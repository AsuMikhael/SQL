-- run_all.sql: build everything from the repository root with psql.
--   psql -d YOUR_DATABASE -f run_all.sql
-- 1. Edit sql/02_load_or_extract_source_data.sql (choose CSV, FDW or extraction) and run it between steps 1 and 3,
--    or load the src tables your own way.
\set ON_ERROR_STOP on

\i sql/01_schemas_and_source_tables.sql
-- \i sql/02_load_or_extract_source_data.sql
\i sql/03_star_schema_ddl.sql
\i sql/04_etl_load_star.sql
CALL dw.load_star();
\i sql/05_parameters_and_helper_functions.sql
\i sql/06_scope_functions.sql
\i sql/07_measure_functions.sql
\i sql/08_reporting_views.sql
\i sql/09_data_quality_and_reconciliation.sql

SELECT * FROM bi.v_dq;
SELECT * FROM bi.v_checks;
