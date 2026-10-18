-- ================================================================================================
-- 10  ANALYSIS QUERIES (descriptive, diagnostic, predictive)
-- ================================================================================================
-- Run after files 01 to 09. Nothing here changes data.
-- Each query states the question, then the answer in SQL. See docs/SQL_ANALYSIS_GUIDE.md for how to read them.
-- Predictive queries use PostgreSQL's built-in regression aggregates (regr_slope, regr_intercept, regr_r2):
-- they are transparent trend models, not forecasting packages. Treat them as indications, not guarantees.
-- ================================================================================================

-- =====================================================================
-- A. DESCRIPTIVE: WHAT HAPPENED
-- =====================================================================

-- A1  Revenue, profit and margin by month, with prior year, MoM, YTD and rolling 12 months
SELECT year_month, total_revenue, gross_profit, gross_margin, revenue_py, revenue_yoy_pct, revenue_mom_pct, revenue_ytd, revenue_rolling_12m
FROM bi.m_revenue_trend();

-- A2  Headline figures for one year
SELECT total_revenue, gross_profit, gross_margin, load_count, total_miles, revenue_per_mile, route_cost_per_mile, fuel_cost, avg_mpg
FROM bi.m_finance(p_start := '2024-01-01', p_end := '2024-12-31');

-- A3  Revenue and margin by customer type and freight type
SELECT c.customer_type, c.primary_freight_type, SUM(f.revenue) AS revenue, bi.sdiv(SUM(f.gross_profit), SUM(f.revenue)) AS gross_margin, COUNT(*) AS loads
FROM dw.fact_load_trip f JOIN dw.dim_customer c ON c.customer_id = f.customer_id
GROUP BY c.customer_type, c.primary_freight_type
ORDER BY revenue DESC;

-- A4  Customer concentration: the Pareto, with the share of the top 18 customers
SELECT customer_rank, customer_name, customer_revenue, ROUND(cumulative_revenue_pct * 100, 1) AS cumulative_pct, abc_class
FROM bi.m_customer_scorecard()
ORDER BY customer_rank
LIMIT 25;

SELECT ROUND(100 * SUM(customer_revenue) FILTER (WHERE customer_rank <= 18) / SUM(customer_revenue), 1) AS top_18_share_pct
FROM bi.m_customer_scorecard();

-- A5  Fuel spend and price by state
SELECT location_state, fuel_cost, fuel_gallons, ROUND(avg_price_per_gallon, 3) AS price_per_gallon, ROUND(state_price_vs_fleet_avg, 4) AS price_vs_fleet
FROM bi.m_fuel_by_state()
ORDER BY fuel_cost DESC;

-- A6  Incidents by type and by year, with the rate per million miles
SELECT dim_label AS incident_type, safety_incidents, at_fault_incidents, ROUND(at_fault_pct * 100, 1) AS at_fault_pct, total_claims
FROM bi.m_safety_by('incident_type')
ORDER BY safety_incidents DESC;

SELECT s.dim_label AS year, s.safety_incidents, ROUND(bi.sdiv(s.safety_incidents, f.total_miles) * 1000000, 2) AS incidents_per_1m_miles
FROM bi.m_safety_by('year') s JOIN bi.m_finance_by('year') f ON f.dim_key = s.dim_key
ORDER BY s.dim_key;

-- A7  Loads out and in by city (network balance)
SELECT city, outbound_loads, inbound_loads, lane_balance, ROUND(lane_balance_pct * 100, 1) AS balance_pct
FROM bi.m_city_network()
ORDER BY lane_balance_pct DESC;

-- =====================================================================
-- B. DIAGNOSTIC: WHY IT HAPPENED
-- =====================================================================

-- B1  Cost structure and margin: contribution margin versus an illustrative full-cost margin
--      (driver pay is not in Gross Profit; it uses the Driver Pay per Mile parameter, default $0.60)
SELECT total_revenue, fuel_cost, maintenance_cost_allocated, gross_profit,
       ROUND(gross_margin * 100, 1) AS contribution_margin_pct,
       driver_cost,
       ROUND(bi.sdiv(gross_profit - driver_cost, total_revenue) * 100, 1) AS margin_after_driver_pay_pct,
       ROUND(fuel_cost / total_revenue * 100, 1) AS fuel_share_of_revenue_pct
FROM bi.m_finance();

-- B2  Are drivers really alike? Spread of the main driver metrics
SELECT metric, ROUND(MIN(v), 4) AS min_value, ROUND(MAX(v), 4) AS max_value, ROUND(AVG(v), 4) AS mean,
       ROUND(STDDEV_POP(v), 4) AS stddev, ROUND(bi.sdiv(STDDEV_POP(v), AVG(v)), 4) AS coefficient_of_variation
FROM (
    SELECT 'revenue_trip_based' AS metric, revenue_trip_based AS v FROM bi.m_driver_scorecard()
    UNION ALL SELECT 'avg_mpg', avg_mpg FROM bi.m_driver_scorecard()
    UNION ALL SELECT 'idle_pct', idle_pct FROM bi.m_driver_scorecard()
    UNION ALL SELECT 'driver_on_time_pct', driver_on_time_pct FROM bi.m_driver_scorecard()
) x
GROUP BY metric
ORDER BY metric;

-- B3  Does fuel price vary by month or by state? Compare the spread of the two
SELECT 'by month' AS grouping, COUNT(*) AS groups, ROUND(MIN(avg_price_per_gallon), 3) AS min_price, ROUND(MAX(avg_price_per_gallon), 3) AS max_price,
       ROUND(MAX(avg_price_per_gallon) - MIN(avg_price_per_gallon), 3) AS spread, ROUND(STDDEV_POP(avg_price_per_gallon), 4) AS stddev
FROM bi.m_fuel_by('year_month') WHERE dim_key IS NOT NULL
UNION ALL
SELECT 'by state', COUNT(*), ROUND(MIN(avg_price_per_gallon), 3), ROUND(MAX(avg_price_per_gallon), 3),
       ROUND(MAX(avg_price_per_gallon) - MIN(avg_price_per_gallon), 3), ROUND(STDDEV_POP(avg_price_per_gallon), 4)
FROM bi.m_fuel_by('state') WHERE dim_key IS NOT NULL;

-- B4  Where does on-time delivery fail? Worst facilities, weekdays and customers
SELECT dim_label AS facility, total_deliveries, ROUND(on_time_pct * 100, 1) AS on_time_pct, ROUND(average_detention, 2) AS avg_detention_hrs
FROM bi.m_delivery_by('facility') WHERE total_deliveries >= 50 ORDER BY on_time_pct LIMIT 10;

SELECT dim_label AS weekday, total_deliveries, ROUND(on_time_pct * 100, 1) AS on_time_pct FROM bi.m_delivery_by('day_name') ORDER BY dim_key;

SELECT dim_label AS customer, total_deliveries, late_deliveries, ROUND(on_time_pct * 100, 1) AS on_time_pct
FROM bi.m_delivery_by('customer') WHERE total_deliveries >= 50 ORDER BY late_deliveries DESC LIMIT 10;

-- B5  Does detention explain lateness? Correlation across facilities (about -1 = yes, about 0 = no)
SELECT ROUND(CORR(average_detention, on_time_pct)::numeric, 3) AS corr_detention_vs_on_time, COUNT(*) AS facilities
FROM bi.m_delivery_by('facility') WHERE dim_key IS NOT NULL;

-- B6  How much revenue has no named driver (DRV_UNKNOWN)?
SELECT COUNT(*) FILTER (WHERE driver_id = 'DRV_UNKNOWN') AS unknown_trips, SUM(revenue) FILTER (WHERE driver_id = 'DRV_UNKNOWN') AS unknown_revenue,
       ROUND(100 * bi.sdiv(SUM(revenue) FILTER (WHERE driver_id = 'DRV_UNKNOWN'), SUM(revenue)), 2) AS share_of_revenue_pct
FROM dw.fact_load_trip;

-- B7  Does the maintenance allocation reconcile month by month?
SELECT r.month_start, r.maintenance_cost, ROUND(SUM(f.maint_alloc), 2) AS allocated, ROUND(r.maintenance_cost - COALESCE(SUM(f.maint_alloc), 0), 2) AS difference
FROM dw.month_maint_ratio r
LEFT JOIN dw.fact_load_trip f ON DATE_TRUNC('month', f.load_date)::date = r.month_start
GROUP BY r.month_start, r.maintenance_cost
ORDER BY r.month_start;

-- B8  Margin spread across customers and routes (after the miles-based maintenance allocation)
SELECT 'customers' AS level, COUNT(*) AS n, ROUND(MIN(customer_margin_pct) * 100, 1) AS min_margin_pct, ROUND(MAX(customer_margin_pct) * 100, 1) AS max_margin_pct, ROUND(STDDEV_POP(customer_margin_pct) * 100, 2) AS stddev_pts
FROM bi.m_customer_scorecard()
UNION ALL
SELECT 'routes', COUNT(*), ROUND(MIN(gross_margin) * 100, 1), ROUND(MAX(gross_margin) * 100, 1), ROUND(STDDEV_POP(gross_margin) * 100, 2)
FROM bi.m_route_scorecard();

-- =====================================================================
-- C. PREDICTIVE: WHAT IS LIKELY NEXT
-- =====================================================================

-- C1  Linear trend of monthly revenue and a six-month projection (regr_slope, regr_intercept, regr_r2)
--      A low r2 means the trend explains little; read the projection as a flat run-rate.
WITH m AS (
    SELECT ROW_NUMBER() OVER (ORDER BY year_month) AS t, year_month, total_revenue
    FROM bi.m_revenue_trend()
), fit AS (
    SELECT regr_slope(total_revenue, t) AS slope, regr_intercept(total_revenue, t) AS intercept,
           regr_r2(total_revenue, t) AS r2, MAX(t) AS last_t, MAX(year_month) AS last_month
    FROM m
)
SELECT TO_CHAR(TO_DATE(fit.last_month || '-01', 'YYYY-MM-DD') + ((k - fit.last_t)::integer * INTERVAL '1 month'), 'YYYY-MM') AS month,
       ROUND((fit.intercept + fit.slope * k)::numeric, 0) AS projected_revenue,
       ROUND(fit.slope::numeric, 0) AS monthly_trend, ROUND(fit.r2::numeric, 3) AS r2
FROM fit CROSS JOIN LATERAL generate_series(fit.last_t + 1, fit.last_t + 6) AS k
ORDER BY k;

-- C2  Seasonality index: average revenue of each calendar month against the overall monthly average
WITH m AS (SELECT month_number, month_name, AVG(total_revenue) AS avg_revenue FROM bi.m_revenue_trend() GROUP BY month_number, month_name)
SELECT month_name, ROUND(avg_revenue, 0) AS avg_revenue, ROUND(avg_revenue / AVG(avg_revenue) OVER (), 3) AS seasonality_index
FROM m ORDER BY month_number;

-- C3  Customer churn risk: days since the last load against the customer's usual gap between loads
WITH g AS (
    SELECT customer_id, load_date, load_date - LAG(load_date) OVER (PARTITION BY customer_id ORDER BY load_date) AS gap_days
    FROM dw.fact_load_trip
), a AS (
    SELECT customer_id, COUNT(*) AS loads, AVG(gap_days) AS avg_gap_days, MAX(load_date) AS last_load_date FROM g GROUP BY customer_id
)
SELECT a.customer_id, c.customer_name, a.loads, ROUND(a.avg_gap_days, 1) AS avg_gap_days,
       dw.data_as_of() - a.last_load_date AS days_since_last_load,
       ROUND(bi.sdiv(dw.data_as_of() - a.last_load_date, a.avg_gap_days), 2) AS overdue_ratio
FROM a JOIN dw.dim_customer c ON c.customer_id = a.customer_id
WHERE a.loads >= 5
ORDER BY overdue_ratio DESC NULLS LAST
LIMIT 25;

-- C4  Maintenance due: miles since the last service against the truck's usual miles between services
WITH ls AS (
    SELECT truck_id, MAX(maintenance_date) AS last_service_date, COUNT(*) AS events FROM dw.fact_maintenance_event GROUP BY truck_id
), u AS (
    SELECT truck_id, SUM(miles) AS total_miles, MIN(load_date) AS first_d, MAX(load_date) AS last_d
    FROM dw.fact_load_trip WHERE truck_id IS NOT NULL GROUP BY truck_id
), sn AS (
    SELECT l.truck_id, SUM(l.miles) AS miles_since
    FROM dw.fact_load_trip l JOIN ls ON ls.truck_id = l.truck_id AND l.load_date > ls.last_service_date
    GROUP BY l.truck_id
)
SELECT u.truck_id,
       ROUND(bi.sdiv(u.total_miles, ls.events)) AS avg_miles_between_service,
       ROUND(COALESCE(sn.miles_since, 0)) AS miles_since_last_service,
       ROUND(bi.sdiv(u.total_miles, u.last_d - u.first_d + 1)) AS miles_per_day,
       ROUND(bi.sdiv(bi.sdiv(u.total_miles, ls.events) - COALESCE(sn.miles_since, 0), bi.sdiv(u.total_miles, u.last_d - u.first_d + 1))) AS predicted_days_to_service
FROM u JOIN ls ON ls.truck_id = u.truck_id LEFT JOIN sn ON sn.truck_id = u.truck_id
ORDER BY predicted_days_to_service
LIMIT 25;

-- C5  Scenario grid: gross profit for rate changes (rows) and fuel price changes (columns), from today's totals
WITH o AS (SELECT * FROM bi.m_finance())
SELECT ROUND(r.rate_change * 100) AS rate_change_pct, ROUND(f.fuel_change * 100) AS fuel_change_pct,
       ROUND(o.total_revenue * (1 + r.rate_change) - (o.total_cost + o.fuel_cost * f.fuel_change), 0) AS gross_profit,
       ROUND(bi.sdiv(o.total_revenue * (1 + r.rate_change) - (o.total_cost + o.fuel_cost * f.fuel_change), o.total_revenue * (1 + r.rate_change)) * 100, 1) AS margin_pct
FROM o
CROSS JOIN generate_series(-0.10, 0.20, 0.05) AS r(rate_change)
CROSS JOIN generate_series(-0.20, 0.30, 0.10) AS f(fuel_change)
ORDER BY 1, 2;

-- C6  Fuel savings from better MPG: gallons and dollars saved if the fleet reached each target
WITH o AS (SELECT * FROM bi.m_finance())
SELECT t.target_mpg, ROUND(o.fuel_gallons_used - o.total_miles / t.target_mpg) AS gallons_saved,
       ROUND((o.fuel_gallons_used - o.total_miles / t.target_mpg) * bi.sdiv(o.fuel_cost, o.fuel_gallons)) AS dollars_saved
FROM o CROSS JOIN generate_series(6.5, 8.0, 0.5) AS t(target_mpg)
ORDER BY t.target_mpg;

