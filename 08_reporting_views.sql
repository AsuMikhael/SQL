-- ================================================================================================
-- 08  REPORTING VIEWS: ONE DATASET PER DASHBOARD VISUAL
-- ================================================================================================
-- Unfiltered datasets for a BI tool (import or DirectQuery). Each view calls a measure function with its
-- defaults (every filter = All). For a filtered result, call the function directly with arguments:
--   SELECT * FROM bi.m_finance_by('year_month', p_start := '2024-01-01', p_end := '2024-12-31');
-- Executive = page 1, Operations = 2, Drivers = 3, Fleet = 4, Fuel & Safety = 5, Customers = 6, Routes = 7.
-- ================================================================================================

-- Executive cards and headline
CREATE OR REPLACE VIEW bi.v_exec_kpis AS
SELECT * FROM bi.m_kpi_exec();

-- Revenue by month vs prior year
CREATE OR REPLACE VIEW bi.v_exec_revenue_trend AS
SELECT * FROM bi.m_revenue_trend();

-- Top 10 customers
CREATE OR REPLACE VIEW bi.v_exec_top_customers AS
SELECT * FROM bi.m_customer_scorecard() ORDER BY customer_rank LIMIT 10;

-- Route scatter
CREATE OR REPLACE VIEW bi.v_exec_routes AS
SELECT * FROM bi.m_route_scorecard();

-- Truck utilization bar
CREATE OR REPLACE VIEW bi.v_exec_truck_utilization AS
SELECT truck_id, fleet_utilization_pct, utilization_status_color FROM (SELECT t.truck_id, t.fleet_utilization_pct, bi.f_color_utilization(t.fleet_utilization_pct) AS utilization_status_color FROM bi.m_truck_scorecard() t) x;

-- Facility map with coordinates
CREATE OR REPLACE VIEW bi.v_exec_facility_map AS
SELECT d.*, f.latitude, f.longitude FROM bi.m_delivery_by('facility') d JOIN dw.dim_facility f ON f.facility_id = d.dim_key;

-- Operations cards
CREATE OR REPLACE VIEW bi.v_ops_kpis AS
SELECT * FROM bi.m_service();

-- Loads per day with 7-day average
CREATE OR REPLACE VIEW bi.v_ops_daily AS
SELECT * FROM bi.m_loads_daily();

-- Booking type donut
CREATE OR REPLACE VIEW bi.v_ops_booking_mix AS
SELECT dim_label AS booking_type, load_count, delivery_volume_share FROM bi.m_finance_by('booking_type');

-- On-time by month
CREATE OR REPLACE VIEW bi.v_ops_ontime_trend AS
SELECT * FROM bi.m_delivery_by('year_month');

-- Weekday by month heat map
CREATE OR REPLACE VIEW bi.v_ops_ontime_weekday_month AS
SELECT dd.day_number, dd.day_name, dd.month_number, dd.month_name, COUNT(*) FILTER (WHERE s.is_delivery) AS total_deliveries, bi.sdiv(COUNT(*) FILTER (WHERE s.is_delivery AND s.on_time_flag IS TRUE), COUNT(*) FILTER (WHERE s.is_delivery)) AS on_time_pct FROM dw.fact_delivery_event s JOIN dw.dim_date dd ON dd.full_date = s.load_date GROUP BY dd.day_number, dd.day_name, dd.month_number, dd.month_name;

-- Detention bar, scatter and map
CREATE OR REPLACE VIEW bi.v_ops_facilities AS
SELECT d.*, f.latitude, f.longitude FROM bi.m_delivery_by('facility') d JOIN dw.dim_facility f ON f.facility_id = d.dim_key;

-- Detention histogram
CREATE OR REPLACE VIEW bi.v_ops_detention_buckets AS
SELECT * FROM bi.m_delivery_by('detention_bucket');

-- Late deliveries treemap
CREATE OR REPLACE VIEW bi.v_ops_late_by_customer AS
SELECT dim_label AS customer_name, late_deliveries FROM bi.m_delivery_by('customer');

-- Driver cards
CREATE OR REPLACE VIEW bi.v_drivers_kpis AS
SELECT * FROM bi.m_driver_overall();

-- Driver scorecard, scatter and Top N
CREATE OR REPLACE VIEW bi.v_drivers_scorecard AS
SELECT * FROM bi.m_driver_scorecard();

-- Miles and on-time by month
CREATE OR REPLACE VIEW bi.v_drivers_monthly AS
SELECT f.dim_key AS year_month, f.total_miles, d.on_time_pct AS driver_on_time_pct FROM bi.m_finance_by('year_month') f LEFT JOIN bi.m_delivery_by('year_month') d ON d.dim_key = f.dim_key;

-- Driver Score by tenure
CREATE OR REPLACE VIEW bi.v_drivers_by_tenure AS
SELECT * FROM bi.m_driver_by_tenure();

-- Trips by idle share
CREATE OR REPLACE VIEW bi.v_drivers_idle_band AS
SELECT * FROM bi.m_idle_band();

-- Fleet cards
CREATE OR REPLACE VIEW bi.v_fleet_kpis AS
SELECT * FROM bi.m_fleet_overall();

-- Truck scatter, Top N and service-due table
CREATE OR REPLACE VIEW bi.v_fleet_trucks AS
SELECT * FROM bi.m_truck_scorecard();

-- Labor and parts by month
CREATE OR REPLACE VIEW bi.v_fleet_cost_by_month AS
SELECT * FROM bi.m_maintenance_by('year_month');

-- Cost by maintenance type
CREATE OR REPLACE VIEW bi.v_fleet_cost_by_type AS
SELECT * FROM bi.m_maintenance_by('maintenance_type');

-- Maintenance cost per mile by model year
CREATE OR REPLACE VIEW bi.v_fleet_cost_by_model_year AS
SELECT m.dim_key AS model_year, m.maintenance_cost, f.total_miles, bi.sdiv(m.maintenance_cost, f.total_miles) AS maint_cost_per_mile_actual FROM bi.m_maintenance_by('model_year') m LEFT JOIN bi.m_finance_by('model_year') f ON f.dim_key = m.dim_key;

-- Trailer utilization
CREATE OR REPLACE VIEW bi.v_fleet_trailers AS
SELECT * FROM bi.m_trailer_util_by_type();

-- Fuel cards and what-if panel
CREATE OR REPLACE VIEW bi.v_fuel_kpis AS
SELECT * FROM bi.m_fuel_overall();

-- Fuel cost and price by month
CREATE OR REPLACE VIEW bi.v_fuel_by_month AS
SELECT * FROM bi.m_fuel_by('year_month');

-- Fuel spend and price by state
CREATE OR REPLACE VIEW bi.v_fuel_by_state AS
SELECT * FROM bi.m_fuel_by_state();

-- MPG and cost per mile by model year
CREATE OR REPLACE VIEW bi.v_fuel_mpg_by_model_year AS
SELECT dim_key AS model_year, avg_mpg, cost_per_mile FROM bi.m_finance_by('model_year');

-- Safety cards
CREATE OR REPLACE VIEW bi.v_safety_kpis AS
SELECT * FROM bi.m_safety_overall();

-- Incidents by type
CREATE OR REPLACE VIEW bi.v_safety_by_type AS
SELECT * FROM bi.m_safety_by('incident_type');

-- Incidents and at-fault share by month
CREATE OR REPLACE VIEW bi.v_safety_by_month AS
SELECT * FROM bi.m_safety_by('year_month');

-- Drivers with most incidents
CREATE OR REPLACE VIEW bi.v_safety_by_driver AS
SELECT * FROM bi.m_safety_by_driver();

-- Latest 20 incidents
CREATE OR REPLACE VIEW bi.v_safety_latest AS
SELECT * FROM bi.m_latest_incidents();

-- Customer cards
CREATE OR REPLACE VIEW bi.v_customers_kpis AS
SELECT * FROM bi.m_customer_overall();

-- Pareto, quadrant, scorecard and at-risk list
CREATE OR REPLACE VIEW bi.v_customers_scorecard AS
SELECT * FROM bi.m_customer_scorecard();

-- Revenue treemap
CREATE OR REPLACE VIEW bi.v_customers_by_type AS
SELECT c.customer_type, c.primary_freight_type, SUM(f.revenue) AS customer_revenue, SUM(f.gross_profit) AS customer_margin, COUNT(*) AS load_count FROM dw.fact_load_trip f JOIN dw.dim_customer c ON c.customer_id = f.customer_id GROUP BY c.customer_type, c.primary_freight_type;

-- Monthly revenue of the top 5 customers
CREATE OR REPLACE VIEW bi.v_customers_top5_monthly AS
SELECT c.customer_name, dd.year_month, SUM(f.revenue) AS customer_revenue FROM dw.fact_load_trip f JOIN dw.dim_customer c ON c.customer_id = f.customer_id JOIN dw.dim_date dd ON dd.full_date = f.load_date WHERE f.customer_id IN (SELECT customer_id FROM bi.m_customer_scorecard() WHERE customer_rank <= 5) GROUP BY c.customer_name, dd.year_month;

-- Route cards (same pack as Executive)
CREATE OR REPLACE VIEW bi.v_routes_kpis AS
SELECT * FROM bi.m_finance();

-- Top and bottom routes, scatter
CREATE OR REPLACE VIEW bi.v_routes_scorecard AS
SELECT * FROM bi.m_route_scorecard();

-- Lane matrix
CREATE OR REPLACE VIEW bi.v_routes_lanes AS
SELECT * FROM bi.m_lane_matrix();

-- Loads out and in, lane balance
CREATE OR REPLACE VIEW bi.v_routes_network AS
SELECT * FROM bi.m_city_network();

-- Waterfall
CREATE OR REPLACE VIEW bi.v_routes_bridge AS
SELECT * FROM bi.m_margin_bridge();

-- Scenario cards
CREATE OR REPLACE VIEW bi.v_routes_scenario AS
SELECT * FROM bi.m_scenario();

