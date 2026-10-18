-- ================================================================================================
-- 06  SCOPE FUNCTIONS: THE FILTER CONTEXT
-- ================================================================================================
-- Every measure function reads its rows through one of these functions. They play the role of slicers:
--   p_start, p_end   inclusive date range (NULL = no limit); dates are load dates, as in the report
--   p_customer, p_route, p_driver, p_truck, p_booking   NULL means All
-- Extra filters: p_facility (deliveries), p_incident_type (safety), p_state (fuel), p_type (maintenance).
-- Date filters reach the child facts through the load date; maintenance and the two monthly facts use
-- their own date. Customer and route never filter maintenance (it links to trucks only).
-- Example: SELECT * FROM bi.m_finance(p_start := '2024-01-01', p_end := '2024-12-31', p_customer := 'CUST00002');
-- ================================================================================================

-- Loads (and their trips) in scope.
CREATE OR REPLACE FUNCTION bi.fn_scope_load(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL)
RETURNS SETOF dw.fact_load_trip
LANGUAGE sql STABLE AS $$
    SELECT f.* FROM dw.fact_load_trip f
    WHERE (p_start IS NULL OR f.load_date >= p_start)
      AND (p_end IS NULL OR f.load_date <= p_end)
      AND (p_customer IS NULL OR f.customer_id = p_customer)
      AND (p_route IS NULL OR f.route_id = p_route)
      AND (p_driver IS NULL OR f.driver_id = p_driver)
      AND (p_truck IS NULL OR f.truck_id = p_truck)
      AND (p_booking IS NULL OR f.booking_type = p_booking)
$$;

-- Delivery events in scope.
CREATE OR REPLACE FUNCTION bi.fn_scope_delivery(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_facility text DEFAULT NULL)
RETURNS SETOF dw.fact_delivery_event
LANGUAGE sql STABLE AS $$
    SELECT f.* FROM dw.fact_delivery_event f
    WHERE (p_start IS NULL OR f.load_date >= p_start)
      AND (p_end IS NULL OR f.load_date <= p_end)
      AND (p_customer IS NULL OR f.customer_id = p_customer)
      AND (p_route IS NULL OR f.route_id = p_route)
      AND (p_driver IS NULL OR f.driver_id = p_driver)
      AND (p_truck IS NULL OR f.truck_id = p_truck)
      AND (p_booking IS NULL OR f.booking_type = p_booking)
      AND (p_facility IS NULL OR f.facility_id = p_facility)
$$;

-- Safety incidents in scope.
CREATE OR REPLACE FUNCTION bi.fn_scope_safety(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_incident_type text DEFAULT NULL)
RETURNS SETOF dw.fact_safety_incident
LANGUAGE sql STABLE AS $$
    SELECT f.* FROM dw.fact_safety_incident f
    WHERE (p_start IS NULL OR f.load_date >= p_start)
      AND (p_end IS NULL OR f.load_date <= p_end)
      AND (p_customer IS NULL OR f.customer_id = p_customer)
      AND (p_route IS NULL OR f.route_id = p_route)
      AND (p_driver IS NULL OR f.driver_id = p_driver)
      AND (p_truck IS NULL OR f.truck_id = p_truck)
      AND (p_booking IS NULL OR f.booking_type = p_booking)
      AND (p_incident_type IS NULL OR f.incident_type = p_incident_type)
$$;

-- Fuel purchases in scope.
CREATE OR REPLACE FUNCTION bi.fn_scope_fuel(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_customer text DEFAULT NULL, p_route text DEFAULT NULL, p_driver text DEFAULT NULL, p_truck text DEFAULT NULL, p_booking text DEFAULT NULL, p_state text DEFAULT NULL)
RETURNS SETOF dw.fact_fuel_purchase
LANGUAGE sql STABLE AS $$
    SELECT f.* FROM dw.fact_fuel_purchase f
    WHERE (p_start IS NULL OR f.load_date >= p_start)
      AND (p_end IS NULL OR f.load_date <= p_end)
      AND (p_customer IS NULL OR f.customer_id = p_customer)
      AND (p_route IS NULL OR f.route_id = p_route)
      AND (p_driver IS NULL OR f.driver_id = p_driver)
      AND (p_truck IS NULL OR f.truck_id = p_truck)
      AND (p_booking IS NULL OR f.booking_type = p_booking)
      AND (p_state IS NULL OR f.location_state = p_state)
$$;

-- Maintenance events in scope (date = maintenance_date; truck and type filters only).
CREATE OR REPLACE FUNCTION bi.fn_scope_maintenance(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_truck text DEFAULT NULL, p_type text DEFAULT NULL)
RETURNS SETOF dw.fact_maintenance_event
LANGUAGE sql STABLE AS $$
    SELECT f.* FROM dw.fact_maintenance_event f
    WHERE (p_start IS NULL OR f.maintenance_date >= p_start)
      AND (p_end IS NULL OR f.maintenance_date <= p_end)
      AND (p_truck IS NULL OR f.truck_id = p_truck)
      AND (p_type IS NULL OR f.maintenance_type = p_type)
$$;

-- Monthly truck utilization in scope (the month is included when it starts inside the range).
CREATE OR REPLACE FUNCTION bi.fn_scope_truck_month(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_truck text DEFAULT NULL)
RETURNS SETOF dw.fact_truck_month
LANGUAGE sql STABLE AS $$
    SELECT f.* FROM dw.fact_truck_month f
    WHERE (p_start IS NULL OR f.month_start >= DATE_TRUNC('month', p_start)::date)
      AND (p_end IS NULL OR f.month_start <= p_end)
      AND (p_truck IS NULL OR f.truck_id = p_truck)
$$;

-- Monthly driver metrics in scope.
CREATE OR REPLACE FUNCTION bi.fn_scope_driver_month(
    p_start date DEFAULT NULL, p_end date DEFAULT NULL, p_driver text DEFAULT NULL)
RETURNS SETOF dw.fact_driver_month
LANGUAGE sql STABLE AS $$
    SELECT f.* FROM dw.fact_driver_month f
    WHERE (p_start IS NULL OR f.month_start >= DATE_TRUNC('month', p_start)::date)
      AND (p_end IS NULL OR f.month_start <= p_end)
      AND (p_driver IS NULL OR f.driver_id = p_driver)
$$;
