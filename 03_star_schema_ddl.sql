-- ================================================================================================
-- 03  STAR SCHEMA DDL (schema dw)
-- ================================================================================================
-- Galaxy (fact constellation) schema: conformed dimensions shared by several fact tables.
--   Dimensions: dim_date, dim_customer, dim_route, dim_driver, dim_truck, dim_trailer, dim_facility,
--               dim_network_city, dim_margin_bridge (helper tables are unrelated by design).
--   Facts: fact_load_trip (load grain, trip folded in), fact_fuel_purchase, fact_delivery_event,
--          fact_safety_incident, fact_maintenance_event, fact_truck_month, fact_driver_month.
-- Child facts carry the conformed keys of their load (date, customer, route, driver, truck),
-- so every dimension filters every fact directly and no snowflake joins are needed.
-- Natural keys from the source are kept as keys. Foreign keys are optional: see optional_foreign_keys.sql.
-- ================================================================================================

-- One row per calendar day, covering every full year in loads
CREATE TABLE IF NOT EXISTS dw.dim_date (
    full_date                  date PRIMARY KEY,
    year                       integer,
    quarter                    text,
    month_number               integer,
    month_name                 text,
    month_year                 text,
    year_month_sort            integer,
    year_month                 text,
    day_name                   text,
    day_number                 integer,
    month_start                date
);
COMMENT ON TABLE dw.dim_date IS 'One row per calendar day, covering every full year in loads';

-- One row per customer
CREATE TABLE IF NOT EXISTS dw.dim_customer (
    customer_id                text PRIMARY KEY,
    customer_name              text,
    customer_type              text,
    credit_terms_days          integer,
    primary_freight_type       text,
    account_status             text,
    contract_start_date        date,
    annual_revenue_potential   numeric
);
COMMENT ON TABLE dw.dim_customer IS 'One row per customer';

-- One row per route
CREATE TABLE IF NOT EXISTS dw.dim_route (
    route_id                   text PRIMARY KEY,
    origin_city                text,
    destination_city           text,
    route_name                 text,
    typical_distance_miles     numeric,
    base_rate_per_mile         numeric
);
COMMENT ON TABLE dw.dim_route IS 'One row per route';

-- One row per driver (includes the placeholder DRV_UNKNOWN)
CREATE TABLE IF NOT EXISTS dw.dim_driver (
    driver_id                  text PRIMARY KEY,
    first_name                 text,
    last_name                  text,
    driver_name                text,
    hire_date                  date,
    termination_date           date,
    employment_status          text,
    home_terminal              text,
    tenure_years               numeric,
    tenure_band                text,
    tenure_band_sort           integer
);
COMMENT ON TABLE dw.dim_driver IS 'One row per driver (includes the placeholder DRV_UNKNOWN)';

-- One row per truck
CREATE TABLE IF NOT EXISTS dw.dim_truck (
    truck_id                   text PRIMARY KEY,
    make                       text,
    model_year                 integer,
    status                     text,
    home_terminal              text,
    fuel_type                  text,
    truck_age                  integer,
    truck_age_band             text
);
COMMENT ON TABLE dw.dim_truck IS 'One row per truck';

-- One row per trailer
CREATE TABLE IF NOT EXISTS dw.dim_trailer (
    trailer_id                 text PRIMARY KEY,
    trailer_type               text
);
COMMENT ON TABLE dw.dim_trailer IS 'One row per trailer';

-- One row per delivery facility
CREATE TABLE IF NOT EXISTS dw.dim_facility (
    facility_id                text PRIMARY KEY,
    facility_name              text,
    city                       text,
    state                      text,
    latitude                   numeric,
    longitude                  numeric
);
COMMENT ON TABLE dw.dim_facility IS 'One row per delivery facility';

-- One row per city that appears as an origin or a destination
CREATE TABLE IF NOT EXISTS dw.dim_network_city (
    city                       text PRIMARY KEY
);
COMMENT ON TABLE dw.dim_network_city IS 'One row per city that appears as an origin or a destination';

-- Fixed rows for the margin waterfall
CREATE TABLE IF NOT EXISTS dw.dim_margin_bridge (
    item                       text PRIMARY KEY,
    sort_order                 integer
);
COMMENT ON TABLE dw.dim_margin_bridge IS 'Fixed rows for the margin waterfall';

-- One row per calendar month
CREATE TABLE IF NOT EXISTS dw.month_maint_ratio (
    month_start                date PRIMARY KEY,
    maintenance_cost           numeric,
    miles                      numeric,
    maint_cost_per_mile        numeric
);
COMMENT ON TABLE dw.month_maint_ratio IS 'One row per calendar month';

-- One row per load; the trip, when there is one, is folded into the same row
CREATE TABLE IF NOT EXISTS dw.fact_load_trip (
    load_id                    text PRIMARY KEY,
    load_date                  date,
    customer_id                text,
    route_id                   text,
    origin_city                text,
    destination_city           text,
    booking_type               text,
    load_type                  text,
    load_status                text,
    revenue                    numeric,
    expected_linehaul_revenue  numeric,
    trip_id                    text,
    driver_id                  text,
    truck_id                   text,
    trailer_id                 text,
    miles                      numeric,
    expected_miles             numeric,
    duration_hours             numeric,
    fuel_gallons_used          numeric,
    idle_hours                 numeric,
    fuel_cost                  numeric,
    fuel_gallons_purchased     numeric,
    maint_alloc                numeric,
    gross_profit               numeric
);
COMMENT ON TABLE dw.fact_load_trip IS 'One row per load; the trip, when there is one, is folded into the same row';

-- One row per fuel purchase
CREATE TABLE IF NOT EXISTS dw.fact_fuel_purchase (
    fuel_key                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fuel_purchase_id           text,
    trip_id                    text,
    purchase_date              date,
    location_state             text,
    gallons                    numeric,
    price_per_gallon           numeric,
    total_cost                 numeric,
    load_id                    text,
    load_date                  date,
    customer_id                text,
    route_id                   text,
    origin_city                text,
    destination_city           text,
    booking_type               text,
    driver_id                  text,
    truck_id                   text
);
COMMENT ON TABLE dw.fact_fuel_purchase IS 'One row per fuel purchase';

-- One row per pickup or delivery event
CREATE TABLE IF NOT EXISTS dw.fact_delivery_event (
    event_key                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id                   text,
    trip_id                    text,
    facility_id                text,
    event_type                 text,
    scheduled_datetime         timestamp,
    actual_datetime            timestamp,
    detention_minutes          numeric,
    on_time_flag               boolean,
    is_delivery                boolean,
    detention_hours            numeric,
    detention_bucket           text,
    detention_bucket_sort      integer,
    load_id                    text,
    load_date                  date,
    customer_id                text,
    route_id                   text,
    origin_city                text,
    destination_city           text,
    booking_type               text,
    driver_id                  text,
    truck_id                   text
);
COMMENT ON TABLE dw.fact_delivery_event IS 'One row per pickup or delivery event';

-- One row per safety incident
CREATE TABLE IF NOT EXISTS dw.fact_safety_incident (
    incident_key               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    incident_id                text,
    trip_id                    text,
    incident_date              date,
    incident_type              text,
    at_fault_flag              boolean,
    preventable_flag           boolean,
    injury_flag                boolean,
    claim_amount               numeric,
    vehicle_damage_cost        numeric,
    cargo_damage_cost          numeric,
    load_id                    text,
    load_date                  date,
    customer_id                text,
    route_id                   text,
    origin_city                text,
    destination_city           text,
    booking_type               text,
    driver_id                  text,
    truck_id                   text
);
COMMENT ON TABLE dw.fact_safety_incident IS 'One row per safety incident';

-- One row per maintenance event; links to dim_truck only
CREATE TABLE IF NOT EXISTS dw.fact_maintenance_event (
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
COMMENT ON TABLE dw.fact_maintenance_event IS 'One row per maintenance event; links to dim_truck only';

-- One row per truck per month
CREATE TABLE IF NOT EXISTS dw.fact_truck_month (
    truck_month_key            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    truck_id                   text,
    month_start                date,
    average_mpg                numeric,
    downtime_hours             numeric,
    maintenance_events         integer,
    maintenance_cost           numeric,
    total_miles                numeric,
    total_revenue              numeric,
    utilization_rate           numeric
);
COMMENT ON TABLE dw.fact_truck_month IS 'One row per truck per month';

-- One row per driver per month
CREATE TABLE IF NOT EXISTS dw.fact_driver_month (
    driver_month_key           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id                  text,
    month_start                date,
    trips_completed            integer,
    total_miles                numeric,
    on_time_delivery_rate      numeric
);
COMMENT ON TABLE dw.fact_driver_month IS 'One row per driver per month';

-- Indexes for the filters the measure functions use
CREATE INDEX IF NOT EXISTS ix_fact_load_trip_load_date ON dw.fact_load_trip (load_date);
CREATE INDEX IF NOT EXISTS ix_fact_load_trip_customer_id ON dw.fact_load_trip (customer_id);
CREATE INDEX IF NOT EXISTS ix_fact_load_trip_route_id ON dw.fact_load_trip (route_id);
CREATE INDEX IF NOT EXISTS ix_fact_load_trip_driver_id ON dw.fact_load_trip (driver_id);
CREATE INDEX IF NOT EXISTS ix_fact_load_trip_truck_id ON dw.fact_load_trip (truck_id);
CREATE INDEX IF NOT EXISTS ix_fact_load_trip_trailer_id ON dw.fact_load_trip (trailer_id);
CREATE INDEX IF NOT EXISTS ix_fact_load_trip_booking_type ON dw.fact_load_trip (booking_type);
CREATE INDEX IF NOT EXISTS ix_fact_fuel_purchase_trip_id ON dw.fact_fuel_purchase (trip_id);
CREATE INDEX IF NOT EXISTS ix_fact_fuel_purchase_load_date ON dw.fact_fuel_purchase (load_date);
CREATE INDEX IF NOT EXISTS ix_fact_fuel_purchase_customer_id ON dw.fact_fuel_purchase (customer_id);
CREATE INDEX IF NOT EXISTS ix_fact_fuel_purchase_driver_id ON dw.fact_fuel_purchase (driver_id);
CREATE INDEX IF NOT EXISTS ix_fact_fuel_purchase_truck_id ON dw.fact_fuel_purchase (truck_id);
CREATE INDEX IF NOT EXISTS ix_fact_fuel_purchase_location_state ON dw.fact_fuel_purchase (location_state);
CREATE INDEX IF NOT EXISTS ix_fact_delivery_event_trip_id ON dw.fact_delivery_event (trip_id);
CREATE INDEX IF NOT EXISTS ix_fact_delivery_event_facility_id ON dw.fact_delivery_event (facility_id);
CREATE INDEX IF NOT EXISTS ix_fact_delivery_event_load_date ON dw.fact_delivery_event (load_date);
CREATE INDEX IF NOT EXISTS ix_fact_delivery_event_customer_id ON dw.fact_delivery_event (customer_id);
CREATE INDEX IF NOT EXISTS ix_fact_delivery_event_driver_id ON dw.fact_delivery_event (driver_id);
CREATE INDEX IF NOT EXISTS ix_fact_delivery_event_truck_id ON dw.fact_delivery_event (truck_id);
CREATE INDEX IF NOT EXISTS ix_fact_safety_incident_trip_id ON dw.fact_safety_incident (trip_id);
CREATE INDEX IF NOT EXISTS ix_fact_safety_incident_load_date ON dw.fact_safety_incident (load_date);
CREATE INDEX IF NOT EXISTS ix_fact_safety_incident_customer_id ON dw.fact_safety_incident (customer_id);
CREATE INDEX IF NOT EXISTS ix_fact_safety_incident_driver_id ON dw.fact_safety_incident (driver_id);
CREATE INDEX IF NOT EXISTS ix_fact_safety_incident_truck_id ON dw.fact_safety_incident (truck_id);
CREATE INDEX IF NOT EXISTS ix_fact_safety_incident_incident_type ON dw.fact_safety_incident (incident_type);
CREATE INDEX IF NOT EXISTS ix_fact_maintenance_event_truck_id ON dw.fact_maintenance_event (truck_id);
CREATE INDEX IF NOT EXISTS ix_fact_maintenance_event_maintenance_date ON dw.fact_maintenance_event (maintenance_date);
CREATE INDEX IF NOT EXISTS ix_fact_maintenance_event_maintenance_type ON dw.fact_maintenance_event (maintenance_type);
CREATE INDEX IF NOT EXISTS ix_fact_truck_month_truck_id ON dw.fact_truck_month (truck_id);
CREATE INDEX IF NOT EXISTS ix_fact_truck_month_month_start ON dw.fact_truck_month (month_start);
CREATE INDEX IF NOT EXISTS ix_fact_driver_month_driver_id ON dw.fact_driver_month (driver_id);
CREATE INDEX IF NOT EXISTS ix_fact_driver_month_month_start ON dw.fact_driver_month (month_start);
CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_load_trip_trip ON dw.fact_load_trip (trip_id) WHERE trip_id IS NOT NULL;
