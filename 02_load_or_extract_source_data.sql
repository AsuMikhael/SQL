-- ================================================================================================
-- 02  LOAD OR EXTRACT THE SOURCE DATA
-- ================================================================================================
-- Choose ONE of the three options, then run the profiling queries in section D.
--   A  Load CSV files with COPY (or psql's \copy for files on your own machine).
--   B  Pull from another PostgreSQL database with postgres_fdw.
--   C  Run the extraction SELECTs against any source system (ANSI SQL, with notes for SQL Server and MySQL),
--      export the result sets to CSV, then use option A.
-- COPY needs the CSV column order to match the table definitions in 01.
-- ================================================================================================

-- =====================================================================
-- A. CSV FILES
-- =====================================================================
-- TRUNCATE the landing tables first if you are reloading.
-- COPY src.customers                  FROM '/data/customers.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.drivers                    FROM '/data/drivers.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.trucks                     FROM '/data/trucks.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.trailers                   FROM '/data/trailers.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.facilities                 FROM '/data/facilities.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.routes                     FROM '/data/routes.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.loads                      FROM '/data/loads.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.trips                      FROM '/data/trips.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.fuel_purchases             FROM '/data/fuel_purchases.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.maintenance_record         FROM '/data/maintenance_records.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.delivery_events            FROM '/data/delivery_events.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.safety_incidents           FROM '/data/safety_incidents.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.driver_monthly_metrics     FROM '/data/driver_monthly_metrics.csv' WITH (FORMAT csv, HEADER true);
-- COPY src.truck_utilization_metrics  FROM '/data/truck_utilization_metrics.csv' WITH (FORMAT csv, HEADER true);
-- psql client-side alternative:  \copy src.loads FROM 'loads.csv' WITH (FORMAT csv, HEADER true)

-- =====================================================================
-- B. POSTGRES FOREIGN DATA WRAPPER (pull from another database)
-- =====================================================================
-- CREATE EXTENSION IF NOT EXISTS postgres_fdw;
-- CREATE SERVER logistics_source FOREIGN DATA WRAPPER postgres_fdw
--     OPTIONS (host 'SOURCE_HOST', port '5432', dbname 'SOURCE_DB');
-- CREATE USER MAPPING FOR CURRENT_USER SERVER logistics_source
--     OPTIONS (user 'SOURCE_USER', password 'SOURCE_PASSWORD');
-- CREATE SCHEMA IF NOT EXISTS src_fdw;
-- IMPORT FOREIGN SCHEMA public FROM SERVER logistics_source INTO src_fdw;
--
-- Then copy with explicit casts (a failed cast points at the bad column):
-- INSERT INTO src.customers (customer_id, customer_name, customer_type, credit_terms_days, primary_freight_type, account_status, contract_start_date, annual_revenue_potential)
-- SELECT
--        customer_id::text,
--        customer_name::text,
--        customer_type::text,
--        credit_terms_days::integer,
--        primary_freight_type::text,
--        account_status::text,
--        contract_start_date::date,
--        annual_revenue_potential::numeric
-- FROM src_fdw.customers;
--
-- INSERT INTO src.drivers (driver_id, first_name, last_name, hire_date, termination_date, employment_status, home_terminal)
-- SELECT
--        driver_id::text,
--        first_name::text,
--        last_name::text,
--        hire_date::date,
--        termination_date::date,
--        employment_status::text,
--        home_terminal::text
-- FROM src_fdw.drivers;
--
-- INSERT INTO src.trucks (truck_id, model_year, make, status, home_terminal, fuel_type)
-- SELECT
--        truck_id::text,
--        model_year::integer,
--        make::text,
--        status::text,
--        home_terminal::text,
--        fuel_type::text
-- FROM src_fdw.trucks;
--
-- INSERT INTO src.trailers (trailer_id, trailer_type)
-- SELECT
--        trailer_id::text,
--        trailer_type::text
-- FROM src_fdw.trailers;
--
-- INSERT INTO src.facilities (facility_id, facility_name, city, state, latitude, longitude)
-- SELECT
--        facility_id::text,
--        facility_name::text,
--        city::text,
--        state::text,
--        latitude::numeric,
--        longitude::numeric
-- FROM src_fdw.facilities;
--
-- INSERT INTO src.routes (route_id, origin_city, destination_city, typical_distance_miles, base_rate_per_mile)
-- SELECT
--        route_id::text,
--        origin_city::text,
--        destination_city::text,
--        typical_distance_miles::numeric,
--        base_rate_per_mile::numeric
-- FROM src_fdw.routes;
--
-- INSERT INTO src.loads (load_id, customer_id, route_id, load_date, booking_type, load_type, load_status, revenue)
-- SELECT
--        load_id::text,
--        customer_id::text,
--        route_id::text,
--        load_date::date,
--        booking_type::text,
--        load_type::text,
--        load_status::text,
--        revenue::numeric
-- FROM src_fdw.loads;
--
-- INSERT INTO src.trips (trip_id, load_id, driver_id, truck_id, trailer_id, actual_distance_miles, actual_duration_hours, fuel_gallons_used, idle_time_hours)
-- SELECT
--        trip_id::text,
--        load_id::text,
--        driver_id::text,
--        truck_id::text,
--        trailer_id::text,
--        actual_distance_miles::numeric,
--        actual_duration_hours::numeric,
--        fuel_gallons_used::numeric,
--        idle_time_hours::numeric
-- FROM src_fdw.trips;
--
-- INSERT INTO src.fuel_purchases (fuel_purchase_id, trip_id, truck_id, driver_id, purchase_date, location_state, gallons, price_per_gallon, total_cost)
-- SELECT
--        fuel_purchase_id::text,
--        trip_id::text,
--        truck_id::text,
--        driver_id::text,
--        purchase_date::date,
--        location_state::text,
--        gallons::numeric,
--        price_per_gallon::numeric,
--        total_cost::numeric
-- FROM src_fdw.fuel_purchases;
--
-- INSERT INTO src.maintenance_record (maintenance_id, truck_id, maintenance_date, maintenance_type, labor_cost, labor_hours, parts_cost, total_cost, downtime_hours, facility_location)
-- SELECT
--        maintenance_id::text,
--        truck_id::text,
--        maintenance_date::date,
--        maintenance_type::text,
--        labor_cost::numeric,
--        labor_hours::numeric,
--        parts_cost::numeric,
--        total_cost::numeric,
--        downtime_hours::numeric,
--        facility_location::text
-- FROM src_fdw.maintenance_record;
--
-- INSERT INTO src.delivery_events (event_id, trip_id, facility_id, event_type, scheduled_datetime, actual_datetime, detention_minutes, on_time_flag)
-- SELECT
--        event_id::text,
--        trip_id::text,
--        facility_id::text,
--        event_type::text,
--        scheduled_datetime::timestamp,
--        actual_datetime::timestamp,
--        detention_minutes::numeric,
--        on_time_flag::boolean
-- FROM src_fdw.delivery_events;
--
-- INSERT INTO src.safety_incidents (incident_id, trip_id, driver_id, truck_id, incident_date, incident_type, at_fault_flag, preventable_flag, injury_flag, claim_amount, vehicle_damage_cost, cargo_damage_cost)
-- SELECT
--        incident_id::text,
--        trip_id::text,
--        driver_id::text,
--        truck_id::text,
--        incident_date::date,
--        incident_type::text,
--        at_fault_flag::boolean,
--        preventable_flag::boolean,
--        injury_flag::boolean,
--        claim_amount::numeric,
--        vehicle_damage_cost::numeric,
--        cargo_damage_cost::numeric
-- FROM src_fdw.safety_incidents;
--
-- INSERT INTO src.driver_monthly_metrics (driver_id, month, trips_completed, total_miles, on_time_delivery_rate)
-- SELECT
--        driver_id::text,
--        month::date,
--        trips_completed::integer,
--        total_miles::numeric,
--        on_time_delivery_rate::numeric
-- FROM src_fdw.driver_monthly_metrics;
--
-- INSERT INTO src.truck_utilization_metrics (truck_id, month, average_mpg, downtime_hours, maintenance_events, maintenance_cost, total_miles, total_revenue, utilization_rate)
-- SELECT
--        truck_id::text,
--        month::date,
--        average_mpg::numeric,
--        downtime_hours::numeric,
--        maintenance_events::integer,
--        maintenance_cost::numeric,
--        total_miles::numeric,
--        total_revenue::numeric,
--        utilization_rate::numeric
-- FROM src_fdw.truck_utilization_metrics;
--

-- =====================================================================
-- C. EXTRACTION QUERIES FOR ANY SOURCE SYSTEM
-- =====================================================================
-- Replace SOURCE_SCHEMA and the source table names. Each query renames and types the columns to match src.
-- Dialect notes: SQL Server uses VARCHAR/DECIMAL/BIT and no TRUE/FALSE keywords (use 1 and 0);
--                MySQL uses CHAR/DECIMAL/TINYINT(1). Everything else is ANSI.

-- Extract: customers
SELECT
    CAST(customer_id AS VARCHAR(100)) AS customer_id,
    CAST(customer_name AS VARCHAR(100)) AS customer_name,
    CAST(customer_type AS VARCHAR(100)) AS customer_type,
    CAST(credit_terms_days AS INTEGER) AS credit_terms_days,
    CAST(primary_freight_type AS VARCHAR(100)) AS primary_freight_type,
    CAST(account_status AS VARCHAR(100)) AS account_status,
    CAST(contract_start_date AS DATE) AS contract_start_date,
    CAST(annual_revenue_potential AS DECIMAL(18,4)) AS annual_revenue_potential
FROM SOURCE_SCHEMA.customers;

-- Extract: drivers
SELECT
    CAST(driver_id AS VARCHAR(100)) AS driver_id,
    CAST(first_name AS VARCHAR(100)) AS first_name,
    CAST(last_name AS VARCHAR(100)) AS last_name,
    CAST(hire_date AS DATE) AS hire_date,
    CAST(termination_date AS DATE) AS termination_date,
    CAST(employment_status AS VARCHAR(100)) AS employment_status,
    CAST(home_terminal AS VARCHAR(100)) AS home_terminal
FROM SOURCE_SCHEMA.drivers;

-- Extract: trucks
SELECT
    CAST(truck_id AS VARCHAR(100)) AS truck_id,
    CAST(model_year AS INTEGER) AS model_year,
    CAST(make AS VARCHAR(100)) AS make,
    CAST(status AS VARCHAR(100)) AS status,
    CAST(home_terminal AS VARCHAR(100)) AS home_terminal,
    CAST(fuel_type AS VARCHAR(100)) AS fuel_type
FROM SOURCE_SCHEMA.trucks;

-- Extract: trailers
SELECT
    CAST(trailer_id AS VARCHAR(100)) AS trailer_id,
    CAST(trailer_type AS VARCHAR(100)) AS trailer_type
FROM SOURCE_SCHEMA.trailers;

-- Extract: facilities
SELECT
    CAST(facility_id AS VARCHAR(100)) AS facility_id,
    CAST(facility_name AS VARCHAR(100)) AS facility_name,
    CAST(city AS VARCHAR(100)) AS city,
    CAST(state AS VARCHAR(100)) AS state,
    CAST(latitude AS DECIMAL(18,4)) AS latitude,
    CAST(longitude AS DECIMAL(18,4)) AS longitude
FROM SOURCE_SCHEMA.facilities;

-- Extract: routes
SELECT
    CAST(route_id AS VARCHAR(100)) AS route_id,
    CAST(origin_city AS VARCHAR(100)) AS origin_city,
    CAST(destination_city AS VARCHAR(100)) AS destination_city,
    CAST(typical_distance_miles AS DECIMAL(18,4)) AS typical_distance_miles,
    CAST(base_rate_per_mile AS DECIMAL(18,4)) AS base_rate_per_mile
FROM SOURCE_SCHEMA.routes;

-- Extract: loads
SELECT
    CAST(load_id AS VARCHAR(100)) AS load_id,
    CAST(customer_id AS VARCHAR(100)) AS customer_id,
    CAST(route_id AS VARCHAR(100)) AS route_id,
    CAST(load_date AS DATE) AS load_date,
    CAST(booking_type AS VARCHAR(100)) AS booking_type,
    CAST(load_type AS VARCHAR(100)) AS load_type,
    CAST(load_status AS VARCHAR(100)) AS load_status,
    CAST(revenue AS DECIMAL(18,4)) AS revenue
FROM SOURCE_SCHEMA.loads;

-- Extract: trips
SELECT
    CAST(trip_id AS VARCHAR(100)) AS trip_id,
    CAST(load_id AS VARCHAR(100)) AS load_id,
    CAST(driver_id AS VARCHAR(100)) AS driver_id,
    CAST(truck_id AS VARCHAR(100)) AS truck_id,
    CAST(trailer_id AS VARCHAR(100)) AS trailer_id,
    CAST(actual_distance_miles AS DECIMAL(18,4)) AS actual_distance_miles,
    CAST(actual_duration_hours AS DECIMAL(18,4)) AS actual_duration_hours,
    CAST(fuel_gallons_used AS DECIMAL(18,4)) AS fuel_gallons_used,
    CAST(idle_time_hours AS DECIMAL(18,4)) AS idle_time_hours
FROM SOURCE_SCHEMA.trips;

-- Extract: fuel_purchases
SELECT
    CAST(fuel_purchase_id AS VARCHAR(100)) AS fuel_purchase_id,
    CAST(trip_id AS VARCHAR(100)) AS trip_id,
    CAST(truck_id AS VARCHAR(100)) AS truck_id,
    CAST(driver_id AS VARCHAR(100)) AS driver_id,
    CAST(purchase_date AS DATE) AS purchase_date,
    CAST(location_state AS VARCHAR(100)) AS location_state,
    CAST(gallons AS DECIMAL(18,4)) AS gallons,
    CAST(price_per_gallon AS DECIMAL(18,4)) AS price_per_gallon,
    CAST(total_cost AS DECIMAL(18,4)) AS total_cost
FROM SOURCE_SCHEMA.fuel_purchases;

-- Extract: maintenance_record
SELECT
    CAST(maintenance_id AS VARCHAR(100)) AS maintenance_id,
    CAST(truck_id AS VARCHAR(100)) AS truck_id,
    CAST(maintenance_date AS DATE) AS maintenance_date,
    CAST(maintenance_type AS VARCHAR(100)) AS maintenance_type,
    CAST(labor_cost AS DECIMAL(18,4)) AS labor_cost,
    CAST(labor_hours AS DECIMAL(18,4)) AS labor_hours,
    CAST(parts_cost AS DECIMAL(18,4)) AS parts_cost,
    CAST(total_cost AS DECIMAL(18,4)) AS total_cost,
    CAST(downtime_hours AS DECIMAL(18,4)) AS downtime_hours,
    CAST(facility_location AS VARCHAR(100)) AS facility_location
FROM SOURCE_SCHEMA.maintenance_record;

-- Extract: delivery_events
SELECT
    CAST(event_id AS VARCHAR(100)) AS event_id,
    CAST(trip_id AS VARCHAR(100)) AS trip_id,
    CAST(facility_id AS VARCHAR(100)) AS facility_id,
    CAST(event_type AS VARCHAR(100)) AS event_type,
    CAST(scheduled_datetime AS TIMESTAMP) AS scheduled_datetime,
    CAST(actual_datetime AS TIMESTAMP) AS actual_datetime,
    CAST(detention_minutes AS DECIMAL(18,4)) AS detention_minutes,
    CASE WHEN LOWER(CAST(on_time_flag AS VARCHAR(10))) IN ('1','true','t','y','yes') THEN TRUE
         WHEN LOWER(CAST(on_time_flag AS VARCHAR(10))) IN ('0','false','f','n','no') THEN FALSE END AS on_time_flag
FROM SOURCE_SCHEMA.delivery_events;

-- Extract: safety_incidents
SELECT
    CAST(incident_id AS VARCHAR(100)) AS incident_id,
    CAST(trip_id AS VARCHAR(100)) AS trip_id,
    CAST(driver_id AS VARCHAR(100)) AS driver_id,
    CAST(truck_id AS VARCHAR(100)) AS truck_id,
    CAST(incident_date AS DATE) AS incident_date,
    CAST(incident_type AS VARCHAR(100)) AS incident_type,
    CASE WHEN LOWER(CAST(at_fault_flag AS VARCHAR(10))) IN ('1','true','t','y','yes') THEN TRUE
         WHEN LOWER(CAST(at_fault_flag AS VARCHAR(10))) IN ('0','false','f','n','no') THEN FALSE END AS at_fault_flag,
    CASE WHEN LOWER(CAST(preventable_flag AS VARCHAR(10))) IN ('1','true','t','y','yes') THEN TRUE
         WHEN LOWER(CAST(preventable_flag AS VARCHAR(10))) IN ('0','false','f','n','no') THEN FALSE END AS preventable_flag,
    CASE WHEN LOWER(CAST(injury_flag AS VARCHAR(10))) IN ('1','true','t','y','yes') THEN TRUE
         WHEN LOWER(CAST(injury_flag AS VARCHAR(10))) IN ('0','false','f','n','no') THEN FALSE END AS injury_flag,
    CAST(claim_amount AS DECIMAL(18,4)) AS claim_amount,
    CAST(vehicle_damage_cost AS DECIMAL(18,4)) AS vehicle_damage_cost,
    CAST(cargo_damage_cost AS DECIMAL(18,4)) AS cargo_damage_cost
FROM SOURCE_SCHEMA.safety_incidents;

-- Extract: driver_monthly_metrics
SELECT
    CAST(driver_id AS VARCHAR(100)) AS driver_id,
    CAST(month AS DATE) AS month,
    CAST(trips_completed AS INTEGER) AS trips_completed,
    CAST(total_miles AS DECIMAL(18,4)) AS total_miles,
    CAST(on_time_delivery_rate AS DECIMAL(18,4)) AS on_time_delivery_rate
FROM SOURCE_SCHEMA.driver_monthly_metrics;

-- Extract: truck_utilization_metrics
SELECT
    CAST(truck_id AS VARCHAR(100)) AS truck_id,
    CAST(month AS DATE) AS month,
    CAST(average_mpg AS DECIMAL(18,4)) AS average_mpg,
    CAST(downtime_hours AS DECIMAL(18,4)) AS downtime_hours,
    CAST(maintenance_events AS INTEGER) AS maintenance_events,
    CAST(maintenance_cost AS DECIMAL(18,4)) AS maintenance_cost,
    CAST(total_miles AS DECIMAL(18,4)) AS total_miles,
    CAST(total_revenue AS DECIMAL(18,4)) AS total_revenue,
    CAST(utilization_rate AS DECIMAL(18,4)) AS utilization_rate
FROM SOURCE_SCHEMA.truck_utilization_metrics;

-- =====================================================================
-- D. PROFILING (run after loading; the measures assume these values)
-- =====================================================================
SELECT 'src.' || t AS table_name, n AS row_count FROM (
    SELECT 'customers' AS t, COUNT(*) AS n FROM src.customers
UNION ALL
    SELECT 'drivers' AS t, COUNT(*) AS n FROM src.drivers
UNION ALL
    SELECT 'trucks' AS t, COUNT(*) AS n FROM src.trucks
UNION ALL
    SELECT 'trailers' AS t, COUNT(*) AS n FROM src.trailers
UNION ALL
    SELECT 'facilities' AS t, COUNT(*) AS n FROM src.facilities
UNION ALL
    SELECT 'routes' AS t, COUNT(*) AS n FROM src.routes
UNION ALL
    SELECT 'loads' AS t, COUNT(*) AS n FROM src.loads
UNION ALL
    SELECT 'trips' AS t, COUNT(*) AS n FROM src.trips
UNION ALL
    SELECT 'fuel_purchases' AS t, COUNT(*) AS n FROM src.fuel_purchases
UNION ALL
    SELECT 'maintenance_record' AS t, COUNT(*) AS n FROM src.maintenance_record
UNION ALL
    SELECT 'delivery_events' AS t, COUNT(*) AS n FROM src.delivery_events
UNION ALL
    SELECT 'safety_incidents' AS t, COUNT(*) AS n FROM src.safety_incidents
UNION ALL
    SELECT 'driver_monthly_metrics' AS t, COUNT(*) AS n FROM src.driver_monthly_metrics
UNION ALL
    SELECT 'truck_utilization_metrics' AS t, COUNT(*) AS n FROM src.truck_utilization_metrics
) x ORDER BY 1;

-- Value checks behind the assumptions
SELECT load_status, COUNT(*) FROM src.loads GROUP BY 1 ORDER BY 2 DESC;            -- expects Delivered, Cancelled
SELECT event_type, on_time_flag, COUNT(*) FROM src.delivery_events GROUP BY 1, 2;  -- expects Delivery
SELECT status, COUNT(*) FROM src.trucks GROUP BY 1;                                -- expects Active
SELECT maintenance_type, COUNT(*) FROM src.maintenance_record GROUP BY 1 ORDER BY 2 DESC;
SELECT account_status, COUNT(*) FROM src.customers GROUP BY 1;                     -- often a single value
SELECT MIN(load_date) AS first_load, MAX(load_date) AS last_load FROM src.loads;   -- drives the Date table

-- Keys that will not join (orphans)
SELECT 'loads without customer' AS check_name, COUNT(*) FROM src.loads l LEFT JOIN src.customers c USING (customer_id) WHERE c.customer_id IS NULL
UNION ALL SELECT 'loads without route', COUNT(*) FROM src.loads l LEFT JOIN src.routes r USING (route_id) WHERE r.route_id IS NULL
UNION ALL SELECT 'trips without load', COUNT(*) FROM src.trips t LEFT JOIN src.loads l USING (load_id) WHERE l.load_id IS NULL
UNION ALL SELECT 'trips without driver', COUNT(*) FROM src.trips t LEFT JOIN src.drivers d USING (driver_id) WHERE d.driver_id IS NULL
UNION ALL SELECT 'trips without truck', COUNT(*) FROM src.trips t LEFT JOIN src.trucks k USING (truck_id) WHERE k.truck_id IS NULL
UNION ALL SELECT 'fuel rows without trip', COUNT(*) FROM src.fuel_purchases WHERE trip_id IS NULL
UNION ALL SELECT 'delivery rows without trip', COUNT(*) FROM src.delivery_events WHERE trip_id IS NULL
UNION ALL SELECT 'safety rows without trip', COUNT(*) FROM src.safety_incidents WHERE trip_id IS NULL;
