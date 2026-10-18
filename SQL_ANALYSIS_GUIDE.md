# SQL analysis guide

A practical guide to building the warehouse, calling the measure functions, reading the analysis queries, validating the numbers and extending the code. Companion documents: `SCHEMA_AND_RELATIONSHIPS.md` (tables, keys, ERD, data dictionary) and `MEASURE_CATALOGUE.md` (every DAX measure and its SQL column).

## Contents

1. Prerequisites and status
2. Quick start
3. How filters work
4. Using the measures by dashboard page
5. Connecting Power BI or Excel
6. Analysis walkthrough
7. Testing and validation
8. Performance
9. Extending the code
10. Other SQL dialects
11. Troubleshooting
12. Limitations

## 1. Prerequisites and status

- PostgreSQL 13 or later (procedures, `FILTER`, `RANGE` windows with intervals, `generate_series` on numerics). Use `psql` to run `run_all.sql`.
- The 14 source tables as CSV files or in another database (file `02`).
- Permission to create schemas `src`, `dw`, `bi`.

**Status.** The SQL was written to reproduce a finished Power BI report. It was **not run against a live database** while it was written. It has been linted: parentheses are balanced, every table, view and function is defined before it is used, and every column in the measure blocks exists in its fact table. Expect to fix a few column-name mismatches on the first run (assumed columns are marked in the docs), then confirm with `bi.v_checks` (section 7).

## 2. Quick start

1. **Create the landing tables:** `sql/01_schemas_and_source_tables.sql`. Edit the column order to match each CSV header first.
2. **Load or extract the data** with `sql/02_load_or_extract_source_data.sql`: option A loads CSV files with `COPY`; option B pulls from another PostgreSQL database with `postgres_fdw`; option C gives extraction `SELECT`s for any source system. Then run the profiling queries in section D of that file and confirm `load_status`, `event_type`, `trucks.status` and the flag types.
3. **Build the star:** run `03_star_schema_ddl.sql` and `04_etl_load_star.sql`, then `CALL dw.load_star();`. The procedure truncates and rebuilds every `dw` table, so rerun it after every reload of `src`.
4. **Create parameters, helpers, scope and measure functions and views:** files `05` to `09`.
5. **Verify:** `SELECT * FROM bi.v_dq;` then `SELECT * FROM bi.v_checks;`. Every check should return `pass = true` on the reference data.
6. **Explore:** run the queries in `sql/10_analysis_queries.sql`.

The one-command version is `psql -d YOUR_DB -f run_all.sql` (edit it first to include your load step).

## 3. How filters work

The report's slicers become **function arguments**. NULL means All, and a function with no arguments returns the unfiltered answer.

| Power BI slicer | Argument | Example |
|---|---|---|
| Year, Quarter, Month | `p_start`, `p_end` (inclusive load-date range) | `p_start := '2024-01-01', p_end := '2024-03-31'` |
| Customer | `p_customer` (customer id) | `p_customer := 'CUST00002'` |
| Route | `p_route` (route id) | `p_route := 'R0001'` |
| Driver | `p_driver` (driver id) | `p_driver := 'DRV00001'` |
| Truck | `p_truck` (truck id) | `p_truck := 'TRK0001'` |
| Booking type | `p_booking` | `p_booking := 'Contract'` |
| Facility | `p_facility` (service functions) | `p_facility := 'FAC001'` |
| Incident type | `p_incident_type` (safety functions) | `p_incident_type := 'Collision'` |
| Fuel state | `p_state` (fuel functions) | `p_state := 'TX'` |
| Maintenance type | `p_type` (fleet functions) | `p_type := 'Inspection'` |

Ids in the examples (routes, trucks, facilities, incident types) are illustrative: look up real ids in the dimension tables. `CUST` and `DRV` ids follow the reference data.

Rules that mirror the report:

- Dates are **load dates**. Fuel, delivery and safety rows follow the load date of their trip; maintenance and the two monthly facts use their own date.
- Customer and route filters never reach maintenance, which links to trucks only. This is why Gross Profit allocates maintenance by miles.
- Driver and truck filters reach load revenue (loads and trips are one fact).

**What-if parameters** are stored in `bi.parameter_selection`. Change one with a plain update; every measure that uses it follows:

```sql
UPDATE bi.parameter_selection SET selected_value = 18 WHERE parameter_name = 'top_n';
SELECT top_n_customer_share FROM bi.m_customer_overall();
UPDATE bi.parameter_selection SET selected_value = NULL WHERE parameter_name = 'top_n';  -- back to the default
```

| Parameter | Range | Default | Used for |
|---|---|---|---|
| `on_time_target` | 0.8 to 1.0 (step 0.01) | 0.95 | on-time colour |
| `utilization_target` | 0.5 to 1.0 (step 0.01) | 0.8 | utilization colour |
| `driver_pay_per_mile` | 0.3 to 1.0 (step 0.05) | 0.6 | driver_cost, full-cost view |
| `detention_rate_per_hour` | 25 to 150 (step 5) | 75 | detention cost |
| `idle_burn_gal_per_hour` | 0.4 to 1.2 (step 0.1) | 0.8 | idle fuel |
| `target_mpg` | 5 to 9 (step 0.1) | 6.5 | driver score, fuel savings |
| `fuel_price_change` | -0.2 to 0.3 (step 0.01) | 0 | fuel and profit scenarios |
| `rate_change` | -0.1 to 0.2 (step 0.01) | 0 | profit scenario |
| `top_n` | 3 to 25 (step 1) | 10 | Top N flags and share |
| `service_interval_days` | 30 to 180 (step 15) | 90 | service status |
| `churn_days` | 30 to 180 (step 15) | 90 | churn status |

## 4. Using the measures by dashboard page

Each page's data comes from a reporting view (`bi.v_*`, file 08) that calls a measure function with its defaults. Call the function directly to filter.

| Page | Cards | Main charts |
|---|---|---|
| 1 Executive | `bi.m_kpi_exec()` | `m_revenue_trend`, `m_customer_scorecard`, `m_route_scorecard`, `m_truck_scorecard`, `m_delivery_by('facility')` |
| 2 Operations | `bi.m_service()` | `m_loads_daily`, `m_finance_by('booking_type')`, `m_delivery_by('year_month' / 'day_name' / 'facility' / 'detention_bucket' / 'customer')` |
| 3 Drivers | `bi.m_driver_overall()` | `m_driver_scorecard`, `m_driver_by_tenure`, `m_idle_band`, `m_finance_by('year_month')` |
| 4 Fleet | `bi.m_fleet_overall()` | `m_truck_scorecard`, `m_maintenance_by('year_month' / 'maintenance_type' / 'model_year')`, `m_trailer_util_by_type` |
| 5 Fuel & Safety | `bi.m_fuel_overall()`, `bi.m_safety_overall()` | `m_fuel_by('year_month')`, `m_fuel_by_state`, `m_safety_by('incident_type' / 'year_month')`, `m_safety_by_driver`, `m_latest_incidents` |
| 6 Customers | `bi.m_customer_overall()` | `m_customer_scorecard`, `m_finance_by('customer_type')` |
| 7 Routes | `bi.m_finance()`, `bi.m_scenario()` | `m_margin_bridge`, `m_lane_matrix`, `m_route_scorecard`, `m_city_network` |

Examples:

```sql
-- Executive cards for 2024
SELECT * FROM bi.m_kpi_exec(p_start := '2024-01-01', p_end := '2024-12-31');

-- Revenue and margin by quarter for one customer
SELECT dim_label AS quarter, total_revenue, gross_profit, gross_margin
FROM bi.m_finance_by('quarter', p_customer := 'CUST00002');

-- The five trucks most overdue for service
SELECT truck_id, days_since_last_service, service_status
FROM bi.m_truck_scorecard() ORDER BY days_since_last_service DESC NULLS LAST LIMIT 5;

-- Profit scenario: +5% rates and +10% fuel
UPDATE bi.parameter_selection SET selected_value = 0.05 WHERE parameter_name = 'rate_change';
UPDATE bi.parameter_selection SET selected_value = 0.10 WHERE parameter_name = 'fuel_price_change';
SELECT * FROM bi.m_scenario();
```

The by-dimension functions accept: `m_finance_by` year, quarter, month_number, year_month, day_name, customer, customer_type, freight_type, route, origin_city, destination_city, booking_type, load_type, driver, tenure_band, truck, truck_make, model_year, truck_age_band; `m_delivery_by` adds facility, facility_city, facility_state, detention_bucket; the others are listed in `MEASURE_CATALOGUE.md`. An unknown name raises an error that lists the valid ones. Dimension expressions are whitelisted in the function body, so no user text is ever put into the query.

## 5. Connecting Power BI or Excel

- **Import mode (recommended):** connect to the `bi` schema and import the `v_*` views you need. Refresh after each `CALL dw.load_star()`. Parameters then act on the database, not on the report.
- **Filtered or parameterised datasets:** use a native query that calls a function, for example `SELECT * FROM bi.m_finance_by('year_month', p_customer := 'CUST00002')`.
- **DirectQuery:** possible, but the measure functions aggregate over the facts on every call. Prefer import, or materialise the heavy views (section 8).
- **Rebuilding the Power BI report from SQL:** the views return the same numbers as the DAX measures for the same filters (see the differences in `MEASURE_CATALOGUE.md`).

## 6. Analysis walkthrough

File `sql/10_analysis_queries.sql` holds three groups of queries. The notes below say what each answers and what the reference dataset showed. Your numbers will differ if your data does.

### 6.1 Descriptive: what happened

| Query | Question | Reference result and how to read it |
|---|---|---|
| A1 | How do revenue, profit and margin move by month? | Revenue is steady month to month (monthly fuel spend is flat), so expect a flat trend. `revenue_py` and `revenue_yoy_pct` are NULL for the first year. Rolling 12 months needs 12 months of data. |
| A2 | Headline figures for one year | Full period: revenue $262.5M, Gross Profit about $161.2M, margin 61.4%, about 85,000 loads, $2.15 revenue per mile, about $0.83 cost per mile. |
| A3 | Which customer and freight types earn most? | Revenue by Contract, Spot and Dedicated customers; margins sit in a narrow band because costs follow miles. |
| A4 | How concentrated is revenue? | The top 18 of 200 customers hold 31.9% of revenue. The largest customer is about 3%, so concentration risk is low. |
| A5 | Where is fuel bought and at what price? | Texas and Tennessee each spend about $7.5M, roughly twice the next states. State prices are within about one cent of the fleet average. |
| A6 | How many incidents, of what kind, and at what rate? | 170 incidents, about 1.4 per million miles, about $3M in claims. |
| A7 | Where does freight start and end? | Positive `lane_balance` means more loads leave a city than arrive. Phoenix, Chicago and Las Vegas lean outbound; Detroit, Seattle, Portland and New York lean inbound. |

### 6.2 Diagnostic: why it happened

| Query | Question | How to read it |
|---|---|---|
| B1 | Why is the margin 61%? | Revenue per mile ($2.15) is far above fuel plus allocated maintenance per mile (about $0.83). The margin excludes driver pay, insurance, depreciation and overhead, so it is a contribution margin. The query also shows the margin after illustrative driver pay (about 34% at $0.60 per mile). |
| B2 | Do drivers differ? | A coefficient of variation near 0.01 to 0.1 means drivers are nearly identical. Idle time is 28.3% to 29.2% for every driver and MPG is about 6.45, so individual coaching will not move results; system levers will. |
| B3 | Does fuel price vary by month or by state? | By month: about $4.20 falling to about $3.85 and then about $3.65. By state: within about one cent. Compare the two `spread` values. |
| B4 | Where does on-time delivery fail? | Fleet on-time is about 55.7% against a 95% target. The query lists the weakest facilities, weekdays and customers; a flat result means the problem is systemic, not local. |
| B5 | Does detention explain lateness? | A correlation near -1 means facilities with more detention are later; near 0 means detention is not the driver. Interpret with the facility count. |
| B6 | How much revenue has no named driver? | About 2% of revenue ($5.26M, 1,714 trips) sits under DRV_UNKNOWN. |
| B7 | Does the maintenance allocation reconcile? | `difference` should be 0 for every month that has trip miles. A non-zero month means maintenance was dated in a month with no miles. |
| B8 | How wide is margin across customers and routes? | After the allocation, margins cluster in a narrow band around the fleet margin (about 58% to 66%). |

### 6.3 Predictive: what is likely next

These queries use transparent statistics, not a forecasting package. Treat the output as an indication.

| Query | Method | How to read it and its limits |
|---|---|---|
| C1 | Linear regression of monthly revenue on time (`regr_slope`, `regr_intercept`, `regr_r2`) and a six-month projection | `monthly_trend` is the change per month; `r2` says how much of the variation the line explains. With flat revenue, `r2` is low and the projection is simply the run-rate. It ignores seasonality and price changes. |
| C2 | Seasonality index: each calendar month's average over the overall average | An index above 1 is a seasonally strong month. Needs at least two years to be meaningful. |
| C3 | Churn risk: days since last load divided by the customer's usual gap between loads | A ratio above 1 means the customer is overdue against its own rhythm; well above 2 deserves a call. Customers with fewer than five loads are excluded. |
| C4 | Maintenance due: miles since last service against the truck's usual miles between services, converted to days by recent mileage | A small or negative `predicted_days_to_service` means the truck is due or overdue. It assumes steady daily mileage. |
| C5 | Scenario grid of rate changes against fuel price changes | Deterministic what-if arithmetic on today's totals. One percent of rate is worth about $2.6M of profit; ten percent of fuel price about $9.6M. |
| C6 | Fuel saved if the fleet reached a target MPG | Gallons and dollars saved at 6.5, 7.0, 7.5 and 8.0 MPG against the current fleet MPG (about 6.4). |

**Recommended next modelling** (outside this repository): a seasonal forecast of revenue and loads, a churn model trained on customer ordering patterns, and a maintenance-interval model. The SQL here prepares the clean inputs for each.

## 7. Testing and validation

1. **Reconciliation view.** `SELECT * FROM bi.v_checks;` compares the SQL results with the figures verified in the Power BI report (revenue 262,525,800.29, Gross Profit about $161.2M, margin 61.4%, 124 active drivers, 200 active customers, 170 incidents, four driver test rows and more). Run with no filters and default parameters. Replace the expected values with your own when you use different data.
2. **Data-quality view.** `SELECT * FROM bi.v_dq;` lists loads without trips, trips under DRV_UNKNOWN, fuel with no trip, blank states, blank model years and months with maintenance but no miles.
3. **Referential integrity.** `SELECT * FROM bi.v_orphan_check;` lists keys that would fail the optional foreign keys.
4. **Compare with Power BI.** Pick a filter (for example year 2024 and one customer), read the cards in the report, then run the same filter through the function. They should agree to rounding, except where `MEASURE_CATALOGUE.md` lists a difference.
5. **Reload test.** Run `CALL dw.load_star();` twice. Row counts must not change.
6. **Allocation test.** `SELECT ABS(SUM(maint_alloc) - (SELECT SUM(total_cost) FROM dw.fact_maintenance_event)) FROM dw.fact_load_trip;` should be about 0 (it differs only for months with maintenance but no miles).
7. **Edge cases.** Call a function with a customer that does not exist: counts return 0 and ratios return NULL (never an error).

## 8. Performance

- `dw.load_star()` runs `ANALYZE` on every table. Indexes exist on the load date and on every key used by the scope functions.
- Scope functions are plain SQL and are inlined into the calling query, so the planner uses the fact-table indexes.
- Scorecards that call other scorecards (`m_driver_overall` calls `m_driver_scorecard`) recompute them; for dashboards, import the views once and filter in the BI tool.
- If a view is slow, materialise it: `CREATE MATERIALIZED VIEW bi.mv_x AS SELECT * FROM bi.v_x;` and refresh it after `load_star()`.
- For very large fact tables, partition `fact_load_trip` and the child facts by `load_date` (year).
- Check a plan with `EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM bi.m_finance_by('year_month');`.

## 9. Extending the code

**Add a measure.**

1. Decide its grain and the function it belongs to (or create a new one).
2. Add a row to the matching block in `sql/07_measure_functions.sql` (or generate it): `(name, type, expression)`. The expression uses the scope alias `s`, and the type is cast explicitly.
3. If the declared type and the expression type differ, PostgreSQL raises a return-type error: cast the expression.
4. Add the measure to `MEASURE_CATALOGUE.md`.

**Add a dimension to a by-function.** Add the join (if needed) and one `WHEN` branch each to the key and label `CASE`s in the function.

**Add a parameter.** Insert a row into `bi.parameter` and `bi.parameter_selection`, read it with `bi.param('name')`, and add its value column to `bi.v_parameter_values`.

**Add a column to the star.** Add it to the `CREATE TABLE` in file 03 and to the `INSERT` in file 04, then rerun `CALL dw.load_star();`.

## 10. Other SQL dialects

The code uses PostgreSQL features. To port it:

| PostgreSQL | SQL Server | MySQL 8 |
|---|---|---|
| `COUNT(*) FILTER (WHERE x)` | `SUM(CASE WHEN x THEN 1 ELSE 0 END)` | `SUM(CASE WHEN x THEN 1 ELSE 0 END)` |
| `generate_series` | recursive CTE or a numbers table | recursive CTE |
| `::type` casts | `CAST(x AS type)` | `CAST(x AS type)` |
| `DATE_TRUNC('month', d)` | `DATEFROMPARTS(YEAR(d), MONTH(d), 1)` | `DATE_FORMAT(d, '%Y-%m-01')` |
| `RETURNS TABLE` functions | inline table-valued functions | stored procedures or views |
| `RANGE ... INTERVAL` windows | self-join over the previous 6 days | self-join |
| `GENERATED ... AS IDENTITY` | `IDENTITY(1,1)` | `AUTO_INCREMENT` |

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `column ... does not exist` while loading or building | A source column name differs from the assumed one | Edit `01` and the matching lines in `04`; rerun |
| `COPY` fails or loads shifted columns | CSV column order differs from the table definition | Reorder the `CREATE TABLE` columns to match the header |
| `duplicate key ... load_id` in `load_star` | A load has more than one trip | `SELECT * FROM bi.v_dq` row 'trips shared by more than one load'; fix the source or aggregate trips |
| `src.loads is empty` | Data not loaded | Run file 02 first |
| `function bi.xxx does not exist` | Files run out of order | Run 05, 06, 07, 08, 09 in order |
| Revenue is NULL or 0 for a filter | Mistyped id or a date range outside the data | Check the id in the dimension; leave dates NULL |
| `structure of query does not match function result type` | A measure expression returns a different type than declared | Add an explicit `::type` cast in the block |
| Active Trucks or Overdue Trucks is 0 | `trucks.status` does not contain 'Active' | Check the values with `SELECT status, COUNT(*) FROM src.trucks GROUP BY 1` |
| On-time is NULL | `event_type` has no 'Delivery' value, or `on_time_flag` is not boolean | Check section D of file 02; adjust the comparison |
| `Unknown dimension` error | A by-function was called with an unsupported name | Use one of the names listed in the error |

## 12. Limitations

- Not executed against a live database; see section 1.
- Source column names marked as assumed must be checked against your files.
- Gross Profit is a contribution margin (fuel and allocated maintenance only).
- The predictive queries are simple trend and ratio models, suitable for indications, not for planning on their own.
- Some measures are only meaningful with a year selected (New Customers, Retention %, Wallet Share), as in the report.
