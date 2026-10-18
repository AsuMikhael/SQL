-- ================================================================================================
-- 05  PARAMETERS AND HELPER FUNCTIONS (schema bi)
-- ================================================================================================
-- bi.sdiv        DAX DIVIDE: NULL instead of an error when the divisor is 0 or NULL.
-- bi.param       the value measure of a what-if parameter (selected value, or the default).
-- dw.data_as_of  latest load date (the DAX measure Data As Of).
-- bi.f_*         score, status and colour measures (Driver Score, Service Status, ABC Class, colours).
-- ================================================================================================

CREATE OR REPLACE FUNCTION bi.sdiv(a numeric, b numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN b IS NULL OR b = 0 THEN NULL ELSE a / b END
$$;

-- Measure: Data As Of
CREATE OR REPLACE FUNCTION dw.data_as_of() RETURNS date
LANGUAGE sql STABLE AS $$
    SELECT MAX(load_date) FROM src.loads
$$;

-- ---------------------------------------------------------------------
-- What-if parameters (the 11 parameter tables of the report)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bi.parameter (
    parameter_name  text PRIMARY KEY,
    min_value       numeric,
    max_value       numeric,
    step_value      numeric,
    default_value   numeric,
    value_measure   text,
    used_on         text
);
CREATE TABLE IF NOT EXISTS bi.parameter_selection (
    parameter_name  text PRIMARY KEY REFERENCES bi.parameter (parameter_name),
    selected_value  numeric               -- NULL means use the default
);

INSERT INTO bi.parameter (parameter_name, min_value, max_value, step_value, default_value, value_measure, used_on) VALUES
    ('on_time_target', 0.8, 1.0, 0.01, 0.95, 'On-Time Target Value', 'Executive, Operations'),
    ('utilization_target', 0.5, 1.0, 0.01, 0.8, 'Utilization Target Value', 'Executive'),
    ('driver_pay_per_mile', 0.3, 1.0, 0.05, 0.6, 'Driver Pay per Mile Value', 'Full-cost view'),
    ('detention_rate_per_hour', 25, 150, 5, 75, 'Detention Rate Value', 'Operations'),
    ('idle_burn_gal_per_hour', 0.4, 1.2, 0.1, 0.8, 'Idle Burn Value', 'Fuel & Safety'),
    ('target_mpg', 5, 9, 0.1, 6.5, 'Target MPG Value', 'Drivers, Fuel & Safety'),
    ('fuel_price_change', -0.2, 0.3, 0.01, 0, 'Fuel Price Change Value', 'Fuel & Safety, Routes'),
    ('rate_change', -0.1, 0.2, 0.01, 0, 'Rate Change Value', 'Routes'),
    ('top_n', 3, 25, 1, 10, 'Top N Value', 'Several pages'),
    ('service_interval_days', 30, 180, 15, 90, 'Service Interval Value', 'Fleet'),
    ('churn_days', 30, 180, 15, 90, 'Churn Days Value', 'Customers')
ON CONFLICT (parameter_name) DO NOTHING;

INSERT INTO bi.parameter_selection (parameter_name)
SELECT parameter_name FROM bi.parameter
ON CONFLICT (parameter_name) DO NOTHING;

-- Value measure: <Parameter> Value = SELECTEDVALUE(<table>[<column>], default)
CREATE OR REPLACE FUNCTION bi.param(p_name text) RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT selected_value FROM bi.parameter_selection WHERE parameter_name = p_name),
        (SELECT default_value  FROM bi.parameter           WHERE parameter_name = p_name))
$$;

-- The slicer lists (GENERATESERIES tables)
CREATE OR REPLACE VIEW bi.v_parameter_series AS
SELECT p.parameter_name, s.value
FROM bi.parameter p
CROSS JOIN LATERAL generate_series(p.min_value, p.max_value, p.step_value) AS s(value);

-- All parameter value measures on one row
CREATE OR REPLACE VIEW bi.v_parameter_values AS
SELECT
    bi.param('on_time_target') AS on_time_target_value,
    bi.param('utilization_target') AS utilization_target_value,
    bi.param('driver_pay_per_mile') AS driver_pay_per_mile_value,
    bi.param('detention_rate_per_hour') AS detention_rate_value,
    bi.param('idle_burn_gal_per_hour') AS idle_burn_value,
    bi.param('target_mpg') AS target_mpg_value,
    bi.param('fuel_price_change') AS fuel_price_change_value,
    bi.param('rate_change') AS rate_change_value,
    bi.param('top_n') AS top_n_value,
    bi.param('service_interval_days') AS service_interval_value,
    bi.param('churn_days') AS churn_days_value;

-- Example: set the Target MPG slicer to 7.0, then clear it
--   UPDATE bi.parameter_selection SET selected_value = 7.0  WHERE parameter_name = 'target_mpg';
--   UPDATE bi.parameter_selection SET selected_value = NULL WHERE parameter_name = 'target_mpg';

-- ---------------------------------------------------------------------
-- Score, status and colour measures
-- ---------------------------------------------------------------------
-- Measure: On-Time Status Color
CREATE OR REPLACE FUNCTION bi.f_color_on_time(r numeric) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN r IS NULL THEN '#BDBDBD'
                WHEN r >= bi.param('on_time_target') THEN '#2E7D32'
                WHEN r >= bi.param('on_time_target') - 0.05 THEN '#F9A825'
                ELSE '#C62828' END
$$;

-- Measure: Utilization Status Color
CREATE OR REPLACE FUNCTION bi.f_color_utilization(r numeric) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN r IS NULL THEN '#BDBDBD'
                WHEN r >= bi.param('utilization_target') THEN '#2E7D32'
                WHEN r >= bi.param('utilization_target') - 0.1 THEN '#F9A825'
                ELSE '#C62828' END
$$;

-- Measure: Customer Service Score (60% on-time, 20% completion, 20% no detention)
CREATE OR REPLACE FUNCTION bi.f_service_score(on_time numeric, cancel_rate numeric, detained_pct numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
    SELECT 100 * ( 0.6 * COALESCE(on_time, 0)
                 + 0.2 * ( 1 - COALESCE(cancel_rate, 0) )
                 + 0.2 * ( 1 - LEAST(1, COALESCE(detained_pct, 0)) ) )
$$;

-- Measure: Driver Score (40% on-time, 25% fuel vs target, 15% idle, 20% safety)
CREATE OR REPLACE FUNCTION bi.f_driver_score(on_time numeric, mpg numeric, idle numeric, incidents_per_1m numeric) RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN on_time IS NULL OR mpg IS NULL THEN NULL
        ELSE 100 * ( 0.40 * on_time
                   + 0.25 * LEAST(1, mpg / bi.param('target_mpg'))
                   + 0.15 * COALESCE(1 - LEAST(1, idle / 0.25), 1)
                   + 0.20 * ( 1 - LEAST(1, COALESCE(incidents_per_1m / 10, 0)) ) ) END
$$;

-- Measure: Driver Bucket
CREATE OR REPLACE FUNCTION bi.f_driver_bucket(score numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN score IS NULL THEN NULL WHEN score >= 85 THEN 'Elite'
                WHEN score >= 70 THEN 'Solid' WHEN score >= 55 THEN 'Coach' ELSE 'At risk' END
$$;

-- Measure: Driver Score Color (relative to the fleet score, bands of 2 points)
CREATE OR REPLACE FUNCTION bi.f_color_driver_score(score numeric, fleet_score numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN score IS NULL THEN '#BDBDBD'
                WHEN score >= fleet_score + 2 THEN '#2E7D32'
                WHEN score >= fleet_score THEN '#9CCC65'
                WHEN score >= fleet_score - 2 THEN '#F9A825'
                ELSE '#C62828' END
$$;

-- Measures: Service Status and Service Status Color
CREATE OR REPLACE FUNCTION bi.f_service_status(days integer) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN days IS NULL THEN 'No history'
                WHEN days > bi.param('service_interval_days') THEN 'Overdue'
                WHEN days > bi.param('service_interval_days') * 0.8 THEN 'Due soon'
                ELSE 'OK' END
$$;
CREATE OR REPLACE FUNCTION bi.f_color_service_status(status text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE status WHEN 'Overdue' THEN '#C62828' WHEN 'Due soon' THEN '#F9A825'
                       WHEN 'OK' THEN '#2E7D32' ELSE '#BDBDBD' END
$$;

-- Measure: Cost per Mile Color (maintenance cost per mile against the fleet)
CREATE OR REPLACE FUNCTION bi.f_color_cost_per_mile(v numeric, fleet numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN v IS NULL THEN '#BDBDBD' WHEN v > fleet * 1.25 THEN '#C62828'
                WHEN v > fleet THEN '#F9A825' ELSE '#2E7D32' END
$$;

-- Measure: Price Variance Color (state price minus fleet price, in dollars)
CREATE OR REPLACE FUNCTION bi.f_color_price_variance(v numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN v IS NULL THEN '#BDBDBD' WHEN v > 0.003 THEN '#C62828'
                WHEN v > 0 THEN '#F9A825' ELSE '#2E7D32' END
$$;

-- Measures: ABC Class and ABC Color
CREATE OR REPLACE FUNCTION bi.f_abc_class(cum_share numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN cum_share <= 0.8 THEN 'A' WHEN cum_share <= 0.95 THEN 'B' ELSE 'C' END
$$;
CREATE OR REPLACE FUNCTION bi.f_color_abc(class text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE class WHEN 'A' THEN '#1F4E79' WHEN 'B' THEN '#2E86AB' WHEN 'C' THEN '#9AA5B1' ELSE '#BDBDBD' END
$$;

-- Measures: Churn Status and Churn Status Color
CREATE OR REPLACE FUNCTION bi.f_churn_status(days integer) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN days IS NULL THEN 'No loads'
                WHEN days > bi.param('churn_days') THEN 'At risk'
                WHEN days > bi.param('churn_days') * 0.7 THEN 'Watch'
                ELSE 'Active' END
$$;
CREATE OR REPLACE FUNCTION bi.f_color_churn(status text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE status WHEN 'At risk' THEN '#C62828' WHEN 'Watch' THEN '#F9A825'
                       WHEN 'Active' THEN '#2E7D32' ELSE '#BDBDBD' END
$$;

-- Measures: Route Profit Tier and Route Tier Color (gap to the fleet margin)
CREATE OR REPLACE FUNCTION bi.f_route_tier(gap numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN gap IS NULL THEN 'No data' WHEN gap >= 0.02 THEN 'Above fleet'
                WHEN gap >= -0.02 THEN 'In line' ELSE 'Below fleet' END
$$;
CREATE OR REPLACE FUNCTION bi.f_color_route_tier(tier text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE tier WHEN 'Above fleet' THEN '#2E7D32' WHEN 'In line' THEN '#F9A825'
                     WHEN 'Below fleet' THEN '#C62828' ELSE '#BDBDBD' END
$$;
