-- ================================================================================================
-- 01  SCHEMAS AND SOURCE TABLES
-- ================================================================================================
-- Logistics Operation Database: PostgreSQL 13 or later.
--
-- Three schemas:
--   src  landing tables, one per source file or source-system table (the 'old' tables).
--   dw   the star schema (conformed dimensions and fact tables) built from src by dw.load_star().
--   bi   parameters, helper functions, measure functions, reporting views and checks.
--
-- Run order: 01, 02 (load data), 03, 04 (CALL dw.load_star()), 05, 06, 07, 08, 09. See run_all.sql.
-- Column names marked (a) in the docs are assumed from the standard logistics schema:
-- adjust the column lists to match your files before loading.
-- ================================================================================================

CREATE SCHEMA IF NOT EXISTS src;
CREATE SCHEMA IF NOT EXISTS dw;
CREATE SCHEMA IF NOT EXISTS bi;

-- Customer master (200 rows in the reference data). account_status held a single value (Active).
CREATE TABLE IF NOT EXISTS src.customers (
    customer_id                text PRIMARY KEY,
    customer_name              text,
    customer_type              text,
    credit_terms_days          integer,
    primary_freight_type       text,
    account_status             text,
    contract_start_date        date,
    annual_revenue_potential   numeric
);

-- Driver master. Includes the placeholder driver DRV_UNKNOWN (about 2% of revenue).
CREATE TABLE IF NOT EXISTS src.drivers (
    driver_id                  text PRIMARY KEY,
    first_name                 text,
    last_name                  text,
    hire_date                  date,
    termination_date           date,
    employment_status          text,
    home_terminal              text
);

-- Truck master. Some model_year values are blank.
CREATE TABLE IF NOT EXISTS src.trucks (
    truck_id                   text PRIMARY KEY,
    model_year                 integer,
    make                       text,
    status                     text,
    home_terminal              text,
    fuel_type                  text
);

-- Trailer master.
CREATE TABLE IF NOT EXISTS src.trailers (
    trailer_id                 text PRIMARY KEY,
    trailer_type               text
);

-- Delivery facilities with coordinates.
CREATE TABLE IF NOT EXISTS src.facilities (
    facility_id                text PRIMARY KEY,
    facility_name              text,
    city                       text,
    state                      text,
    latitude                   numeric,
    longitude                  numeric
);

-- Origin to destination routes with typical distance and base rate per mile.
CREATE TABLE IF NOT EXISTS src.routes (
    route_id                   text PRIMARY KEY,
    origin_city                text,
    destination_city           text,
    typical_distance_miles     numeric,
    base_rate_per_mile         numeric
);

-- One row per load (booking). revenue is the load revenue.
CREATE TABLE IF NOT EXISTS src.loads (
    load_id                    text PRIMARY KEY,
    customer_id                text,
    route_id                   text,
    load_date                  date,
    booking_type               text,
    load_type                  text,
    load_status                text,
    revenue                    numeric
);

-- One row per trip; one-to-one with loads.
CREATE TABLE IF NOT EXISTS src.trips (
    trip_id                    text PRIMARY KEY,
    load_id                    text,
    driver_id                  text,
    truck_id                   text,
    trailer_id                 text,
    actual_distance_miles      numeric,
    actual_duration_hours      numeric,
    fuel_gallons_used          numeric,
    idle_time_hours            numeric
);

-- Fuel purchases linked to trips. Some rows have no state.
CREATE TABLE IF NOT EXISTS src.fuel_purchases (
    fuel_purchase_id           text,
    trip_id                    text,
    truck_id                   text,
    driver_id                  text,
    purchase_date              date,
    location_state             text,
    gallons                    numeric,
    price_per_gallon           numeric,
    total_cost                 numeric
);

-- Maintenance events per truck (links to trucks only).
CREATE TABLE IF NOT EXISTS src.maintenance_record (
    maintenance_id             text PRIMARY KEY,
    truck_id                   text,
    maintenance_date           date,
    maintenance_type           text,
    labor_cost                 numeric,
    labor_hours                numeric,
    parts_cost                 numeric,
    total_cost                 numeric,
    downtime_hours             numeric,
    facility_location          text
);

-- Pickup and delivery events with detention and on-time flag.
CREATE TABLE IF NOT EXISTS src.delivery_events (
    event_id                   text,
    trip_id                    text,
    facility_id                text,
    event_type                 text,
    scheduled_datetime         timestamp,
    actual_datetime            timestamp,
    detention_minutes          numeric,
    on_time_flag               boolean
);

-- Safety incidents linked to trips.
CREATE TABLE IF NOT EXISTS src.safety_incidents (
    incident_id                text,
    trip_id                    text,
    driver_id                  text,
    truck_id                   text,
    incident_date              date,
    incident_type              text,
    at_fault_flag              boolean,
    preventable_flag           boolean,
    injury_flag                boolean,
    claim_amount               numeric,
    vehicle_damage_cost        numeric,
    cargo_damage_cost          numeric
);

-- Pre-computed monthly metrics per driver.
CREATE TABLE IF NOT EXISTS src.driver_monthly_metrics (
    driver_id                  text,
    month                      date,
    trips_completed            integer,
    total_miles                numeric,
    on_time_delivery_rate      numeric
);

-- Pre-computed monthly metrics per truck.
CREATE TABLE IF NOT EXISTS src.truck_utilization_metrics (
    truck_id                   text,
    month                      date,
    average_mpg                numeric,
    downtime_hours             numeric,
    maintenance_events         integer,
    maintenance_cost           numeric,
    total_miles                numeric,
    total_revenue              numeric,
    utilization_rate           numeric
);

-- Indexes on the landing tables (they speed up the star build)
CREATE INDEX IF NOT EXISTS ix_loads_customer_id ON src.loads (customer_id);
CREATE INDEX IF NOT EXISTS ix_loads_route_id ON src.loads (route_id);
CREATE INDEX IF NOT EXISTS ix_loads_load_date ON src.loads (load_date);
CREATE INDEX IF NOT EXISTS ix_trips_load_id ON src.trips (load_id);
CREATE INDEX IF NOT EXISTS ix_trips_driver_id ON src.trips (driver_id);
CREATE INDEX IF NOT EXISTS ix_trips_truck_id ON src.trips (truck_id);
CREATE INDEX IF NOT EXISTS ix_trips_trailer_id ON src.trips (trailer_id);
CREATE INDEX IF NOT EXISTS ix_fuel_purchases_trip_id ON src.fuel_purchases (trip_id);
CREATE INDEX IF NOT EXISTS ix_delivery_events_trip_id ON src.delivery_events (trip_id);
CREATE INDEX IF NOT EXISTS ix_delivery_events_facility_id ON src.delivery_events (facility_id);
CREATE INDEX IF NOT EXISTS ix_safety_incidents_trip_id ON src.safety_incidents (trip_id);
CREATE INDEX IF NOT EXISTS ix_maintenance_record_truck_id ON src.maintenance_record (truck_id);
CREATE INDEX IF NOT EXISTS ix_maintenance_record_maintenance_date ON src.maintenance_record (maintenance_date);
CREATE INDEX IF NOT EXISTS ix_driver_monthly_metrics_driver_id ON src.driver_monthly_metrics (driver_id);
CREATE INDEX IF NOT EXISTS ix_truck_utilization_metrics_truck_id ON src.truck_utilization_metrics (truck_id);
