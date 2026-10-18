-- ================================================================================================
-- 04  ETL: LOAD THE STAR FROM THE LANDING TABLES
-- ================================================================================================
-- CALL dw.load_star();  truncates and rebuilds every dw table in dependency order.
-- Run it again after each reload of src. Raises an error if src.loads is empty.
-- Rules baked into the load:
--   * Maintenance Record joins only to trucks, so maintenance is allocated to loads by miles using
--     each calendar month's maintenance cost per mile (dw.month_maint_ratio).
--   * gross_profit = revenue - fuel cost - allocated maintenance. It excludes driver pay and overhead.
--   * Child facts take date, customer, route, driver and truck from their trip's load.
--   * Rows with no trip_id keep NULL keys; they drop out of date-filtered results, as in the report.
-- ================================================================================================

CREATE OR REPLACE PROCEDURE dw.load_star()
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_as_of date;
BEGIN
    SELECT MAX(load_date) INTO v_as_of FROM src.loads;
    IF v_as_of IS NULL THEN
        RAISE EXCEPTION 'src.loads is empty: load the source data first (file 02)';
    END IF;

    TRUNCATE dw.dim_date, dw.dim_customer, dw.dim_route, dw.dim_driver, dw.dim_truck, dw.dim_trailer, dw.dim_facility, dw.dim_network_city, dw.dim_margin_bridge, dw.month_maint_ratio, dw.fact_load_trip, dw.fact_fuel_purchase, dw.fact_delivery_event, dw.fact_safety_incident, dw.fact_maintenance_event, dw.fact_truck_month, dw.fact_driver_month;

    -- ------------------------------------------------------------ dimensions
    INSERT INTO dw.dim_date (full_date, year, quarter, month_number, month_name, month_year,
                             year_month_sort, year_month, day_name, day_number, month_start)
    SELECT g.d::date,
           EXTRACT(YEAR FROM g.d)::integer,
           'Q' || EXTRACT(QUARTER FROM g.d)::integer,
           EXTRACT(MONTH FROM g.d)::integer,
           TRIM(TO_CHAR(g.d, 'Month')),
           TO_CHAR(g.d, 'YYYYMM'),
           (EXTRACT(YEAR FROM g.d) * 100 + EXTRACT(MONTH FROM g.d))::integer,
           TO_CHAR(g.d, 'YYYY-MM'),
           TRIM(TO_CHAR(g.d, 'Dy')),
           EXTRACT(ISODOW FROM g.d)::integer,
           DATE_TRUNC('month', g.d)::date
    FROM generate_series(
            (SELECT DATE_TRUNC('year', MIN(load_date)) FROM src.loads)::timestamp,
            (SELECT DATE_TRUNC('year', MAX(load_date)) + INTERVAL '1 year - 1 day' FROM src.loads)::timestamp,
            INTERVAL '1 day') AS g(d);

    INSERT INTO dw.dim_customer
    SELECT customer_id, customer_name, customer_type, credit_terms_days, primary_freight_type,
           account_status, contract_start_date, annual_revenue_potential
    FROM src.customers;

    INSERT INTO dw.dim_route
    SELECT route_id, origin_city, destination_city, origin_city || ' → ' || destination_city,
           typical_distance_miles, base_rate_per_mile
    FROM src.routes;

    INSERT INTO dw.dim_driver (driver_id, first_name, last_name, driver_name, hire_date, termination_date,
                               employment_status, home_terminal, tenure_years, tenure_band, tenure_band_sort)
    SELECT d.driver_id, d.first_name, d.last_name,
           COALESCE(d.first_name || ' ' || d.last_name, d.driver_id),
           d.hire_date, d.termination_date, d.employment_status, d.home_terminal,
           t.yrs,
           CASE WHEN d.hire_date IS NULL THEN 'Unknown' WHEN t.yrs < 1 THEN '0-1 yr'
                WHEN t.yrs < 3 THEN '1-3 yrs' WHEN t.yrs < 6 THEN '3-6 yrs' ELSE '6+ yrs' END,
           CASE WHEN d.hire_date IS NULL THEN 5 WHEN t.yrs < 1 THEN 1
                WHEN t.yrs < 3 THEN 2 WHEN t.yrs < 6 THEN 3 ELSE 4 END
    FROM src.drivers d
    CROSS JOIN LATERAL (SELECT (COALESCE(d.termination_date, v_as_of) - d.hire_date) / 365.25 AS yrs) t;

    INSERT INTO dw.dim_truck (truck_id, make, model_year, status, home_terminal, fuel_type, truck_age, truck_age_band)
    SELECT k.truck_id, k.make, k.model_year, k.status, k.home_terminal, k.fuel_type,
           CASE WHEN k.model_year IS NULL THEN NULL ELSE EXTRACT(YEAR FROM v_as_of)::integer - k.model_year END,
           CASE WHEN k.model_year IS NULL THEN 'Unknown'
                WHEN EXTRACT(YEAR FROM v_as_of)::integer - k.model_year <= 2 THEN '0-2 yrs'
                WHEN EXTRACT(YEAR FROM v_as_of)::integer - k.model_year <= 5 THEN '3-5 yrs'
                ELSE '6+ yrs' END
    FROM src.trucks k;

    INSERT INTO dw.dim_trailer SELECT trailer_id, trailer_type FROM src.trailers;
    INSERT INTO dw.dim_facility SELECT facility_id, facility_name, city, state, latitude, longitude FROM src.facilities;

    INSERT INTO dw.dim_network_city
    SELECT origin_city FROM src.routes WHERE origin_city IS NOT NULL
    UNION
    SELECT destination_city FROM src.routes WHERE destination_city IS NOT NULL;

    INSERT INTO dw.dim_margin_bridge VALUES ('Revenue', 1), ('Fuel', 2), ('Maintenance', 3), ('Gross Profit', 4);

    -- ------------------------------------------------------------ maintenance allocation basis
    INSERT INTO dw.month_maint_ratio (month_start, maintenance_cost, miles, maint_cost_per_mile)
    WITH m AS (
        SELECT DATE_TRUNC('month', maintenance_date)::date AS month_start, SUM(total_cost) AS maintenance_cost
        FROM src.maintenance_record GROUP BY 1
    ), t AS (
        SELECT DATE_TRUNC('month', l.load_date)::date AS month_start, SUM(tr.actual_distance_miles) AS miles
        FROM src.loads l JOIN src.trips tr ON tr.load_id = l.load_id GROUP BY 1
    )
    SELECT COALESCE(m.month_start, t.month_start), m.maintenance_cost, t.miles,
           CASE WHEN t.miles IS NULL OR t.miles = 0 THEN NULL ELSE m.maintenance_cost / t.miles END
    FROM m FULL JOIN t ON t.month_start = m.month_start
    WHERE COALESCE(m.month_start, t.month_start) IS NOT NULL;

    -- ------------------------------------------------------------ fact_load_trip
    INSERT INTO dw.fact_load_trip (
        load_id, load_date, customer_id, route_id, origin_city, destination_city, booking_type, load_type, load_status,
        revenue, expected_linehaul_revenue, trip_id, driver_id, truck_id, trailer_id, miles, expected_miles,
        duration_hours, fuel_gallons_used, idle_hours, fuel_cost, fuel_gallons_purchased, maint_alloc, gross_profit)
    WITH fuel AS (
        SELECT trip_id, SUM(total_cost) AS fuel_cost, SUM(gallons) AS fuel_gallons
        FROM src.fuel_purchases WHERE trip_id IS NOT NULL GROUP BY trip_id
    )
    SELECT l.load_id, l.load_date, l.customer_id, l.route_id, r.origin_city, r.destination_city,
           l.booking_type, l.load_type, l.load_status, l.revenue,
           r.typical_distance_miles * r.base_rate_per_mile,
           t.trip_id, t.driver_id, t.truck_id, t.trailer_id,
           t.actual_distance_miles,
           CASE WHEN t.trip_id IS NOT NULL THEN r.typical_distance_miles END,
           t.actual_duration_hours, t.fuel_gallons_used, t.idle_time_hours,
           COALESCE(f.fuel_cost, 0), COALESCE(f.fuel_gallons, 0),
           COALESCE(t.actual_distance_miles, 0) * COALESCE(m.maint_cost_per_mile, 0),
           l.revenue - ( COALESCE(f.fuel_cost, 0)
                         + COALESCE(t.actual_distance_miles, 0) * COALESCE(m.maint_cost_per_mile, 0) )
    FROM src.loads l
    LEFT JOIN src.routes r ON r.route_id = l.route_id
    LEFT JOIN src.trips t ON t.load_id = l.load_id
    LEFT JOIN fuel f ON f.trip_id = t.trip_id
    LEFT JOIN dw.month_maint_ratio m ON m.month_start = DATE_TRUNC('month', l.load_date)::date;

    -- ------------------------------------------------------------ child facts (conformed keys from the load)
    INSERT INTO dw.fact_fuel_purchase (fuel_purchase_id, trip_id, purchase_date, location_state, gallons, price_per_gallon, total_cost,
        load_id, load_date, customer_id, route_id, origin_city, destination_city, booking_type, driver_id, truck_id)
    SELECT fp.fuel_purchase_id, fp.trip_id, fp.purchase_date, NULLIF(fp.location_state, ''), fp.gallons, fp.price_per_gallon, fp.total_cost,
           b.load_id, b.load_date, b.customer_id, b.route_id, b.origin_city, b.destination_city, b.booking_type, b.driver_id, b.truck_id
    FROM src.fuel_purchases fp
    LEFT JOIN dw.fact_load_trip b ON b.trip_id = fp.trip_id;

    INSERT INTO dw.fact_delivery_event (event_id, trip_id, facility_id, event_type, scheduled_datetime, actual_datetime,
        detention_minutes, on_time_flag, is_delivery, detention_hours, detention_bucket, detention_bucket_sort,
        load_id, load_date, customer_id, route_id, origin_city, destination_city, booking_type, driver_id, truck_id)
    SELECT de.event_id, de.trip_id, de.facility_id, de.event_type, de.scheduled_datetime, de.actual_datetime,
           de.detention_minutes, de.on_time_flag, COALESCE(de.event_type = 'Delivery', FALSE), de.detention_minutes / 60.0,
           CASE WHEN COALESCE(de.detention_minutes, 0) <= 0 THEN 'None' WHEN de.detention_minutes <= 60 THEN '0-1 h'
                WHEN de.detention_minutes <= 120 THEN '1-2 h' WHEN de.detention_minutes <= 240 THEN '2-4 h' ELSE '4 h+' END,
           CASE WHEN COALESCE(de.detention_minutes, 0) <= 0 THEN 1 WHEN de.detention_minutes <= 60 THEN 2
                WHEN de.detention_minutes <= 120 THEN 3 WHEN de.detention_minutes <= 240 THEN 4 ELSE 5 END,
           b.load_id, b.load_date, b.customer_id, b.route_id, b.origin_city, b.destination_city, b.booking_type, b.driver_id, b.truck_id
    FROM src.delivery_events de
    LEFT JOIN dw.fact_load_trip b ON b.trip_id = de.trip_id;

    INSERT INTO dw.fact_safety_incident (incident_id, trip_id, incident_date, incident_type, at_fault_flag, preventable_flag, injury_flag,
        claim_amount, vehicle_damage_cost, cargo_damage_cost,
        load_id, load_date, customer_id, route_id, origin_city, destination_city, booking_type, driver_id, truck_id)
    SELECT si.incident_id, si.trip_id, si.incident_date, si.incident_type, si.at_fault_flag, si.preventable_flag, si.injury_flag,
           si.claim_amount, si.vehicle_damage_cost, si.cargo_damage_cost,
           b.load_id, b.load_date, b.customer_id, b.route_id, b.origin_city, b.destination_city, b.booking_type, b.driver_id, b.truck_id
    FROM src.safety_incidents si
    LEFT JOIN dw.fact_load_trip b ON b.trip_id = si.trip_id;

    INSERT INTO dw.fact_maintenance_event
    SELECT maintenance_id, truck_id, maintenance_date, maintenance_type, labor_cost, labor_hours, parts_cost,
           total_cost, downtime_hours, facility_location
    FROM src.maintenance_record;

    INSERT INTO dw.fact_truck_month (truck_id, month_start, average_mpg, downtime_hours, maintenance_events,
                                     maintenance_cost, total_miles, total_revenue, utilization_rate)
    SELECT truck_id, DATE_TRUNC('month', month)::date, average_mpg, downtime_hours, maintenance_events,
           maintenance_cost, total_miles, total_revenue, utilization_rate
    FROM src.truck_utilization_metrics;

    INSERT INTO dw.fact_driver_month (driver_id, month_start, trips_completed, total_miles, on_time_delivery_rate)
    SELECT driver_id, DATE_TRUNC('month', month)::date, trips_completed, total_miles, on_time_delivery_rate
    FROM src.driver_monthly_metrics;

    ANALYZE dw.dim_date;
    ANALYZE dw.dim_customer;
    ANALYZE dw.dim_route;
    ANALYZE dw.dim_driver;
    ANALYZE dw.dim_truck;
    ANALYZE dw.dim_trailer;
    ANALYZE dw.dim_facility;
    ANALYZE dw.dim_network_city;
    ANALYZE dw.dim_margin_bridge;
    ANALYZE dw.month_maint_ratio;
    ANALYZE dw.fact_load_trip;
    ANALYZE dw.fact_fuel_purchase;
    ANALYZE dw.fact_delivery_event;
    ANALYZE dw.fact_safety_incident;
    ANALYZE dw.fact_maintenance_event;
    ANALYZE dw.fact_truck_month;
    ANALYZE dw.fact_driver_month;
END;
$proc$;

-- After loading src (file 02):
--   CALL dw.load_star();
