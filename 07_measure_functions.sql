-- ================================================================================================
-- 07  MEASURE FUNCTIONS (schema bi)
-- ================================================================================================
-- One function pack per business area. Every column is a DAX measure of the report, named in snake_case
-- (Total Revenue = total_revenue, On-Time % = on_time_pct, 7 Day Avg = loads_booked_7day_avg).
-- docs/SQL_ANALYSIS_GUIDE.md lists every DAX measure and the function column that replaces it.
--
-- All functions take the same filter arguments (NULL = All):
--   p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking
-- plus p_facility, p_incident_type, p_state or p_type where the area needs one.
-- Overall packs return one row. By-dimension packs (m_*_by) return one row per group:
--   SELECT * FROM bi.m_finance_by('year_month', p_start := '2024-01-01');
-- Scorecards (m_*_scorecard) return one row per customer, driver, truck or route, with ranks, flags and colours.
-- Types are cast explicitly so every function returns exactly the declared columns.
-- ================================================================================================

-- Measure: Fleet Maint Cost per Mile (all maintenance in the window over all miles in the window)
CREATE OR REPLACE FUNCTION bi.fleet_maint_cost_per_mile(p_start date DEFAULT NULL, p_end date DEFAULT NULL)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT bi.sdiv(
        (SELECT SUM(m.total_cost) FROM bi.fn_scope_maintenance(p_start, p_end) m),
        (SELECT SUM(l.miles) FROM bi.fn_scope_load(p_start, p_end) l))
$$;

-- Finance and volume measures: revenue, miles, fuel, allocated maintenance, Gross Profit, margins, per-mile figures, MPG, idle, route and pricing ratios.
CREATE OR REPLACE FUNCTION bi.m_finance(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    total_revenue numeric,
    customer_revenue numeric,
    route_revenue numeric,
    load_count bigint,
    loads_booked bigint,
    loads_delivered bigint,
    cancelled_loads bigint,
    trip_count bigint,
    total_miles numeric,
    expected_miles numeric,
    expected_linehaul_revenue numeric,
    fuel_cost numeric,
    fuel_gallons_used numeric,
    fuel_gallons numeric,
    idle_hours numeric,
    duration_hours numeric,
    maintenance_cost_allocated numeric,
    gross_profit numeric,
    customer_margin numeric,
    driver_cost numeric,
    total_cost numeric,
    total_operating_cost numeric,
    revenue_trip_based numeric,
    gross_margin numeric,
    customer_margin_pct numeric,
    revenue_per_mile numeric,
    revenue_per_load numeric,
    route_cost_per_mile numeric,
    profit_per_mile numeric,
    cost_per_mile numeric,
    avg_mpg numeric,
    idle_pct numeric,
    distance_variance_pct numeric,
    rate_realization_pct numeric,
    cancellation_rate numeric,
    average_transit_time numeric,
    active_customers bigint,
    drivers_with_trips bigint,
    trailers_used bigint,
    delivery_volume_share numeric,
    fleet_maint_cost_per_mile numeric)
LANGUAGE sql STABLE AS $$
    SELECT
        (SUM(s.revenue))::numeric AS total_revenue,
        (SUM(s.revenue))::numeric AS customer_revenue,
        (SUM(s.revenue))::numeric AS route_revenue,
        (COUNT(*))::bigint AS load_count,
        (COUNT(*))::bigint AS loads_booked,
        (COUNT(*) FILTER (WHERE s.load_status = 'Delivered'))::bigint AS loads_delivered,
        (COUNT(*) FILTER (WHERE s.load_status = 'Cancelled'))::bigint AS cancelled_loads,
        (COUNT(s.trip_id))::bigint AS trip_count,
        (SUM(s.miles))::numeric AS total_miles,
        (SUM(s.expected_miles))::numeric AS expected_miles,
        (SUM(s.expected_linehaul_revenue))::numeric AS expected_linehaul_revenue,
        (SUM(s.fuel_cost))::numeric AS fuel_cost,
        (SUM(s.fuel_gallons_used))::numeric AS fuel_gallons_used,
        (SUM(s.fuel_gallons_purchased))::numeric AS fuel_gallons,
        (SUM(s.idle_hours))::numeric AS idle_hours,
        (SUM(s.duration_hours))::numeric AS duration_hours,
        (SUM(s.maint_alloc))::numeric AS maintenance_cost_allocated,
        (SUM(s.gross_profit))::numeric AS gross_profit,
        (SUM(s.gross_profit))::numeric AS customer_margin,
        (SUM(s.miles) * bi.param('driver_pay_per_mile'))::numeric AS driver_cost,
        (SUM(s.revenue) - SUM(s.gross_profit))::numeric AS total_cost,
        (SUM(s.fuel_cost) + SUM(s.miles) * bi.param('driver_pay_per_mile') + SUM(s.maint_alloc))::numeric AS total_operating_cost,
        (SUM(s.revenue) FILTER (WHERE s.trip_id IS NOT NULL))::numeric AS revenue_trip_based,
        (bi.sdiv(SUM(s.gross_profit), SUM(s.revenue)))::numeric AS gross_margin,
        (bi.sdiv(SUM(s.gross_profit), SUM(s.revenue)))::numeric AS customer_margin_pct,
        (bi.sdiv(SUM(s.revenue), SUM(s.miles)))::numeric AS revenue_per_mile,
        (bi.sdiv(SUM(s.revenue), COUNT(*)))::numeric AS revenue_per_load,
        (bi.sdiv(SUM(s.revenue) - SUM(s.gross_profit), SUM(s.miles)))::numeric AS route_cost_per_mile,
        (bi.sdiv(SUM(s.gross_profit), SUM(s.miles)))::numeric AS profit_per_mile,
        (bi.sdiv(SUM(s.fuel_cost) + SUM(s.miles) * bi.param('driver_pay_per_mile') + SUM(s.maint_alloc), SUM(s.miles)))::numeric AS cost_per_mile,
        (bi.sdiv(SUM(s.miles), SUM(s.fuel_gallons_used)))::numeric AS avg_mpg,
        (bi.sdiv(SUM(s.idle_hours), SUM(s.duration_hours)))::numeric AS idle_pct,
        (bi.sdiv(SUM(s.miles) - SUM(s.expected_miles), SUM(s.expected_miles)))::numeric AS distance_variance_pct,
        (bi.sdiv(SUM(s.revenue), SUM(s.expected_linehaul_revenue)))::numeric AS rate_realization_pct,
        (bi.sdiv(COUNT(*) FILTER (WHERE s.load_status = 'Cancelled'), COUNT(*)))::numeric AS cancellation_rate,
        (AVG(s.duration_hours))::numeric AS average_transit_time,
        (COUNT(DISTINCT s.customer_id))::bigint AS active_customers,
        (COUNT(DISTINCT s.driver_id))::bigint AS drivers_with_trips,
        (COUNT(DISTINCT s.trailer_id))::bigint AS trailers_used,
        (bi.sdiv(COUNT(*), SUM(COUNT(*)) OVER ()))::numeric AS delivery_volume_share,
        (bi.fleet_maint_cost_per_mile(p_start, p_end))::numeric AS fleet_maint_cost_per_mile
    FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s
$$;

-- Finance measures grouped by any dimension (Dashboard 1, 2, 7 charts).
-- p_dimension: year, quarter, month_number, year_month, day_name, customer, customer_type, freight_type, route, origin_city, destination_city, booking_type, load_type, driver, tenure_band, truck, truck_make, model_year, truck_age_band
CREATE OR REPLACE FUNCTION bi.m_finance_by(
    p_dimension text, p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    dim_key text,
    dim_label text,
    total_revenue numeric,
    customer_revenue numeric,
    route_revenue numeric,
    load_count bigint,
    loads_booked bigint,
    loads_delivered bigint,
    cancelled_loads bigint,
    trip_count bigint,
    total_miles numeric,
    expected_miles numeric,
    expected_linehaul_revenue numeric,
    fuel_cost numeric,
    fuel_gallons_used numeric,
    fuel_gallons numeric,
    idle_hours numeric,
    duration_hours numeric,
    maintenance_cost_allocated numeric,
    gross_profit numeric,
    customer_margin numeric,
    driver_cost numeric,
    total_cost numeric,
    total_operating_cost numeric,
    revenue_trip_based numeric,
    gross_margin numeric,
    customer_margin_pct numeric,
    revenue_per_mile numeric,
    revenue_per_load numeric,
    route_cost_per_mile numeric,
    profit_per_mile numeric,
    cost_per_mile numeric,
    avg_mpg numeric,
    idle_pct numeric,
    distance_variance_pct numeric,
    rate_realization_pct numeric,
    cancellation_rate numeric,
    average_transit_time numeric,
    active_customers bigint,
    drivers_with_trips bigint,
    trailers_used bigint,
    delivery_volume_share numeric)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_key text;
    v_label text;
BEGIN
    v_key := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'lpad(dd.month_number::text, 2, ''0'')'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'day_name' THEN 'dd.day_number'
        WHEN 'customer' THEN 's.customer_id'
        WHEN 'customer_type' THEN 'c.customer_type'
        WHEN 'freight_type' THEN 'c.primary_freight_type'
        WHEN 'route' THEN 's.route_id'
        WHEN 'origin_city' THEN 's.origin_city'
        WHEN 'destination_city' THEN 's.destination_city'
        WHEN 'booking_type' THEN 's.booking_type'
        WHEN 'load_type' THEN 's.load_type'
        WHEN 'driver' THEN 's.driver_id'
        WHEN 'tenure_band' THEN 'dr.tenure_band_sort'
        WHEN 'truck' THEN 's.truck_id'
        WHEN 'truck_make' THEN 'tk.make'
        WHEN 'model_year' THEN 'tk.model_year'
        WHEN 'truck_age_band' THEN 'tk.truck_age_band'
    END;
    v_label := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'dd.month_name'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'day_name' THEN 'dd.day_name'
        WHEN 'customer' THEN 'c.customer_name'
        WHEN 'customer_type' THEN 'c.customer_type'
        WHEN 'freight_type' THEN 'c.primary_freight_type'
        WHEN 'route' THEN 'r.route_name'
        WHEN 'origin_city' THEN 's.origin_city'
        WHEN 'destination_city' THEN 's.destination_city'
        WHEN 'booking_type' THEN 's.booking_type'
        WHEN 'load_type' THEN 's.load_type'
        WHEN 'driver' THEN 'dr.driver_name'
        WHEN 'tenure_band' THEN 'dr.tenure_band'
        WHEN 'truck' THEN 's.truck_id'
        WHEN 'truck_make' THEN 'tk.make'
        WHEN 'model_year' THEN 'tk.model_year'
        WHEN 'truck_age_band' THEN 'tk.truck_age_band'
    END;
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Unknown dimension %. Allowed: year, quarter, month_number, year_month, day_name, customer, customer_type, freight_type, route, origin_city, destination_city, booking_type, load_type, driver, tenure_band, truck, truck_make, model_year, truck_age_band', p_dimension;
    END IF;
    RETURN QUERY EXECUTE format($q$
        SELECT (%1$s)::text AS dim_key, (%2$s)::text AS dim_label,
               (SUM(s.revenue))::numeric AS total_revenue,
               (SUM(s.revenue))::numeric AS customer_revenue,
               (SUM(s.revenue))::numeric AS route_revenue,
               (COUNT(*))::bigint AS load_count,
               (COUNT(*))::bigint AS loads_booked,
               (COUNT(*) FILTER (WHERE s.load_status = 'Delivered'))::bigint AS loads_delivered,
               (COUNT(*) FILTER (WHERE s.load_status = 'Cancelled'))::bigint AS cancelled_loads,
               (COUNT(s.trip_id))::bigint AS trip_count,
               (SUM(s.miles))::numeric AS total_miles,
               (SUM(s.expected_miles))::numeric AS expected_miles,
               (SUM(s.expected_linehaul_revenue))::numeric AS expected_linehaul_revenue,
               (SUM(s.fuel_cost))::numeric AS fuel_cost,
               (SUM(s.fuel_gallons_used))::numeric AS fuel_gallons_used,
               (SUM(s.fuel_gallons_purchased))::numeric AS fuel_gallons,
               (SUM(s.idle_hours))::numeric AS idle_hours,
               (SUM(s.duration_hours))::numeric AS duration_hours,
               (SUM(s.maint_alloc))::numeric AS maintenance_cost_allocated,
               (SUM(s.gross_profit))::numeric AS gross_profit,
               (SUM(s.gross_profit))::numeric AS customer_margin,
               (SUM(s.miles) * bi.param('driver_pay_per_mile'))::numeric AS driver_cost,
               (SUM(s.revenue) - SUM(s.gross_profit))::numeric AS total_cost,
               (SUM(s.fuel_cost) + SUM(s.miles) * bi.param('driver_pay_per_mile') + SUM(s.maint_alloc))::numeric AS total_operating_cost,
               (SUM(s.revenue) FILTER (WHERE s.trip_id IS NOT NULL))::numeric AS revenue_trip_based,
               (bi.sdiv(SUM(s.gross_profit), SUM(s.revenue)))::numeric AS gross_margin,
               (bi.sdiv(SUM(s.gross_profit), SUM(s.revenue)))::numeric AS customer_margin_pct,
               (bi.sdiv(SUM(s.revenue), SUM(s.miles)))::numeric AS revenue_per_mile,
               (bi.sdiv(SUM(s.revenue), COUNT(*)))::numeric AS revenue_per_load,
               (bi.sdiv(SUM(s.revenue) - SUM(s.gross_profit), SUM(s.miles)))::numeric AS route_cost_per_mile,
               (bi.sdiv(SUM(s.gross_profit), SUM(s.miles)))::numeric AS profit_per_mile,
               (bi.sdiv(SUM(s.fuel_cost) + SUM(s.miles) * bi.param('driver_pay_per_mile') + SUM(s.maint_alloc), SUM(s.miles)))::numeric AS cost_per_mile,
               (bi.sdiv(SUM(s.miles), SUM(s.fuel_gallons_used)))::numeric AS avg_mpg,
               (bi.sdiv(SUM(s.idle_hours), SUM(s.duration_hours)))::numeric AS idle_pct,
               (bi.sdiv(SUM(s.miles) - SUM(s.expected_miles), SUM(s.expected_miles)))::numeric AS distance_variance_pct,
               (bi.sdiv(SUM(s.revenue), SUM(s.expected_linehaul_revenue)))::numeric AS rate_realization_pct,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.load_status = 'Cancelled'), COUNT(*)))::numeric AS cancellation_rate,
               (AVG(s.duration_hours))::numeric AS average_transit_time,
               (COUNT(DISTINCT s.customer_id))::bigint AS active_customers,
               (COUNT(DISTINCT s.driver_id))::bigint AS drivers_with_trips,
               (COUNT(DISTINCT s.trailer_id))::bigint AS trailers_used,
               (bi.sdiv(COUNT(*), SUM(COUNT(*)) OVER ()))::numeric AS delivery_volume_share
        FROM bi.fn_scope_load($1, $2, $3, $4, $5, $6, $7) s
        LEFT JOIN dw.dim_date dd ON dd.full_date = s.load_date
        LEFT JOIN dw.dim_customer c ON c.customer_id = s.customer_id
        LEFT JOIN dw.dim_route r ON r.route_id = s.route_id
        LEFT JOIN dw.dim_driver dr ON dr.driver_id = s.driver_id
        LEFT JOIN dw.dim_truck tk ON tk.truck_id = s.truck_id
        GROUP BY 1, 2
        ORDER BY 1
    $q$, v_key, v_label)
    USING p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking;
END;
$fn$;

-- Prior-year comparison for the selected window (SAMEPERIODLASTYEAR). With no dates it compares each year with the one before, so pass dates for a headline YoY.
CREATE OR REPLACE FUNCTION bi.m_time_overall(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    revenue_py numeric,
    revenue_yoy_pct numeric,
    gross_profit_py numeric,
    gross_profit_yoy_pct numeric)
LANGUAGE sql STABLE AS $$
    WITH cur AS (
        SELECT SUM(s.revenue) AS rev, SUM(s.gross_profit) AS gp FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s
    ), py AS (
        SELECT SUM(s.revenue) AS rev, SUM(s.gross_profit) AS gp FROM bi.fn_scope_load((COALESCE(p_start, (SELECT MIN(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, (COALESCE(p_end, (SELECT MAX(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, p_customer, p_route, p_driver, p_truck, p_booking) s
    )
    SELECT
        (py.rev)::numeric AS revenue_py,
        (bi.sdiv(cur.rev - py.rev, py.rev))::numeric AS revenue_yoy_pct,
        (py.gp)::numeric AS gross_profit_py,
        (bi.sdiv(cur.gp - py.gp, ABS(py.gp)))::numeric AS gross_profit_yoy_pct
    FROM cur CROSS JOIN py
$$;

-- Monthly revenue with prior year, YoY, MoM, YTD and rolling 12 months. Rolling 12 needs 12 months in the window.
CREATE OR REPLACE FUNCTION bi.m_revenue_trend(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    year integer,
    quarter text,
    month_number integer,
    month_name text,
    year_month text,
    total_revenue numeric,
    gross_profit numeric,
    gross_margin numeric,
    revenue_py numeric,
    revenue_yoy_pct numeric,
    gross_profit_py numeric,
    gross_profit_yoy_pct numeric,
    revenue_mom_pct numeric,
    revenue_ytd numeric,
    revenue_rolling_12m numeric)
LANGUAGE sql STABLE AS $$
    WITH cur AS (
        SELECT dd.year, dd.quarter, dd.month_number, dd.month_name, dd.year_month,
               SUM(s.revenue) AS rev, SUM(s.gross_profit) AS gp
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s
        JOIN dw.dim_date dd ON dd.full_date = s.load_date
        GROUP BY dd.year, dd.quarter, dd.month_number, dd.month_name, dd.year_month
    ), py AS (
        SELECT dd.year + 1 AS year, dd.month_number, SUM(s.revenue) AS rev, SUM(s.gross_profit) AS gp
        FROM bi.fn_scope_load((COALESCE(p_start, (SELECT MIN(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, (COALESCE(p_end, (SELECT MAX(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, p_customer, p_route, p_driver, p_truck, p_booking) s
        JOIN dw.dim_date dd ON dd.full_date = s.load_date
        GROUP BY dd.year + 1, dd.month_number
    )
    SELECT
        (cur.year)::integer AS year,
        (cur.quarter)::text AS quarter,
        (cur.month_number)::integer AS month_number,
        (cur.month_name)::text AS month_name,
        (cur.year_month)::text AS year_month,
        (cur.rev)::numeric AS total_revenue,
        (cur.gp)::numeric AS gross_profit,
        (bi.sdiv(cur.gp, cur.rev))::numeric AS gross_margin,
        (py.rev)::numeric AS revenue_py,
        (bi.sdiv(cur.rev - py.rev, py.rev))::numeric AS revenue_yoy_pct,
        (py.gp)::numeric AS gross_profit_py,
        (bi.sdiv(cur.gp - py.gp, ABS(py.gp)))::numeric AS gross_profit_yoy_pct,
        (bi.sdiv(cur.rev - LAG(cur.rev) OVER (ORDER BY cur.year_month), LAG(cur.rev) OVER (ORDER BY cur.year_month)))::numeric AS revenue_mom_pct,
        (SUM(cur.rev) OVER (PARTITION BY cur.year ORDER BY cur.month_number))::numeric AS revenue_ytd,
        (SUM(cur.rev) OVER (ORDER BY cur.year_month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW))::numeric AS revenue_rolling_12m
    FROM cur LEFT JOIN py ON py.year = cur.year AND py.month_number = cur.month_number
    ORDER BY cur.year_month
$$;

-- Loads booked per day with the 7-day average (7 Day Avg). Days with no loads are skipped, as AVERAGEX does.
CREATE OR REPLACE FUNCTION bi.m_loads_daily(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    load_date date,
    loads_booked bigint,
    loads_booked_7day_avg numeric)
LANGUAGE sql STABLE AS $$
    WITH d AS (SELECT s.load_date, COUNT(*) AS n FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s GROUP BY s.load_date)
    SELECT
        (d.load_date)::date AS load_date,
        (d.n)::bigint AS loads_booked,
        (AVG(d.n) OVER (ORDER BY d.load_date RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW))::numeric AS loads_booked_7day_avg
    FROM d
    ORDER BY d.load_date
$$;

-- Service measures: on-time, detention, cancellations, transit time and the Customer Service Score (Dashboard 2 cards).
CREATE OR REPLACE FUNCTION bi.m_service(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_facility text DEFAULT NULL)
RETURNS TABLE (
    loads_booked bigint,
    loads_delivered bigint,
    cancelled_loads bigint,
    cancellation_rate numeric,
    average_transit_time numeric,
    revenue_per_load numeric,
    total_deliveries bigint,
    on_time_deliveries bigint,
    late_deliveries bigint,
    on_time_pct numeric,
    pct_on_time_deliveries numeric,
    driver_on_time_pct numeric,
    customer_on_time_pct numeric,
    on_time_vs_target numeric,
    on_time_status_color text,
    stop_count bigint,
    detention_hours numeric,
    average_detention numeric,
    detention_cost numeric,
    detained_stops_pct numeric,
    detention_cost_per_load numeric,
    customer_service_score numeric)
LANGUAGE sql STABLE AS $$
    WITH f AS (
        SELECT * FROM bi.m_finance(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking)
    ), d AS (
        SELECT
        COUNT(*) FILTER (WHERE s.is_delivery) AS total_deliveries,
        COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE) AS on_time_deliveries,
        COUNT(*) FILTER (WHERE s.is_delivery) - COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE) AS late_deliveries,
        bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) AS on_time_pct,
        bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) AS pct_on_time_deliveries,
        bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) AS driver_on_time_pct,
        bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) AS customer_on_time_pct,
        bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) - bi.param('on_time_target') AS on_time_vs_target,
        bi.f_color_on_time(bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery))) AS on_time_status_color,
        COUNT(*) AS stop_count,
        SUM(s.detention_hours) AS detention_hours,
        AVG(s.detention_minutes) / 60.0 AS average_detention,
        SUM(s.detention_hours) * bi.param('detention_rate_per_hour') AS detention_cost,
        bi.sdiv(COUNT(*) FILTER (WHERE s.detention_minutes > 0), COUNT(*)) AS detained_stops_pct
        FROM bi.fn_scope_delivery(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_facility) s
    )
    SELECT
        (f.load_count)::bigint AS loads_booked,
        (f.loads_delivered)::bigint AS loads_delivered,
        (f.cancelled_loads)::bigint AS cancelled_loads,
        (f.cancellation_rate)::numeric AS cancellation_rate,
        (f.average_transit_time)::numeric AS average_transit_time,
        (f.revenue_per_load)::numeric AS revenue_per_load,
        (d.total_deliveries)::bigint AS total_deliveries,
        (d.on_time_deliveries)::bigint AS on_time_deliveries,
        (d.late_deliveries)::bigint AS late_deliveries,
        (d.on_time_pct)::numeric AS on_time_pct,
        (d.on_time_pct)::numeric AS pct_on_time_deliveries,
        (d.on_time_pct)::numeric AS driver_on_time_pct,
        (d.on_time_pct)::numeric AS customer_on_time_pct,
        (d.on_time_vs_target)::numeric AS on_time_vs_target,
        (d.on_time_status_color)::text AS on_time_status_color,
        (d.stop_count)::bigint AS stop_count,
        (d.detention_hours)::numeric AS detention_hours,
        (d.average_detention)::numeric AS average_detention,
        (d.detention_cost)::numeric AS detention_cost,
        (d.detained_stops_pct)::numeric AS detained_stops_pct,
        (bi.sdiv(d.detention_cost, f.load_count))::numeric AS detention_cost_per_load,
        (bi.f_service_score(d.on_time_pct, f.cancellation_rate, d.detained_stops_pct))::numeric AS customer_service_score
    FROM f CROSS JOIN d
$$;

-- Delivery and detention measures grouped by any dimension (on-time trend, facility charts, detention histogram).
-- p_dimension: year, quarter, month_number, year_month, day_name, customer, route, driver, booking_type, facility, facility_city, facility_state, detention_bucket
CREATE OR REPLACE FUNCTION bi.m_delivery_by(
    p_dimension text, p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_facility text DEFAULT NULL)
RETURNS TABLE (
    dim_key text,
    dim_label text,
    total_deliveries bigint,
    on_time_deliveries bigint,
    late_deliveries bigint,
    on_time_pct numeric,
    pct_on_time_deliveries numeric,
    driver_on_time_pct numeric,
    customer_on_time_pct numeric,
    on_time_vs_target numeric,
    on_time_status_color text,
    stop_count bigint,
    detention_hours numeric,
    average_detention numeric,
    detention_cost numeric,
    detained_stops_pct numeric)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_key text;
    v_label text;
BEGIN
    v_key := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'lpad(dd.month_number::text, 2, ''0'')'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'day_name' THEN 'dd.day_number'
        WHEN 'customer' THEN 's.customer_id'
        WHEN 'route' THEN 's.route_id'
        WHEN 'driver' THEN 's.driver_id'
        WHEN 'booking_type' THEN 's.booking_type'
        WHEN 'facility' THEN 's.facility_id'
        WHEN 'facility_city' THEN 'fa.city'
        WHEN 'facility_state' THEN 'fa.state'
        WHEN 'detention_bucket' THEN 's.detention_bucket_sort'
    END;
    v_label := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'dd.month_name'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'day_name' THEN 'dd.day_name'
        WHEN 'customer' THEN 'c.customer_name'
        WHEN 'route' THEN 'r.route_name'
        WHEN 'driver' THEN 'dr.driver_name'
        WHEN 'booking_type' THEN 's.booking_type'
        WHEN 'facility' THEN 'fa.facility_name'
        WHEN 'facility_city' THEN 'fa.city'
        WHEN 'facility_state' THEN 'fa.state'
        WHEN 'detention_bucket' THEN 's.detention_bucket'
    END;
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Unknown dimension %. Allowed: year, quarter, month_number, year_month, day_name, customer, route, driver, booking_type, facility, facility_city, facility_state, detention_bucket', p_dimension;
    END IF;
    RETURN QUERY EXECUTE format($q$
        SELECT (%1$s)::text AS dim_key, (%2$s)::text AS dim_label,
               (COUNT(*) FILTER (WHERE s.is_delivery))::bigint AS total_deliveries,
               (COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE))::bigint AS on_time_deliveries,
               (COUNT(*) FILTER (WHERE s.is_delivery) - COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE))::bigint AS late_deliveries,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)))::numeric AS on_time_pct,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)))::numeric AS pct_on_time_deliveries,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)))::numeric AS driver_on_time_pct,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)))::numeric AS customer_on_time_pct,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) - bi.param('on_time_target'))::numeric AS on_time_vs_target,
               (bi.f_color_on_time(bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery))))::text AS on_time_status_color,
               (COUNT(*))::bigint AS stop_count,
               (SUM(s.detention_hours))::numeric AS detention_hours,
               (AVG(s.detention_minutes) / 60.0)::numeric AS average_detention,
               (SUM(s.detention_hours) * bi.param('detention_rate_per_hour'))::numeric AS detention_cost,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.detention_minutes > 0), COUNT(*)))::numeric AS detained_stops_pct
        FROM bi.fn_scope_delivery($1, $2, $3, $4, $5, $6, $7, $8) s
        LEFT JOIN dw.dim_date dd ON dd.full_date = s.load_date
        LEFT JOIN dw.dim_customer c ON c.customer_id = s.customer_id
        LEFT JOIN dw.dim_route r ON r.route_id = s.route_id
        LEFT JOIN dw.dim_driver dr ON dr.driver_id = s.driver_id
        LEFT JOIN dw.dim_facility fa ON fa.facility_id = s.facility_id
        GROUP BY 1, 2
        ORDER BY 1
    $q$, v_key, v_label)
    USING p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_facility;
END;
$fn$;

-- Driver-level inputs aggregated for the whole fleet; the fleet Driver Score is the reference for the score colour.
CREATE OR REPLACE FUNCTION bi.m_driver_fleet(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    total_miles numeric,
    avg_mpg numeric,
    idle_pct numeric,
    on_time_pct numeric,
    incidents_per_1m_miles numeric,
    fleet_driver_score numeric)
LANGUAGE sql STABLE AS $$
    WITH f AS (
        SELECT SUM(s.miles) AS miles, bi.sdiv(SUM(s.miles), SUM(s.fuel_gallons_used)) AS mpg,
               bi.sdiv(SUM(s.idle_hours), SUM(s.duration_hours)) AS idle
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s WHERE s.driver_id IS NOT NULL
    ), d AS (
        SELECT bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) AS ot
        FROM bi.fn_scope_delivery(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL) s WHERE s.driver_id IS NOT NULL
    ), i AS (
        SELECT COUNT(*) AS n FROM bi.fn_scope_safety(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL) s
    )
    SELECT
        (f.miles)::numeric AS total_miles,
        (f.mpg)::numeric AS avg_mpg,
        (f.idle)::numeric AS idle_pct,
        (d.ot)::numeric AS on_time_pct,
        (bi.sdiv(i.n, f.miles) * 1000000)::numeric AS incidents_per_1m_miles,
        (bi.f_driver_score(d.ot, f.mpg, f.idle, bi.sdiv(i.n, f.miles) * 1000000))::numeric AS fleet_driver_score
    FROM f CROSS JOIN d CROSS JOIN i
$$;

-- One row per driver (DRV_UNKNOWN excluded): score, rank, bucket, colour, Top N flag and the low-miles filter.
CREATE OR REPLACE FUNCTION bi.m_driver_scorecard(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    driver_id text,
    driver_name text,
    employment_status text,
    tenure_band text,
    revenue_trip_based numeric,
    revenue_per_driver numeric,
    trip_count bigint,
    total_miles numeric,
    avg_mpg numeric,
    idle_pct numeric,
    driver_on_time_pct numeric,
    driver_on_time_pct_monthly numeric,
    incidents bigint,
    incidents_per_1m_miles numeric,
    driver_score numeric,
    driver_rank bigint,
    driver_bucket text,
    driver_score_color text,
    top_n_driver_flag integer,
    low_miles_filter integer,
    idle_pct_vs_fleet numeric)
LANGUAGE sql STABLE AS $$
    WITH f AS (
        SELECT s.driver_id, SUM(s.revenue) AS revenue_trip_based, COUNT(s.trip_id) AS trip_count, SUM(s.miles) AS total_miles,
               bi.sdiv(SUM(s.miles), SUM(s.fuel_gallons_used)) AS avg_mpg, bi.sdiv(SUM(s.idle_hours), SUM(s.duration_hours)) AS idle_pct
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s
        WHERE s.driver_id IS NOT NULL AND s.driver_id <> 'DRV_UNKNOWN'
        GROUP BY s.driver_id
    ), d AS (
        SELECT x.driver_id, bi.sdiv(COUNT(*) FILTER (WHERE x.is_delivery AND x.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE x.is_delivery)) AS driver_on_time_pct
        FROM bi.fn_scope_delivery(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL) x WHERE x.driver_id IS NOT NULL GROUP BY x.driver_id
    ), i AS (
        SELECT x.driver_id, COUNT(*) AS incidents FROM bi.fn_scope_safety(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL) x WHERE x.driver_id IS NOT NULL GROUP BY x.driver_id
    ), mm AS (
        SELECT x.driver_id, bi.sdiv(SUM(x.on_time_delivery_rate * x.trips_completed), SUM(x.trips_completed)) AS driver_on_time_pct_monthly
        FROM bi.fn_scope_driver_month(p_start, p_end, p_driver) x GROUP BY x.driver_id
    ), fl AS (
        SELECT * FROM bi.m_driver_fleet(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking)
    ), base AS (
        SELECT f.driver_id, dr.driver_name, dr.employment_status, dr.tenure_band, f.revenue_trip_based, f.trip_count, f.total_miles,
               f.avg_mpg, f.idle_pct, d.driver_on_time_pct, mm.driver_on_time_pct_monthly, COALESCE(i.incidents, 0) AS incidents,
               bi.sdiv(COALESCE(i.incidents, 0), f.total_miles) * 1000000 AS incidents_per_1m_miles
        FROM f
        LEFT JOIN dw.dim_driver dr ON dr.driver_id = f.driver_id
        LEFT JOIN d ON d.driver_id = f.driver_id
        LEFT JOIN i ON i.driver_id = f.driver_id
        LEFT JOIN mm ON mm.driver_id = f.driver_id
    ), scored AS (
        SELECT b.*, bi.f_driver_score(b.driver_on_time_pct, b.avg_mpg, b.idle_pct, b.incidents_per_1m_miles) AS driver_score FROM base b
    )
    SELECT
        (sc.driver_id)::text AS driver_id,
        (sc.driver_name)::text AS driver_name,
        (sc.employment_status)::text AS employment_status,
        (sc.tenure_band)::text AS tenure_band,
        (sc.revenue_trip_based)::numeric AS revenue_trip_based,
        (sc.revenue_trip_based)::numeric AS revenue_per_driver,
        (sc.trip_count)::bigint AS trip_count,
        (sc.total_miles)::numeric AS total_miles,
        (sc.avg_mpg)::numeric AS avg_mpg,
        (sc.idle_pct)::numeric AS idle_pct,
        (sc.driver_on_time_pct)::numeric AS driver_on_time_pct,
        (sc.driver_on_time_pct_monthly)::numeric AS driver_on_time_pct_monthly,
        (sc.incidents)::bigint AS incidents,
        (sc.incidents_per_1m_miles)::numeric AS incidents_per_1m_miles,
        (sc.driver_score)::numeric AS driver_score,
        (DENSE_RANK() OVER (ORDER BY sc.driver_score DESC NULLS LAST))::bigint AS driver_rank,
        (bi.f_driver_bucket(sc.driver_score))::text AS driver_bucket,
        (bi.f_color_driver_score(sc.driver_score, fl.fleet_driver_score))::text AS driver_score_color,
        ((DENSE_RANK() OVER (ORDER BY sc.revenue_trip_based DESC) <= bi.param('top_n'))::integer)::integer AS top_n_driver_flag,
        ((sc.total_miles >= 5000)::integer)::integer AS low_miles_filter,
        (sc.idle_pct - fl.idle_pct)::numeric AS idle_pct_vs_fleet
    FROM scored sc CROSS JOIN fl
$$;

-- Dashboard 3 cards: workforce, productivity, fuel economy, idle, on-time, safety, turnover and tenure.
CREATE OR REPLACE FUNCTION bi.m_driver_overall(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    active_drivers bigint,
    drivers_with_trips bigint,
    miles_per_driver numeric,
    revenue_per_driver numeric,
    avg_mpg numeric,
    idle_pct numeric,
    driver_on_time_pct numeric,
    driver_on_time_pct_monthly numeric,
    incidents_per_1m_miles numeric,
    driver_score numeric,
    drivers_terminated bigint,
    turnover_pct numeric,
    avg_tenure_yrs numeric,
    idle_pct_best_driver numeric,
    idle_pct_worst_driver numeric)
LANGUAGE sql STABLE AS $$
    WITH w AS (
        SELECT COALESCE(p_start, (SELECT MIN(full_date) FROM dw.dim_date)) AS w0,
               COALESCE(p_end, (SELECT MAX(full_date) FROM dw.dim_date)) AS w1
    ), fl AS (
        SELECT * FROM bi.m_driver_fleet(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking)
    ), f AS (
        SELECT COUNT(DISTINCT s.driver_id) AS drivers_with_trips, SUM(s.miles) AS miles, SUM(s.revenue) AS rev
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s WHERE s.driver_id IS NOT NULL
    ), a AS (
        SELECT COUNT(*) FILTER (WHERE dd.employment_status = 'Active') AS active_drivers,
               COUNT(*) FILTER (WHERE dd.termination_date IS NOT NULL AND dd.termination_date BETWEEN w.w0 AND w.w1) AS drivers_terminated,
               AVG((dw.data_as_of() - dd.hire_date) / 365.25) FILTER (WHERE dd.termination_date IS NULL) AS avg_tenure_yrs
        FROM dw.dim_driver dd CROSS JOIN w
        WHERE (p_driver IS NULL OR dd.driver_id = p_driver)
    ), idle AS (
        SELECT MIN(x.idle_pct) AS best, MAX(x.idle_pct) AS worst FROM bi.m_driver_scorecard(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) x
    ), mm AS (
        SELECT bi.sdiv(SUM(x.on_time_delivery_rate * x.trips_completed), SUM(x.trips_completed)) AS v
        FROM bi.fn_scope_driver_month(p_start, p_end, p_driver) x
    )
    SELECT
        (a.active_drivers)::bigint AS active_drivers,
        (f.drivers_with_trips)::bigint AS drivers_with_trips,
        (bi.sdiv(f.miles, f.drivers_with_trips))::numeric AS miles_per_driver,
        (bi.sdiv(f.rev, f.drivers_with_trips))::numeric AS revenue_per_driver,
        (fl.avg_mpg)::numeric AS avg_mpg,
        (fl.idle_pct)::numeric AS idle_pct,
        (fl.on_time_pct)::numeric AS driver_on_time_pct,
        (mm.v)::numeric AS driver_on_time_pct_monthly,
        (fl.incidents_per_1m_miles)::numeric AS incidents_per_1m_miles,
        (fl.fleet_driver_score)::numeric AS driver_score,
        (a.drivers_terminated)::bigint AS drivers_terminated,
        (bi.sdiv(a.drivers_terminated, a.active_drivers + a.drivers_terminated))::numeric AS turnover_pct,
        (a.avg_tenure_yrs)::numeric AS avg_tenure_yrs,
        (idle.best)::numeric AS idle_pct_best_driver,
        (idle.worst)::numeric AS idle_pct_worst_driver
    FROM fl CROSS JOIN f CROSS JOIN a CROSS JOIN idle CROSS JOIN mm
$$;

-- Driver Score by tenure band (computed on band totals, DRV_UNKNOWN excluded).
CREATE OR REPLACE FUNCTION bi.m_driver_by_tenure(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    tenure_band text,
    tenure_band_sort integer,
    drivers_with_trips bigint,
    total_miles numeric,
    avg_mpg numeric,
    idle_pct numeric,
    driver_on_time_pct numeric,
    incidents_per_1m_miles numeric,
    driver_score numeric,
    driver_score_color text)
LANGUAGE sql STABLE AS $$
    WITH f AS (
        SELECT dr.tenure_band, dr.tenure_band_sort, COUNT(DISTINCT s.driver_id) AS drivers, SUM(s.miles) AS miles,
               bi.sdiv(SUM(s.miles), SUM(s.fuel_gallons_used)) AS mpg, bi.sdiv(SUM(s.idle_hours), SUM(s.duration_hours)) AS idle
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s JOIN dw.dim_driver dr ON dr.driver_id = s.driver_id
        WHERE s.driver_id <> 'DRV_UNKNOWN'
        GROUP BY dr.tenure_band, dr.tenure_band_sort
    ), d AS (
        SELECT dr.tenure_band, bi.sdiv(COUNT(*) FILTER (WHERE x.is_delivery AND x.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE x.is_delivery)) AS ot
        FROM bi.fn_scope_delivery(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL) x JOIN dw.dim_driver dr ON dr.driver_id = x.driver_id
        WHERE x.driver_id <> 'DRV_UNKNOWN' GROUP BY dr.tenure_band
    ), i AS (
        SELECT dr.tenure_band, COUNT(*) AS n
        FROM bi.fn_scope_safety(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL) x JOIN dw.dim_driver dr ON dr.driver_id = x.driver_id
        GROUP BY dr.tenure_band
    )
    SELECT
        (f.tenure_band)::text AS tenure_band,
        (f.tenure_band_sort)::integer AS tenure_band_sort,
        (f.drivers)::bigint AS drivers_with_trips,
        (f.miles)::numeric AS total_miles,
        (f.mpg)::numeric AS avg_mpg,
        (f.idle)::numeric AS idle_pct,
        (d.ot)::numeric AS driver_on_time_pct,
        (bi.sdiv(COALESCE(i.n, 0), f.miles) * 1000000)::numeric AS incidents_per_1m_miles,
        (bi.f_driver_score(d.ot, f.mpg, f.idle, bi.sdiv(COALESCE(i.n, 0), f.miles) * 1000000))::numeric AS driver_score,
        (bi.f_color_driver_score(bi.f_driver_score(d.ot, f.mpg, f.idle, bi.sdiv(COALESCE(i.n, 0), f.miles) * 1000000), (SELECT fleet_driver_score FROM bi.m_driver_fleet(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking))))::text AS driver_score_color
    FROM f LEFT JOIN d ON d.tenure_band = f.tenure_band LEFT JOIN i ON i.tenure_band = f.tenure_band
    ORDER BY f.tenure_band_sort
$$;

-- Trips by idle share (Trips[Idle Ratio] and Trips[Idle Band]).
CREATE OR REPLACE FUNCTION bi.m_idle_band(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    idle_band text,
    trip_count bigint)
LANGUAGE sql STABLE AS $$
    WITH t AS (SELECT s.idle_hours / NULLIF(s.duration_hours, 0) AS r FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s WHERE s.trip_id IS NOT NULL)
    SELECT
        (CASE WHEN COALESCE(t.r, 0) < 0.10 THEN '0-10%' WHEN t.r < 0.20 THEN '10-20%' WHEN t.r < 0.30 THEN '20-30%' WHEN t.r < 0.40 THEN '30-40%' ELSE '40%+' END)::text AS idle_band,
        (COUNT(*))::bigint AS trip_count
    FROM t
    GROUP BY 1
    ORDER BY 1
$$;

-- One row per truck: maintenance, utilization, last service, service status and colours, Top N flag.
CREATE OR REPLACE FUNCTION bi.m_truck_scorecard(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_truck text DEFAULT NULL, p_type text DEFAULT NULL)
RETURNS TABLE (
    truck_id text,
    make text,
    model_year integer,
    truck_age integer,
    truck_age_band text,
    truck_status text,
    total_miles numeric,
    revenue_trip_based numeric,
    avg_mpg numeric,
    maintenance_cost numeric,
    labor_cost numeric,
    parts_cost numeric,
    maintenance_events bigint,
    avg_cost_per_event numeric,
    downtime_hours numeric,
    maint_cost_per_mile_actual numeric,
    miles_between_service numeric,
    fleet_utilization_pct numeric,
    last_service_date date,
    days_since_last_service integer,
    service_status text,
    service_status_color text,
    cost_per_mile_color text,
    top_n_truck_flag integer)
LANGUAGE sql STABLE AS $$
    WITH t AS (
        SELECT k.* FROM dw.dim_truck k WHERE (p_truck IS NULL OR k.truck_id = p_truck)
    ), f AS (
        SELECT s.truck_id, SUM(s.miles) AS total_miles, SUM(s.revenue) AS revenue_trip_based,
               bi.sdiv(SUM(s.miles), SUM(s.fuel_gallons_used)) AS avg_mpg
        FROM bi.fn_scope_load(p_start, p_end, NULL, NULL, NULL, p_truck, NULL) s GROUP BY s.truck_id
    ), m AS (
        SELECT s.truck_id,
        SUM(s.total_cost) AS maintenance_cost,
        SUM(s.labor_cost) AS labor_cost,
        SUM(s.parts_cost) AS parts_cost,
        COUNT(*) AS maintenance_events,
        bi.sdiv(SUM(s.total_cost), COUNT(*)) AS avg_cost_per_event,
        SUM(s.downtime_hours) AS downtime_hours,
        MAX(s.maintenance_date) AS last_service_in_scope
        FROM bi.fn_scope_maintenance(p_start, p_end, p_truck, p_type) s GROUP BY s.truck_id
    ), u AS (
        SELECT s.truck_id, AVG(s.utilization_rate) AS fleet_utilization_pct
        FROM bi.fn_scope_truck_month(p_start, p_end, p_truck) s GROUP BY s.truck_id
    ), ls AS (
        SELECT truck_id, MAX(maintenance_date) AS last_service_date FROM dw.fact_maintenance_event GROUP BY truck_id
    ), fleet AS (
        SELECT bi.sdiv(SUM(m.maintenance_cost), SUM(f.total_miles)) AS cost_per_mile FROM m JOIN f ON f.truck_id = m.truck_id
    ), x AS (
        SELECT t.truck_id, t.make, t.model_year, t.truck_age, t.truck_age_band, t.status AS truck_status,
               f.total_miles, f.revenue_trip_based, f.avg_mpg, m.maintenance_cost, m.labor_cost, m.parts_cost,
               m.maintenance_events, m.avg_cost_per_event, m.downtime_hours,
               bi.sdiv(m.maintenance_cost, f.total_miles) AS maint_cost_per_mile_actual,
               bi.sdiv(f.total_miles, m.maintenance_events) AS miles_between_service,
               u.fleet_utilization_pct, ls.last_service_date,
               (dw.data_as_of() - ls.last_service_date)::integer AS days_since_last_service
        FROM t
        LEFT JOIN f ON f.truck_id = t.truck_id
        LEFT JOIN m ON m.truck_id = t.truck_id
        LEFT JOIN u ON u.truck_id = t.truck_id
        LEFT JOIN ls ON ls.truck_id = t.truck_id
    )
    SELECT
        (x.truck_id)::text AS truck_id,
        (x.make)::text AS make,
        (x.model_year)::integer AS model_year,
        (x.truck_age)::integer AS truck_age,
        (x.truck_age_band)::text AS truck_age_band,
        (x.truck_status)::text AS truck_status,
        (x.total_miles)::numeric AS total_miles,
        (x.revenue_trip_based)::numeric AS revenue_trip_based,
        (x.avg_mpg)::numeric AS avg_mpg,
        (x.maintenance_cost)::numeric AS maintenance_cost,
        (x.labor_cost)::numeric AS labor_cost,
        (x.parts_cost)::numeric AS parts_cost,
        (x.maintenance_events)::bigint AS maintenance_events,
        (x.avg_cost_per_event)::numeric AS avg_cost_per_event,
        (x.downtime_hours)::numeric AS downtime_hours,
        (x.maint_cost_per_mile_actual)::numeric AS maint_cost_per_mile_actual,
        (x.miles_between_service)::numeric AS miles_between_service,
        (x.fleet_utilization_pct)::numeric AS fleet_utilization_pct,
        (x.last_service_date)::date AS last_service_date,
        (x.days_since_last_service)::integer AS days_since_last_service,
        (bi.f_service_status(x.days_since_last_service))::text AS service_status,
        (bi.f_color_service_status(bi.f_service_status(x.days_since_last_service)))::text AS service_status_color,
        (bi.f_color_cost_per_mile(x.maint_cost_per_mile_actual, fleet.cost_per_mile))::text AS cost_per_mile_color,
        ((DENSE_RANK() OVER (ORDER BY x.maintenance_cost DESC NULLS LAST) <= bi.param('top_n'))::integer)::integer AS top_n_truck_flag
    FROM x CROSS JOIN fleet
$$;

-- Dashboard 4 cards: fleet size and age, maintenance cost, downtime, availability, overdue trucks, utilization.
CREATE OR REPLACE FUNCTION bi.m_fleet_overall(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_truck text DEFAULT NULL, p_type text DEFAULT NULL)
RETURNS TABLE (
    active_trucks bigint,
    fleet_age_yrs numeric,
    maintenance_cost numeric,
    labor_cost numeric,
    parts_cost numeric,
    maintenance_events bigint,
    avg_cost_per_event numeric,
    downtime_hours numeric,
    maint_cost_per_mile_actual numeric,
    miles_between_service numeric,
    availability_pct numeric,
    overdue_trucks bigint,
    trailer_utilization_pct numeric,
    fleet_utilization_pct numeric,
    utilization_status_color text)
LANGUAGE sql STABLE AS $$
    WITH tr AS (
        SELECT COUNT(*) FILTER (WHERE k.status = 'Active') AS active_trucks, AVG(k.truck_age) AS fleet_age_yrs
        FROM dw.dim_truck k WHERE (p_truck IS NULL OR k.truck_id = p_truck)
    ), m AS (
        SELECT
        SUM(s.total_cost) AS maintenance_cost,
        SUM(s.labor_cost) AS labor_cost,
        SUM(s.parts_cost) AS parts_cost,
        COUNT(*) AS maintenance_events,
        bi.sdiv(SUM(s.total_cost), COUNT(*)) AS avg_cost_per_event,
        SUM(s.downtime_hours) AS downtime_hours,
        MAX(s.maintenance_date) AS last_service_in_scope
        FROM bi.fn_scope_maintenance(p_start, p_end, p_truck, p_type) s
    ), f AS (
        SELECT SUM(s.miles) AS total_miles, COUNT(DISTINCT s.trailer_id) AS trailers_used FROM bi.fn_scope_load(p_start, p_end, NULL, NULL, NULL, p_truck, NULL) s
    ), dys AS (
        SELECT GREATEST(0, LEAST(COALESCE(p_end, dw.data_as_of()), dw.data_as_of())
                         - GREATEST(COALESCE(p_start, (SELECT MIN(load_date) FROM dw.fact_load_trip)), (SELECT MIN(load_date) FROM dw.fact_load_trip)) + 1) AS days_in_scope
    ), u AS (
        SELECT AVG(s.utilization_rate) AS fleet_utilization_pct FROM bi.fn_scope_truck_month(p_start, p_end, p_truck) s
    ), od AS (
        SELECT COUNT(*) FILTER (WHERE x.service_status = 'Overdue' AND x.truck_status = 'Active') AS overdue_trucks
        FROM bi.m_truck_scorecard(p_start, p_end, p_truck, p_type) x
    )
    SELECT
        (tr.active_trucks)::bigint AS active_trucks,
        (tr.fleet_age_yrs)::numeric AS fleet_age_yrs,
        (m.maintenance_cost)::numeric AS maintenance_cost,
        (m.labor_cost)::numeric AS labor_cost,
        (m.parts_cost)::numeric AS parts_cost,
        (m.maintenance_events)::bigint AS maintenance_events,
        (m.avg_cost_per_event)::numeric AS avg_cost_per_event,
        (m.downtime_hours)::numeric AS downtime_hours,
        (bi.sdiv(m.maintenance_cost, f.total_miles))::numeric AS maint_cost_per_mile_actual,
        (bi.sdiv(f.total_miles, m.maintenance_events))::numeric AS miles_between_service,
        (1 - bi.sdiv(m.downtime_hours, tr.active_trucks * dys.days_in_scope * 24))::numeric AS availability_pct,
        (od.overdue_trucks)::bigint AS overdue_trucks,
        (bi.sdiv(f.trailers_used, (SELECT COUNT(*) FROM dw.dim_trailer)))::numeric AS trailer_utilization_pct,
        (u.fleet_utilization_pct)::numeric AS fleet_utilization_pct,
        (bi.f_color_utilization(u.fleet_utilization_pct))::text AS utilization_status_color
    FROM tr CROSS JOIN m CROSS JOIN f CROSS JOIN dys CROSS JOIN u CROSS JOIN od
$$;

-- Maintenance measures grouped by any dimension (cost by month, by type, by model year).
-- p_dimension: year, quarter, month_number, year_month, maintenance_type, truck, truck_make, model_year, truck_age_band
CREATE OR REPLACE FUNCTION bi.m_maintenance_by(
    p_dimension text, p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_truck text DEFAULT NULL, p_type text DEFAULT NULL)
RETURNS TABLE (
    dim_key text,
    dim_label text,
    maintenance_cost numeric,
    labor_cost numeric,
    parts_cost numeric,
    maintenance_events bigint,
    avg_cost_per_event numeric,
    downtime_hours numeric,
    last_service_in_scope date)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_key text;
    v_label text;
BEGIN
    v_key := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'lpad(dd.month_number::text, 2, ''0'')'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'maintenance_type' THEN 's.maintenance_type'
        WHEN 'truck' THEN 's.truck_id'
        WHEN 'truck_make' THEN 'tk.make'
        WHEN 'model_year' THEN 'tk.model_year'
        WHEN 'truck_age_band' THEN 'tk.truck_age_band'
    END;
    v_label := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'dd.month_name'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'maintenance_type' THEN 's.maintenance_type'
        WHEN 'truck' THEN 's.truck_id'
        WHEN 'truck_make' THEN 'tk.make'
        WHEN 'model_year' THEN 'tk.model_year'
        WHEN 'truck_age_band' THEN 'tk.truck_age_band'
    END;
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Unknown dimension %. Allowed: year, quarter, month_number, year_month, maintenance_type, truck, truck_make, model_year, truck_age_band', p_dimension;
    END IF;
    RETURN QUERY EXECUTE format($q$
        SELECT (%1$s)::text AS dim_key, (%2$s)::text AS dim_label,
               (SUM(s.total_cost))::numeric AS maintenance_cost,
               (SUM(s.labor_cost))::numeric AS labor_cost,
               (SUM(s.parts_cost))::numeric AS parts_cost,
               (COUNT(*))::bigint AS maintenance_events,
               (bi.sdiv(SUM(s.total_cost), COUNT(*)))::numeric AS avg_cost_per_event,
               (SUM(s.downtime_hours))::numeric AS downtime_hours,
               (MAX(s.maintenance_date))::date AS last_service_in_scope
        FROM bi.fn_scope_maintenance($1, $2, $3, $4) s
        LEFT JOIN dw.dim_date dd ON dd.full_date = s.maintenance_date
        LEFT JOIN dw.dim_truck tk ON tk.truck_id = s.truck_id
        GROUP BY 1, 2
        ORDER BY 1
    $q$, v_key, v_label)
    USING p_start, p_end, p_truck, p_type;
END;
$fn$;

-- Trailer utilization by trailer type.
CREATE OR REPLACE FUNCTION bi.m_trailer_util_by_type(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    trailer_type text,
    trailers bigint,
    trailers_used bigint,
    trailer_utilization_pct numeric)
LANGUAGE sql STABLE AS $$
    WITH used AS (
        SELECT t.trailer_type, COUNT(DISTINCT s.trailer_id) AS n
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s JOIN dw.dim_trailer t ON t.trailer_id = s.trailer_id GROUP BY t.trailer_type
    ), tot AS (
        SELECT trailer_type, COUNT(*) AS n FROM dw.dim_trailer GROUP BY trailer_type
    )
    SELECT
        (tot.trailer_type)::text AS trailer_type,
        (tot.n)::bigint AS trailers,
        (COALESCE(used.n, 0))::bigint AS trailers_used,
        (bi.sdiv(COALESCE(used.n, 0), tot.n))::numeric AS trailer_utilization_pct
    FROM tot LEFT JOIN used ON used.trailer_type = tot.trailer_type
    ORDER BY tot.trailer_type
$$;

-- Dashboard 5 fuel cards and what-if panel: cost, price, MPG, idle fuel cost, savings to the target MPG, price scenario.
CREATE OR REPLACE FUNCTION bi.m_fuel_overall(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_state text DEFAULT NULL)
RETURNS TABLE (
    fuel_cost numeric,
    fuel_gallons numeric,
    avg_price_per_gallon numeric,
    fuel_cost_per_mile numeric,
    fuel_pct_of_revenue numeric,
    avg_mpg numeric,
    idle_hours numeric,
    idle_fuel_gallons numeric,
    idle_fuel_cost numeric,
    fuel_savings_to_target_mpg numeric,
    fuel_cost_scenario numeric,
    fuel_scenario_margin_impact numeric)
LANGUAGE sql STABLE AS $$
    WITH fu AS (
        SELECT
        SUM(s.total_cost) AS fuel_cost,
        SUM(s.gallons) AS fuel_gallons,
        bi.sdiv(SUM(s.total_cost), SUM(s.gallons)) AS avg_price_per_gallon
        FROM bi.fn_scope_fuel(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_state) s
    ), f AS (
        SELECT SUM(s.revenue) AS rev, SUM(s.miles) AS miles, SUM(s.fuel_gallons_used) AS gused, SUM(s.idle_hours) AS idle,
               bi.sdiv(SUM(s.miles), SUM(s.fuel_gallons_used)) AS mpg
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s
    )
    SELECT
        (fu.fuel_cost)::numeric AS fuel_cost,
        (fu.fuel_gallons)::numeric AS fuel_gallons,
        (fu.avg_price_per_gallon)::numeric AS avg_price_per_gallon,
        (bi.sdiv(fu.fuel_cost, f.miles))::numeric AS fuel_cost_per_mile,
        (bi.sdiv(fu.fuel_cost, f.rev))::numeric AS fuel_pct_of_revenue,
        (f.mpg)::numeric AS avg_mpg,
        (f.idle)::numeric AS idle_hours,
        (f.idle * bi.param('idle_burn_gal_per_hour'))::numeric AS idle_fuel_gallons,
        (f.idle * bi.param('idle_burn_gal_per_hour') * fu.avg_price_per_gallon)::numeric AS idle_fuel_cost,
        (GREATEST(0, f.gused - f.miles / bi.param('target_mpg')) * fu.avg_price_per_gallon)::numeric AS fuel_savings_to_target_mpg,
        (fu.fuel_cost * (1 + bi.param('fuel_price_change')))::numeric AS fuel_cost_scenario,
        (-(fu.fuel_cost * (1 + bi.param('fuel_price_change')) - fu.fuel_cost))::numeric AS fuel_scenario_margin_impact
    FROM fu CROSS JOIN f
$$;

-- Fuel cost, gallons and price grouped by any dimension (cost and price by month).
-- p_dimension: year, quarter, month_number, year_month, state, customer, route, driver, truck
CREATE OR REPLACE FUNCTION bi.m_fuel_by(
    p_dimension text, p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_state text DEFAULT NULL)
RETURNS TABLE (
    dim_key text,
    dim_label text,
    fuel_cost numeric,
    fuel_gallons numeric,
    avg_price_per_gallon numeric)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_key text;
    v_label text;
BEGIN
    v_key := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'lpad(dd.month_number::text, 2, ''0'')'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'state' THEN 's.location_state'
        WHEN 'customer' THEN 's.customer_id'
        WHEN 'route' THEN 's.route_id'
        WHEN 'driver' THEN 's.driver_id'
        WHEN 'truck' THEN 's.truck_id'
    END;
    v_label := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'dd.month_name'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'state' THEN 's.location_state'
        WHEN 'customer' THEN 'c.customer_name'
        WHEN 'route' THEN 'r.route_name'
        WHEN 'driver' THEN 'dr.driver_name'
        WHEN 'truck' THEN 's.truck_id'
    END;
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Unknown dimension %. Allowed: year, quarter, month_number, year_month, state, customer, route, driver, truck', p_dimension;
    END IF;
    RETURN QUERY EXECUTE format($q$
        SELECT (%1$s)::text AS dim_key, (%2$s)::text AS dim_label,
               (SUM(s.total_cost))::numeric AS fuel_cost,
               (SUM(s.gallons))::numeric AS fuel_gallons,
               (bi.sdiv(SUM(s.total_cost), SUM(s.gallons)))::numeric AS avg_price_per_gallon
        FROM bi.fn_scope_fuel($1, $2, $3, $4, $5, $6, $7, $8) s
        LEFT JOIN dw.dim_date dd ON dd.full_date = s.load_date
        LEFT JOIN dw.dim_customer c ON c.customer_id = s.customer_id
        LEFT JOIN dw.dim_route r ON r.route_id = s.route_id
        LEFT JOIN dw.dim_driver dr ON dr.driver_id = s.driver_id
        GROUP BY 1, 2
        ORDER BY 1
    $q$, v_key, v_label)
    USING p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_state;
END;
$fn$;

-- Fuel spend and price by state, with the price gap to the fleet average and its colour. States with no value are excluded.
CREATE OR REPLACE FUNCTION bi.m_fuel_by_state(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_state text DEFAULT NULL)
RETURNS TABLE (
    location_state text,
    fuel_cost numeric,
    fuel_gallons numeric,
    avg_price_per_gallon numeric,
    state_price_vs_fleet_avg numeric,
    price_variance_color text,
    top_15_by_gallons_flag integer)
LANGUAGE sql STABLE AS $$
    WITH s AS (
        SELECT x.location_state, SUM(x.total_cost) AS fuel_cost, SUM(x.gallons) AS fuel_gallons
        FROM bi.fn_scope_fuel(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_state) x WHERE x.location_state IS NOT NULL GROUP BY x.location_state
    )
    SELECT
        (s.location_state)::text AS location_state,
        (s.fuel_cost)::numeric AS fuel_cost,
        (s.fuel_gallons)::numeric AS fuel_gallons,
        (bi.sdiv(s.fuel_cost, s.fuel_gallons))::numeric AS avg_price_per_gallon,
        (bi.sdiv(s.fuel_cost, s.fuel_gallons) - bi.sdiv(SUM(s.fuel_cost) OVER (), SUM(s.fuel_gallons) OVER ()))::numeric AS state_price_vs_fleet_avg,
        (bi.f_color_price_variance(bi.sdiv(s.fuel_cost, s.fuel_gallons) - bi.sdiv(SUM(s.fuel_cost) OVER (), SUM(s.fuel_gallons) OVER ())))::text AS price_variance_color,
        ((DENSE_RANK() OVER (ORDER BY s.fuel_gallons DESC) <= 15)::integer)::integer AS top_15_by_gallons_flag
    FROM s
    ORDER BY s.fuel_cost DESC
$$;

-- Dashboard 5 safety cards. safety_incident is the rate per 100,000 miles (the legacy Safety incident measure); incidents_per_1m_miles is the rate used elsewhere.
CREATE OR REPLACE FUNCTION bi.m_safety_overall(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_incident_type text DEFAULT NULL)
RETURNS TABLE (
    safety_incidents bigint,
    at_fault_incidents bigint,
    at_fault_pct numeric,
    preventable_incidents bigint,
    preventable_pct numeric,
    injury_incidents bigint,
    total_claims numeric,
    damage_cost numeric,
    cost_per_incident numeric,
    last_incident_date date,
    incidents_per_1m_miles numeric,
    safety_incident numeric,
    days_since_last_incident integer)
LANGUAGE sql STABLE AS $$
    WITH sf AS (
        SELECT
        COUNT(*) AS safety_incidents,
        COUNT(*) FILTER (WHERE s.at_fault_flag IS TRUE) AS at_fault_incidents,
        bi.sdiv(COUNT(*) FILTER (WHERE s.at_fault_flag IS TRUE), COUNT(*)) AS at_fault_pct,
        COUNT(*) FILTER (WHERE s.preventable_flag IS TRUE) AS preventable_incidents,
        bi.sdiv(COUNT(*) FILTER (WHERE s.preventable_flag IS TRUE), COUNT(*)) AS preventable_pct,
        COUNT(*) FILTER (WHERE s.injury_flag IS TRUE) AS injury_incidents,
        SUM(s.claim_amount) AS total_claims,
        SUM(COALESCE(s.vehicle_damage_cost, 0)) + SUM(COALESCE(s.cargo_damage_cost, 0)) AS damage_cost,
        bi.sdiv(SUM(COALESCE(s.claim_amount, 0)) + SUM(COALESCE(s.vehicle_damage_cost, 0)) + SUM(COALESCE(s.cargo_damage_cost, 0)), COUNT(*)) AS cost_per_incident,
        MAX(s.incident_date) AS last_incident_date
        FROM bi.fn_scope_safety(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type) s
    ), f AS (
        SELECT SUM(s.miles) AS miles FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s
    ), li AS (
        SELECT MAX(x.incident_date) AS d FROM dw.fact_safety_incident x WHERE (p_incident_type IS NULL OR x.incident_type = p_incident_type)
    )
    SELECT
        (sf.safety_incidents)::bigint AS safety_incidents,
        (sf.at_fault_incidents)::bigint AS at_fault_incidents,
        (sf.at_fault_pct)::numeric AS at_fault_pct,
        (sf.preventable_incidents)::bigint AS preventable_incidents,
        (sf.preventable_pct)::numeric AS preventable_pct,
        (sf.injury_incidents)::bigint AS injury_incidents,
        (sf.total_claims)::numeric AS total_claims,
        (sf.damage_cost)::numeric AS damage_cost,
        (sf.cost_per_incident)::numeric AS cost_per_incident,
        (sf.last_incident_date)::date AS last_incident_date,
        (bi.sdiv(sf.safety_incidents, f.miles) * 1000000)::numeric AS incidents_per_1m_miles,
        (bi.sdiv(sf.safety_incidents, f.miles) * 100000)::numeric AS safety_incident,
        ((dw.data_as_of() - li.d)::integer)::integer AS days_since_last_incident
    FROM sf CROSS JOIN f CROSS JOIN li
$$;

-- Safety measures grouped by any dimension (incidents by type and month).
-- p_dimension: year, quarter, month_number, year_month, incident_type, customer, route, driver, truck
CREATE OR REPLACE FUNCTION bi.m_safety_by(
    p_dimension text, p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_incident_type text DEFAULT NULL)
RETURNS TABLE (
    dim_key text,
    dim_label text,
    safety_incidents bigint,
    at_fault_incidents bigint,
    at_fault_pct numeric,
    preventable_incidents bigint,
    preventable_pct numeric,
    injury_incidents bigint,
    total_claims numeric,
    damage_cost numeric,
    cost_per_incident numeric,
    last_incident_date date)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_key text;
    v_label text;
BEGIN
    v_key := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'lpad(dd.month_number::text, 2, ''0'')'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'incident_type' THEN 's.incident_type'
        WHEN 'customer' THEN 's.customer_id'
        WHEN 'route' THEN 's.route_id'
        WHEN 'driver' THEN 's.driver_id'
        WHEN 'truck' THEN 's.truck_id'
    END;
    v_label := CASE p_dimension
        WHEN 'year' THEN 'dd.year'
        WHEN 'quarter' THEN 'dd.quarter'
        WHEN 'month_number' THEN 'dd.month_name'
        WHEN 'year_month' THEN 'dd.year_month'
        WHEN 'incident_type' THEN 's.incident_type'
        WHEN 'customer' THEN 'c.customer_name'
        WHEN 'route' THEN 'r.route_name'
        WHEN 'driver' THEN 'dr.driver_name'
        WHEN 'truck' THEN 's.truck_id'
    END;
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Unknown dimension %. Allowed: year, quarter, month_number, year_month, incident_type, customer, route, driver, truck', p_dimension;
    END IF;
    RETURN QUERY EXECUTE format($q$
        SELECT (%1$s)::text AS dim_key, (%2$s)::text AS dim_label,
               (COUNT(*))::bigint AS safety_incidents,
               (COUNT(*) FILTER (WHERE s.at_fault_flag IS TRUE))::bigint AS at_fault_incidents,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.at_fault_flag IS TRUE), COUNT(*)))::numeric AS at_fault_pct,
               (COUNT(*) FILTER (WHERE s.preventable_flag IS TRUE))::bigint AS preventable_incidents,
               (bi.sdiv(COUNT(*) FILTER (WHERE s.preventable_flag IS TRUE), COUNT(*)))::numeric AS preventable_pct,
               (COUNT(*) FILTER (WHERE s.injury_flag IS TRUE))::bigint AS injury_incidents,
               (SUM(s.claim_amount))::numeric AS total_claims,
               (SUM(COALESCE(s.vehicle_damage_cost, 0)) + SUM(COALESCE(s.cargo_damage_cost, 0)))::numeric AS damage_cost,
               (bi.sdiv(SUM(COALESCE(s.claim_amount, 0)) + SUM(COALESCE(s.vehicle_damage_cost, 0)) + SUM(COALESCE(s.cargo_damage_cost, 0)), COUNT(*)))::numeric AS cost_per_incident,
               (MAX(s.incident_date))::date AS last_incident_date
        FROM bi.fn_scope_safety($1, $2, $3, $4, $5, $6, $7, $8) s
        LEFT JOIN dw.dim_date dd ON dd.full_date = s.load_date
        LEFT JOIN dw.dim_customer c ON c.customer_id = s.customer_id
        LEFT JOIN dw.dim_route r ON r.route_id = s.route_id
        LEFT JOIN dw.dim_driver dr ON dr.driver_id = s.driver_id
        GROUP BY 1, 2
        ORDER BY 1
    $q$, v_key, v_label)
    USING p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type;
END;
$fn$;

-- Incidents per driver (DRV_UNKNOWN excluded) with the Top N Incident Driver Flag.
CREATE OR REPLACE FUNCTION bi.m_safety_by_driver(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_incident_type text DEFAULT NULL)
RETURNS TABLE (
    driver_id text,
    driver_name text,
    safety_incidents bigint,
    total_claims numeric,
    total_miles numeric,
    incidents_per_1m_miles numeric,
    top_n_incident_driver_flag integer)
LANGUAGE sql STABLE AS $$
    WITH s AS (
        SELECT x.driver_id, COUNT(*) AS n, SUM(x.claim_amount) AS claims
        FROM bi.fn_scope_safety(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type) x
        WHERE x.driver_id IS NOT NULL AND x.driver_id <> 'DRV_UNKNOWN' GROUP BY x.driver_id
    ), f AS (
        SELECT l.driver_id, SUM(l.miles) AS miles FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) l GROUP BY l.driver_id
    )
    SELECT
        (s.driver_id)::text AS driver_id,
        (dr.driver_name)::text AS driver_name,
        (s.n)::bigint AS safety_incidents,
        (s.claims)::numeric AS total_claims,
        (f.miles)::numeric AS total_miles,
        (bi.sdiv(s.n, f.miles) * 1000000)::numeric AS incidents_per_1m_miles,
        ((s.n > 0 AND DENSE_RANK() OVER (ORDER BY s.n DESC) <= bi.param('top_n'))::integer)::integer AS top_n_incident_driver_flag
    FROM s LEFT JOIN f ON f.driver_id = s.driver_id LEFT JOIN dw.dim_driver dr ON dr.driver_id = s.driver_id
    ORDER BY s.n DESC
$$;

-- The most recent incidents (default 20).
CREATE OR REPLACE FUNCTION bi.m_latest_incidents(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_incident_type text DEFAULT NULL, p_limit integer DEFAULT 20)
RETURNS TABLE (
    incident_date date,
    incident_type text,
    driver_name text,
    truck_id text,
    claim_amount numeric)
LANGUAGE sql STABLE AS $$
    SELECT
        (x.incident_date)::date AS incident_date,
        (x.incident_type)::text AS incident_type,
        (COALESCE(dr.driver_name, x.driver_id))::text AS driver_name,
        (x.truck_id)::text AS truck_id,
        (x.claim_amount)::numeric AS claim_amount
    FROM bi.fn_scope_safety(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type) x LEFT JOIN dw.dim_driver dr ON dr.driver_id = x.driver_id
    ORDER BY x.incident_date DESC
    LIMIT p_limit
$$;

-- One row per customer: revenue, margin, on-time, rank, Pareto class, churn status and wallet share.
CREATE OR REPLACE FUNCTION bi.m_customer_scorecard(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    customer_id text,
    customer_name text,
    customer_type text,
    primary_freight_type text,
    credit_terms_days integer,
    annual_revenue_potential numeric,
    contract_start_date date,
    customer_revenue numeric,
    load_count bigint,
    total_miles numeric,
    customer_margin numeric,
    customer_margin_pct numeric,
    cancellation_rate numeric,
    total_deliveries bigint,
    on_time_deliveries bigint,
    late_deliveries bigint,
    customer_on_time_pct numeric,
    detained_stops_pct numeric,
    customer_service_score numeric,
    customer_rank bigint,
    top_n_customer_flag integer,
    cumulative_revenue_pct numeric,
    abc_class text,
    abc_color text,
    first_load_date date,
    last_load_date date,
    is_new boolean,
    is_retained boolean,
    is_repeat_customer boolean,
    days_since_last_load integer,
    churn_status text,
    churn_status_color text,
    wallet_share_customer numeric)
LANGUAGE sql STABLE AS $$
    WITH w AS (
        SELECT COALESCE(p_start, (SELECT MIN(full_date) FROM dw.dim_date)) AS w0,
               COALESCE(p_end, (SELECT MAX(full_date) FROM dw.dim_date)) AS w1
    ), f AS (
        SELECT s.customer_id, SUM(s.revenue) AS customer_revenue, COUNT(*) AS load_count, SUM(s.miles) AS total_miles,
               SUM(s.gross_profit) AS gross_profit, bi.sdiv(SUM(s.gross_profit), SUM(s.revenue)) AS gross_margin,
               bi.sdiv(COUNT(*) FILTER (WHERE s.load_status = 'Cancelled'), COUNT(*)) AS cancellation_rate
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s GROUP BY s.customer_id
    ), d AS (
        SELECT x.customer_id, COUNT(*) FILTER (WHERE x.is_delivery) AS total_deliveries,
               COUNT(*) FILTER (WHERE x.is_delivery AND x.on_time_flag IS TRUE) AS on_time_deliveries,
               bi.sdiv(COUNT(*) FILTER (WHERE x.detention_minutes > 0), COUNT(*)) AS detained_stops_pct
        FROM bi.fn_scope_delivery(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL) x GROUP BY x.customer_id
    ), ll AS (
        SELECT customer_id, MIN(load_date) AS first_load_date, MAX(load_date) AS last_load_date
        FROM dw.fact_load_trip GROUP BY customer_id
    ), pr AS (
        SELECT DISTINCT s.customer_id FROM bi.fn_scope_load((COALESCE(p_start, (SELECT MIN(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, (COALESCE(p_end, (SELECT MAX(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, p_customer, p_route, p_driver, p_truck, p_booking) s
    ), b AS (
        SELECT f.customer_id, c.customer_name, c.customer_type, c.primary_freight_type, c.credit_terms_days,
               c.annual_revenue_potential, c.contract_start_date, f.customer_revenue, f.load_count, f.total_miles,
               f.gross_profit, f.gross_margin, f.cancellation_rate, d.total_deliveries, d.on_time_deliveries,
               bi.sdiv(d.on_time_deliveries, d.total_deliveries) AS customer_on_time_pct, d.detained_stops_pct,
               ll.first_load_date, ll.last_load_date,
               (pr.customer_id IS NOT NULL) AS is_retained,
               (ll.first_load_date BETWEEN w.w0 AND w.w1) AS is_new,
               (dw.data_as_of() - ll.last_load_date)::integer AS days_since_last_load,
               DENSE_RANK() OVER (ORDER BY f.customer_revenue DESC) AS customer_rank,
               bi.sdiv(SUM(f.customer_revenue) OVER (ORDER BY f.customer_revenue DESC RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
                       SUM(f.customer_revenue) OVER ()) AS cumulative_revenue_pct
        FROM f
        LEFT JOIN dw.dim_customer c ON c.customer_id = f.customer_id
        LEFT JOIN d ON d.customer_id = f.customer_id
        LEFT JOIN ll ON ll.customer_id = f.customer_id
        LEFT JOIN pr ON pr.customer_id = f.customer_id
        CROSS JOIN w
    )
    SELECT
        (b.customer_id)::text AS customer_id,
        (b.customer_name)::text AS customer_name,
        (b.customer_type)::text AS customer_type,
        (b.primary_freight_type)::text AS primary_freight_type,
        (b.credit_terms_days)::integer AS credit_terms_days,
        (b.annual_revenue_potential)::numeric AS annual_revenue_potential,
        (b.contract_start_date)::date AS contract_start_date,
        (b.customer_revenue)::numeric AS customer_revenue,
        (b.load_count)::bigint AS load_count,
        (b.total_miles)::numeric AS total_miles,
        (b.gross_profit)::numeric AS customer_margin,
        (b.gross_margin)::numeric AS customer_margin_pct,
        (b.cancellation_rate)::numeric AS cancellation_rate,
        (b.total_deliveries)::bigint AS total_deliveries,
        (b.on_time_deliveries)::bigint AS on_time_deliveries,
        (b.total_deliveries - b.on_time_deliveries)::bigint AS late_deliveries,
        (b.customer_on_time_pct)::numeric AS customer_on_time_pct,
        (b.detained_stops_pct)::numeric AS detained_stops_pct,
        (bi.f_service_score(b.customer_on_time_pct, b.cancellation_rate, b.detained_stops_pct))::numeric AS customer_service_score,
        (b.customer_rank)::bigint AS customer_rank,
        ((b.customer_rank <= bi.param('top_n'))::integer)::integer AS top_n_customer_flag,
        (b.cumulative_revenue_pct)::numeric AS cumulative_revenue_pct,
        (bi.f_abc_class(b.cumulative_revenue_pct))::text AS abc_class,
        (bi.f_color_abc(bi.f_abc_class(b.cumulative_revenue_pct)))::text AS abc_color,
        (b.first_load_date)::date AS first_load_date,
        (b.last_load_date)::date AS last_load_date,
        (b.is_new)::boolean AS is_new,
        (b.is_retained)::boolean AS is_retained,
        (b.load_count >= 2)::boolean AS is_repeat_customer,
        (b.days_since_last_load)::integer AS days_since_last_load,
        (bi.f_churn_status(b.days_since_last_load))::text AS churn_status,
        (bi.f_color_churn(bi.f_churn_status(b.days_since_last_load)))::text AS churn_status_color,
        (bi.sdiv(b.customer_revenue, b.annual_revenue_potential))::numeric AS wallet_share_customer
    FROM b
    ORDER BY b.customer_rank
$$;

-- Dashboard 6 cards. New Customers and Retention need a year; Wallet Share is only meaningful for one year.
CREATE OR REPLACE FUNCTION bi.m_customer_overall(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    active_customers bigint,
    avg_revenue_per_customer numeric,
    top_n_customer_share numeric,
    new_customers bigint,
    retained_customers bigint,
    retention_pct numeric,
    repeat_customers bigint,
    repeat_rate numeric,
    at_risk_customers bigint,
    customer_margin_pct numeric,
    wallet_share numeric)
LANGUAGE sql STABLE AS $$
    SELECT
        (COUNT(*))::bigint AS active_customers,
        (bi.sdiv(SUM(x.customer_revenue), COUNT(*)))::numeric AS avg_revenue_per_customer,
        (bi.sdiv(SUM(x.customer_revenue) FILTER (WHERE x.customer_rank <= bi.param('top_n')), SUM(x.customer_revenue)))::numeric AS top_n_customer_share,
        (COUNT(*) FILTER (WHERE x.is_new))::bigint AS new_customers,
        (COUNT(*) FILTER (WHERE x.is_retained))::bigint AS retained_customers,
        (bi.sdiv(COUNT(*) FILTER (WHERE x.is_retained), (SELECT COUNT(DISTINCT s.customer_id) FROM bi.fn_scope_load((COALESCE(p_start, (SELECT MIN(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, (COALESCE(p_end, (SELECT MAX(full_date) FROM dw.dim_date)) - INTERVAL '1 year')::date, p_customer, p_route, p_driver, p_truck, p_booking) s)))::numeric AS retention_pct,
        (COUNT(*) FILTER (WHERE x.is_repeat_customer))::bigint AS repeat_customers,
        (bi.sdiv(COUNT(*) FILTER (WHERE x.is_repeat_customer), COUNT(*)))::numeric AS repeat_rate,
        (COUNT(*) FILTER (WHERE x.days_since_last_load > bi.param('churn_days')))::bigint AS at_risk_customers,
        (bi.sdiv(SUM(x.customer_margin), SUM(x.customer_revenue)))::numeric AS customer_margin_pct,
        (bi.sdiv(SUM(x.customer_revenue), SUM(x.annual_revenue_potential)))::numeric AS wallet_share
    FROM bi.m_customer_scorecard(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) x
$$;

-- One row per route: profit, margin, cost and revenue per mile, distance and rate realization, tier, rank and Top/Bottom N flags.
CREATE OR REPLACE FUNCTION bi.m_route_scorecard(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    route_id text,
    route_name text,
    origin_city text,
    destination_city text,
    route_revenue numeric,
    load_count bigint,
    total_miles numeric,
    gross_profit numeric,
    gross_margin numeric,
    revenue_per_mile numeric,
    route_cost_per_mile numeric,
    profit_per_mile numeric,
    expected_miles numeric,
    distance_variance_pct numeric,
    expected_linehaul_revenue numeric,
    rate_realization_pct numeric,
    margin_vs_fleet numeric,
    route_profit_tier text,
    route_tier_color text,
    route_rank bigint,
    top_n_route_flag integer,
    bottom_n_route_flag integer)
LANGUAGE sql STABLE AS $$
    WITH f AS (
        SELECT s.route_id, r.route_name, s.origin_city, s.destination_city, SUM(s.revenue) AS total_revenue, COUNT(*) AS load_count,
               SUM(s.miles) AS total_miles, SUM(s.gross_profit) AS gross_profit, SUM(s.expected_miles) AS expected_miles,
               SUM(s.expected_linehaul_revenue) AS expected_linehaul_revenue
        FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s LEFT JOIN dw.dim_route r ON r.route_id = s.route_id
        GROUP BY s.route_id, r.route_name, s.origin_city, s.destination_city
    ), fleet AS (
        SELECT bi.sdiv(SUM(s.gross_profit), SUM(s.revenue)) AS fleet_margin
        FROM bi.fn_scope_load(p_start, p_end, p_customer, NULL, p_driver, p_truck, p_booking) s
    )
    SELECT
        (f.route_id)::text AS route_id,
        (f.route_name)::text AS route_name,
        (f.origin_city)::text AS origin_city,
        (f.destination_city)::text AS destination_city,
        (f.total_revenue)::numeric AS route_revenue,
        (f.load_count)::bigint AS load_count,
        (f.total_miles)::numeric AS total_miles,
        (f.gross_profit)::numeric AS gross_profit,
        (bi.sdiv(f.gross_profit, f.total_revenue))::numeric AS gross_margin,
        (bi.sdiv(f.total_revenue, f.total_miles))::numeric AS revenue_per_mile,
        (bi.sdiv(f.total_revenue - f.gross_profit, f.total_miles))::numeric AS route_cost_per_mile,
        (bi.sdiv(f.gross_profit, f.total_miles))::numeric AS profit_per_mile,
        (f.expected_miles)::numeric AS expected_miles,
        (bi.sdiv(f.total_miles - f.expected_miles, f.expected_miles))::numeric AS distance_variance_pct,
        (f.expected_linehaul_revenue)::numeric AS expected_linehaul_revenue,
        (bi.sdiv(f.total_revenue, f.expected_linehaul_revenue))::numeric AS rate_realization_pct,
        (bi.sdiv(f.gross_profit, f.total_revenue) - fleet.fleet_margin)::numeric AS margin_vs_fleet,
        (bi.f_route_tier(bi.sdiv(f.gross_profit, f.total_revenue) - fleet.fleet_margin))::text AS route_profit_tier,
        (bi.f_color_route_tier(bi.f_route_tier(bi.sdiv(f.gross_profit, f.total_revenue) - fleet.fleet_margin)))::text AS route_tier_color,
        (DENSE_RANK() OVER (ORDER BY f.gross_profit DESC))::bigint AS route_rank,
        ((DENSE_RANK() OVER (ORDER BY f.gross_profit DESC) <= bi.param('top_n'))::integer)::integer AS top_n_route_flag,
        ((DENSE_RANK() OVER (ORDER BY f.gross_profit ASC) <= bi.param('top_n'))::integer)::integer AS bottom_n_route_flag
    FROM f CROSS JOIN fleet
    ORDER BY f.gross_profit DESC
$$;

-- Gross margin by origin and destination (the lane matrix).
CREATE OR REPLACE FUNCTION bi.m_lane_matrix(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    origin_city text,
    destination_city text,
    total_revenue numeric,
    gross_profit numeric,
    gross_margin numeric,
    load_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT
        (s.origin_city)::text AS origin_city,
        (s.destination_city)::text AS destination_city,
        (SUM(s.revenue))::numeric AS total_revenue,
        (SUM(s.gross_profit))::numeric AS gross_profit,
        (bi.sdiv(SUM(s.gross_profit), SUM(s.revenue)))::numeric AS gross_margin,
        (COUNT(*))::bigint AS load_count
    FROM bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s
    GROUP BY s.origin_city, s.destination_city
    ORDER BY 1, 2
$$;

-- Loads out and in per city, and the balance between them (Network City).
CREATE OR REPLACE FUNCTION bi.m_city_network(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    city text,
    outbound_loads bigint,
    inbound_loads bigint,
    lane_balance bigint,
    lane_balance_pct numeric)
LANGUAGE sql STABLE AS $$
    WITH n AS (
        SELECT c.city, COUNT(*) FILTER (WHERE s.origin_city = c.city) AS o, COUNT(*) FILTER (WHERE s.destination_city = c.city) AS i
        FROM dw.dim_network_city c
        JOIN bi.fn_scope_load(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking) s ON s.origin_city = c.city OR s.destination_city = c.city
        GROUP BY c.city
    )
    SELECT
        (n.city)::text AS city,
        (n.o)::bigint AS outbound_loads,
        (n.i)::bigint AS inbound_loads,
        (n.o - n.i)::bigint AS lane_balance,
        (bi.sdiv(n.o - n.i, n.o + n.i))::numeric AS lane_balance_pct
    FROM n
    ORDER BY n.city
$$;

-- The margin waterfall: revenue, fuel, maintenance and the Gross Profit total.
CREATE OR REPLACE FUNCTION bi.m_margin_bridge(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    item text,
    sort_order integer,
    margin_bridge_value numeric)
LANGUAGE sql STABLE AS $$
    WITH o AS (SELECT * FROM bi.m_finance(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking))
    SELECT
        (b.item)::text AS item,
        (b.sort_order)::integer AS sort_order,
        (CASE b.item WHEN 'Revenue' THEN o.total_revenue WHEN 'Fuel' THEN -o.fuel_cost WHEN 'Maintenance' THEN -o.maintenance_cost_allocated WHEN 'Gross Profit' THEN o.gross_profit END)::numeric AS margin_bridge_value
    FROM dw.dim_margin_bridge b CROSS JOIN o
    ORDER BY b.sort_order
$$;

-- What-if: revenue moved by the Rate Change parameter and fuel by the Fuel Price Change parameter.
CREATE OR REPLACE FUNCTION bi.m_scenario(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    total_revenue numeric,
    gross_profit numeric,
    revenue_scenario numeric,
    cost_scenario numeric,
    profit_scenario numeric,
    profit_scenario_delta numeric,
    margin_scenario_pct numeric)
LANGUAGE sql STABLE AS $$
    WITH o AS (
        SELECT * FROM bi.m_finance(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking)
    ), x AS (
        SELECT o.total_revenue, o.gross_profit,
               o.total_revenue * (1 + bi.param('rate_change')) AS rs,
               o.total_cost + o.fuel_cost * bi.param('fuel_price_change') AS cs
        FROM o
    )
    SELECT
        (x.total_revenue)::numeric AS total_revenue,
        (x.gross_profit)::numeric AS gross_profit,
        (x.rs)::numeric AS revenue_scenario,
        (x.cs)::numeric AS cost_scenario,
        (x.rs - x.cs)::numeric AS profit_scenario,
        (x.rs - x.cs - x.gross_profit)::numeric AS profit_scenario_delta,
        (bi.sdiv(x.rs - x.cs, x.rs))::numeric AS margin_scenario_pct
    FROM x
$$;

-- Dashboard 1 cards and the dynamic Headline text. Pass dates for a meaningful YoY.
CREATE OR REPLACE FUNCTION bi.m_kpi_exec(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS TABLE (
    total_revenue numeric,
    revenue_py numeric,
    revenue_yoy_pct numeric,
    gross_profit numeric,
    gross_profit_yoy_pct numeric,
    gross_margin numeric,
    revenue_per_mile numeric,
    load_count bigint,
    on_time_pct numeric,
    on_time_vs_target numeric,
    on_time_status_color text,
    average_detention numeric,
    fleet_utilization_pct numeric,
    utilization_status_color text,
    safety_incidents bigint,
    safety_incident numeric,
    incidents_per_1m_miles numeric,
    headline text)
LANGUAGE sql STABLE AS $$
    WITH f AS (
        SELECT * FROM bi.m_finance(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking)
    ), t AS (
        SELECT * FROM bi.m_time_overall(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking)
    ), sv AS (
        SELECT * FROM bi.m_service(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL)
    ), u AS (
        SELECT AVG(s.utilization_rate) AS fleet_utilization_pct FROM bi.fn_scope_truck_month(p_start, p_end, p_truck) s
    ), sf AS (
        SELECT * FROM bi.m_safety_overall(p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, NULL)
    )
    SELECT
        (f.total_revenue)::numeric AS total_revenue,
        (t.revenue_py)::numeric AS revenue_py,
        (t.revenue_yoy_pct)::numeric AS revenue_yoy_pct,
        (f.gross_profit)::numeric AS gross_profit,
        (t.gross_profit_yoy_pct)::numeric AS gross_profit_yoy_pct,
        (f.gross_margin)::numeric AS gross_margin,
        (f.revenue_per_mile)::numeric AS revenue_per_mile,
        (f.load_count)::bigint AS load_count,
        (sv.on_time_pct)::numeric AS on_time_pct,
        (sv.on_time_vs_target)::numeric AS on_time_vs_target,
        (sv.on_time_status_color)::text AS on_time_status_color,
        (sv.average_detention)::numeric AS average_detention,
        (u.fleet_utilization_pct)::numeric AS fleet_utilization_pct,
        (bi.f_color_utilization(u.fleet_utilization_pct))::text AS utilization_status_color,
        (sf.safety_incidents)::bigint AS safety_incidents,
        (sf.safety_incident)::numeric AS safety_incident,
        (sf.incidents_per_1m_miles)::numeric AS incidents_per_1m_miles,
        ('Revenue $' || COALESCE(TO_CHAR(f.total_revenue / 1000000.0, 'FM999990.0'), 'n/a') || 'M (' || COALESCE(CASE WHEN t.revenue_yoy_pct >= 0 THEN '+' ELSE '' END || TO_CHAR(t.revenue_yoy_pct * 100, 'FM990.0') || '%', 'n/a') || ' YoY)  |  Margin ' || COALESCE(TO_CHAR(f.gross_margin * 100, 'FM990.0') || '%', 'n/a') || '  |  On-time ' || COALESCE(TO_CHAR(sv.on_time_pct * 100, 'FM990.0') || '%', 'n/a'))::text AS headline
    FROM f CROSS JOIN t CROSS JOIN sv CROSS JOIN u CROSS JOIN sf
$$;

