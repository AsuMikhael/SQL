-- ================================================================================================
-- OPTIONAL FOREIGN KEYS
-- ================================================================================================
-- Run after dw.load_star() has succeeded. Constraints are added NOT VALID so existing rows are not checked,
-- then VALIDATE tells you whether the data is clean. Orphan keys make later reloads fail, so keep these
-- off if your source has known orphans (see bi.v_orphan_check in file 09).
-- ================================================================================================

ALTER TABLE dw.fact_load_trip ADD CONSTRAINT fk_fact_load_trip_load_date FOREIGN KEY (load_date) REFERENCES dw.dim_date (full_date) NOT VALID;
ALTER TABLE dw.fact_load_trip ADD CONSTRAINT fk_fact_load_trip_customer_id FOREIGN KEY (customer_id) REFERENCES dw.dim_customer (customer_id) NOT VALID;
ALTER TABLE dw.fact_load_trip ADD CONSTRAINT fk_fact_load_trip_route_id FOREIGN KEY (route_id) REFERENCES dw.dim_route (route_id) NOT VALID;
ALTER TABLE dw.fact_load_trip ADD CONSTRAINT fk_fact_load_trip_driver_id FOREIGN KEY (driver_id) REFERENCES dw.dim_driver (driver_id) NOT VALID;
ALTER TABLE dw.fact_load_trip ADD CONSTRAINT fk_fact_load_trip_truck_id FOREIGN KEY (truck_id) REFERENCES dw.dim_truck (truck_id) NOT VALID;
ALTER TABLE dw.fact_load_trip ADD CONSTRAINT fk_fact_load_trip_trailer_id FOREIGN KEY (trailer_id) REFERENCES dw.dim_trailer (trailer_id) NOT VALID;
ALTER TABLE dw.fact_delivery_event ADD CONSTRAINT fk_fact_delivery_event_facility_id FOREIGN KEY (facility_id) REFERENCES dw.dim_facility (facility_id) NOT VALID;
ALTER TABLE dw.fact_maintenance_event ADD CONSTRAINT fk_fact_maintenance_event_truck_id FOREIGN KEY (truck_id) REFERENCES dw.dim_truck (truck_id) NOT VALID;
ALTER TABLE dw.fact_maintenance_event ADD CONSTRAINT fk_fact_maintenance_event_maintenance_date FOREIGN KEY (maintenance_date) REFERENCES dw.dim_date (full_date) NOT VALID;
ALTER TABLE dw.fact_truck_month ADD CONSTRAINT fk_fact_truck_month_truck_id FOREIGN KEY (truck_id) REFERENCES dw.dim_truck (truck_id) NOT VALID;
ALTER TABLE dw.fact_truck_month ADD CONSTRAINT fk_fact_truck_month_month_start FOREIGN KEY (month_start) REFERENCES dw.dim_date (full_date) NOT VALID;
ALTER TABLE dw.fact_driver_month ADD CONSTRAINT fk_fact_driver_month_driver_id FOREIGN KEY (driver_id) REFERENCES dw.dim_driver (driver_id) NOT VALID;
ALTER TABLE dw.fact_driver_month ADD CONSTRAINT fk_fact_driver_month_month_start FOREIGN KEY (month_start) REFERENCES dw.dim_date (full_date) NOT VALID;

-- Validate (each statement fails if orphans exist):
-- ALTER TABLE dw.fact_load_trip VALIDATE CONSTRAINT fk_fact_load_trip_load_date;
-- ALTER TABLE dw.fact_load_trip VALIDATE CONSTRAINT fk_fact_load_trip_customer_id;
-- ALTER TABLE dw.fact_load_trip VALIDATE CONSTRAINT fk_fact_load_trip_route_id;
-- ALTER TABLE dw.fact_load_trip VALIDATE CONSTRAINT fk_fact_load_trip_driver_id;
-- ALTER TABLE dw.fact_load_trip VALIDATE CONSTRAINT fk_fact_load_trip_truck_id;
-- ALTER TABLE dw.fact_load_trip VALIDATE CONSTRAINT fk_fact_load_trip_trailer_id;
-- ALTER TABLE dw.fact_delivery_event VALIDATE CONSTRAINT fk_fact_delivery_event_facility_id;
-- ALTER TABLE dw.fact_maintenance_event VALIDATE CONSTRAINT fk_fact_maintenance_event_truck_id;
-- ALTER TABLE dw.fact_maintenance_event VALIDATE CONSTRAINT fk_fact_maintenance_event_maintenance_date;
-- ALTER TABLE dw.fact_truck_month VALIDATE CONSTRAINT fk_fact_truck_month_truck_id;
-- ALTER TABLE dw.fact_truck_month VALIDATE CONSTRAINT fk_fact_truck_month_month_start;
-- ALTER TABLE dw.fact_driver_month VALIDATE CONSTRAINT fk_fact_driver_month_driver_id;
-- ALTER TABLE dw.fact_driver_month VALIDATE CONSTRAINT fk_fact_driver_month_month_start;
