-- ================================================================================================
-- 09  DATA QUALITY AND RECONCILIATION
-- ================================================================================================
-- bi.v_dq             data gaps found while building the report.
-- bi.v_orphan_check   keys that would violate the optional foreign keys.
-- bi.v_checks         reconciliation against the figures verified in Power BI.
-- Run v_checks with the default parameters and no filters. Every row should show pass = true.
-- The figures belong to the reference dataset; replace the expected values for your own data.
-- ================================================================================================

CREATE OR REPLACE VIEW bi.v_dq AS
SELECT 'loads without a trip'::text AS metric, COUNT(*)::numeric AS value
  FROM src.loads l LEFT JOIN src.trips t ON t.load_id = l.load_id WHERE t.trip_id IS NULL
UNION ALL SELECT 'trips without a load', COUNT(*) FROM src.trips t LEFT JOIN src.loads l ON l.load_id = t.load_id WHERE l.load_id IS NULL
UNION ALL SELECT 'trips under DRV_UNKNOWN', COUNT(*) FROM src.trips WHERE driver_id = 'DRV_UNKNOWN'
UNION ALL SELECT 'revenue under DRV_UNKNOWN', COALESCE(SUM(l.revenue), 0) FROM src.trips t JOIN src.loads l ON l.load_id = t.load_id WHERE t.driver_id = 'DRV_UNKNOWN'
UNION ALL SELECT 'fuel rows with no trip_id', COUNT(*) FROM src.fuel_purchases WHERE trip_id IS NULL
UNION ALL SELECT 'fuel cost with no trip_id', COALESCE(SUM(total_cost), 0) FROM src.fuel_purchases WHERE trip_id IS NULL
UNION ALL SELECT 'fuel rows with blank state', COUNT(*) FROM src.fuel_purchases WHERE location_state IS NULL OR location_state = ''
UNION ALL SELECT 'safety rows with no trip_id', COUNT(*) FROM src.safety_incidents WHERE trip_id IS NULL
UNION ALL SELECT 'delivery rows with no trip_id', COUNT(*) FROM src.delivery_events WHERE trip_id IS NULL
UNION ALL SELECT 'trucks with blank model_year', COUNT(*) FROM src.trucks WHERE model_year IS NULL
UNION ALL SELECT 'drivers with no hire_date', COUNT(*) FROM src.drivers WHERE hire_date IS NULL
UNION ALL SELECT 'distinct account_status values', COUNT(DISTINCT account_status) FROM src.customers
UNION ALL SELECT 'distinct load_status values', COUNT(DISTINCT load_status) FROM src.loads
UNION ALL SELECT 'distinct event_type values', COUNT(DISTINCT event_type) FROM src.delivery_events
UNION ALL SELECT 'months with maintenance but no miles', COUNT(*) FROM dw.month_maint_ratio WHERE maintenance_cost IS NOT NULL AND (miles IS NULL OR miles = 0)
UNION ALL SELECT 'trips shared by more than one load', COUNT(*) FROM (SELECT load_id FROM src.trips GROUP BY load_id HAVING COUNT(*) > 1) x;

CREATE OR REPLACE VIEW bi.v_orphan_check AS
SELECT 'fact_load_trip.customer_id' AS fk, COUNT(*) AS orphans FROM dw.fact_load_trip f LEFT JOIN dw.dim_customer d ON d.customer_id = f.customer_id WHERE f.customer_id IS NOT NULL AND d.customer_id IS NULL
UNION ALL SELECT 'fact_load_trip.route_id', COUNT(*) FROM dw.fact_load_trip f LEFT JOIN dw.dim_route d ON d.route_id = f.route_id WHERE f.route_id IS NOT NULL AND d.route_id IS NULL
UNION ALL SELECT 'fact_load_trip.driver_id', COUNT(*) FROM dw.fact_load_trip f LEFT JOIN dw.dim_driver d ON d.driver_id = f.driver_id WHERE f.driver_id IS NOT NULL AND d.driver_id IS NULL
UNION ALL SELECT 'fact_load_trip.truck_id', COUNT(*) FROM dw.fact_load_trip f LEFT JOIN dw.dim_truck d ON d.truck_id = f.truck_id WHERE f.truck_id IS NOT NULL AND d.truck_id IS NULL
UNION ALL SELECT 'fact_load_trip.trailer_id', COUNT(*) FROM dw.fact_load_trip f LEFT JOIN dw.dim_trailer d ON d.trailer_id = f.trailer_id WHERE f.trailer_id IS NOT NULL AND d.trailer_id IS NULL
UNION ALL SELECT 'fact_load_trip.load_date', COUNT(*) FROM dw.fact_load_trip f LEFT JOIN dw.dim_date d ON d.full_date = f.load_date WHERE f.load_date IS NOT NULL AND d.full_date IS NULL
UNION ALL SELECT 'fact_delivery_event.facility_id', COUNT(*) FROM dw.fact_delivery_event f LEFT JOIN dw.dim_facility d ON d.facility_id = f.facility_id WHERE f.facility_id IS NOT NULL AND d.facility_id IS NULL
UNION ALL SELECT 'fact_maintenance_event.truck_id', COUNT(*) FROM dw.fact_maintenance_event f LEFT JOIN dw.dim_truck d ON d.truck_id = f.truck_id WHERE f.truck_id IS NOT NULL AND d.truck_id IS NULL
UNION ALL SELECT 'fact_maintenance_event.maintenance_date', COUNT(*) FROM dw.fact_maintenance_event f LEFT JOIN dw.dim_date d ON d.full_date = f.maintenance_date WHERE f.maintenance_date IS NOT NULL AND d.full_date IS NULL
UNION ALL SELECT 'fact_truck_month.truck_id', COUNT(*) FROM dw.fact_truck_month f LEFT JOIN dw.dim_truck d ON d.truck_id = f.truck_id WHERE f.truck_id IS NOT NULL AND d.truck_id IS NULL
UNION ALL SELECT 'fact_driver_month.driver_id', COUNT(*) FROM dw.fact_driver_month f LEFT JOIN dw.dim_driver d ON d.driver_id = f.driver_id WHERE f.driver_id IS NOT NULL AND d.driver_id IS NULL;

CREATE OR REPLACE VIEW bi.v_checks AS
WITH o  AS (SELECT * FROM bi.m_finance()),
     c  AS (SELECT * FROM bi.m_customer_overall()),
     dr AS (SELECT * FROM bi.m_driver_overall()),
     sf AS (SELECT * FROM bi.m_safety_overall()),
     sv AS (SELECT * FROM bi.m_service()),
     fx AS (SELECT driver_id, SUM(revenue) AS revenue, COUNT(trip_id) AS trips, SUM(miles) * bi.param('driver_pay_per_mile') AS driver_cost
            FROM dw.fact_load_trip GROUP BY driver_id)
SELECT check_name, expected, actual, tolerance, (ABS(actual - expected) <= tolerance) AS pass
FROM (
    SELECT 'Total Revenue'::text AS check_name, 262525800.29::numeric AS expected, (SELECT total_revenue FROM o)::numeric AS actual, 0.01::numeric AS tolerance
    UNION ALL SELECT 'Gross Profit (about 161.2M)',          161200000, (SELECT gross_profit FROM o), 100000
    UNION ALL SELECT 'Gross Margin',                         0.614,     (SELECT gross_margin FROM o), 0.0006
    UNION ALL SELECT 'Load Count (about 85,000)',            85000,     (SELECT load_count FROM o), 1500
    UNION ALL SELECT 'Revenue Per Mile',                     2.15,      (SELECT revenue_per_mile FROM o), 0.006
    UNION ALL SELECT 'Route Cost per Mile (about 0.83)',     0.83,      (SELECT route_cost_per_mile FROM o), 0.01
    UNION ALL SELECT 'Avg MPG (6.4 to 6.45)',                6.43,      (SELECT avg_mpg FROM o), 0.03
    UNION ALL SELECT 'Distance Variance %',                  0.0295,    (SELECT distance_variance_pct FROM o), 0.0005
    UNION ALL SELECT 'On-Time % (delivery events)',          0.5567,    (SELECT on_time_pct FROM sv), 0.0005
    UNION ALL SELECT 'Active Drivers',                       124,       (SELECT active_drivers FROM dr), 0
    UNION ALL SELECT 'Active Customers',                     200,       (SELECT active_customers FROM c), 0
    UNION ALL SELECT 'Avg Revenue per Customer (1.31M)',     1310000,   (SELECT avg_revenue_per_customer FROM c), 10000
    UNION ALL SELECT 'Safety Incidents',                     170,       (SELECT safety_incidents FROM sf), 0
    UNION ALL SELECT 'Incidents per 1M Miles (about 1.4)',   1.39,      (SELECT incidents_per_1m_miles FROM sf), 0.05
    UNION ALL SELECT 'Safety incident (per 100K miles, 0.14)', 0.14,    (SELECT safety_incident FROM sf), 0.005
    UNION ALL SELECT 'Monthly metrics miles, named drivers', 119692305, (SELECT SUM(total_miles) FROM dw.fact_driver_month), 1
    UNION ALL SELECT 'DRV_UNKNOWN revenue',                  5261249.70, (SELECT revenue FROM fx WHERE driver_id = 'DRV_UNKNOWN'), 0.01
    UNION ALL SELECT 'DRV_UNKNOWN trips',                    1714,      (SELECT trips FROM fx WHERE driver_id = 'DRV_UNKNOWN'), 0
    UNION ALL SELECT 'DRV00001 revenue',                     1985683.26, (SELECT revenue FROM fx WHERE driver_id = 'DRV00001'), 0.01
    UNION ALL SELECT 'DRV00001 trips',                       632,       (SELECT trips FROM fx WHERE driver_id = 'DRV00001'), 0
    UNION ALL SELECT 'DRV00001 driver cost (at 0.60/mile)',  558141.60, (SELECT driver_cost FROM fx WHERE driver_id = 'DRV00001'), 0.01
    UNION ALL SELECT 'DRV00002 revenue',                     2073621.50, (SELECT revenue FROM fx WHERE driver_id = 'DRV00002'), 0.01
    UNION ALL SELECT 'DRV00002 trips',                       662,       (SELECT trips FROM fx WHERE driver_id = 'DRV00002'), 0
    UNION ALL SELECT 'DRV00003 revenue',                     2146977.47, (SELECT revenue FROM fx WHERE driver_id = 'DRV00003'), 0.01
    UNION ALL SELECT 'DRV00003 trips',                       677,       (SELECT trips FROM fx WHERE driver_id = 'DRV00003'), 0
    UNION ALL SELECT 'Sum of driver revenue = Total Revenue', 262525800.29, (SELECT SUM(revenue) FROM fx), 0.01
    UNION ALL SELECT 'Allocated maintenance = actual maintenance (difference)', 0,
           (SELECT ABS(SUM(maint_alloc) - (SELECT SUM(total_cost) FROM dw.fact_maintenance_event)) FROM dw.fact_load_trip), 1
) t;
