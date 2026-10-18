# Logistics Operation Database: SQL warehouse and analytics

A complete SQL implementation of the Logistics Operation Database Power BI report: source tables, a star (galaxy) schema, the ETL that builds it, a SQL function for every one of the report's 166 DAX measures, reporting views for all seven dashboards, data-quality and reconciliation checks, and analysis queries (descriptive, diagnostic and predictive).

**Status:** written to reproduce the finished report; linted but **not executed against a live database**. Run the first load in a scratch database and use `bi.v_checks` to confirm the numbers (see the guide).

## What is inside

```
logistics-sql/
  README.md
  run_all.sql                          psql runner
  sql/
    01_schemas_and_source_tables.sql   schemas src, dw, bi; the 14 source (landing) tables
    02_load_or_extract_source_data.sql CSV COPY, postgres_fdw, extraction queries, profiling
    03_star_schema_ddl.sql             dimensions, facts, indexes (galaxy schema)
    03b_optional_foreign_keys.sql      optional foreign keys (NOT VALID)
    04_etl_load_star.sql               CALL dw.load_star(): rebuild the star from src
    05_parameters_and_helper_functions.sql   what-if parameters, bi.sdiv, bi.param, score, status and colour functions
    06_scope_functions.sql             the filter context (slicers as arguments)
    07_measure_functions.sql           measure function packs, one per business area
    08_reporting_views.sql             one dataset per dashboard visual
    09_data_quality_and_reconciliation.sql   v_dq, v_orphan_check, v_checks
    10_analysis_queries.sql            descriptive, diagnostic and predictive analysis
  docs/
    SCHEMA_AND_RELATIONSHIPS.md        architecture, ERD, keys, data dictionary
    MEASURE_CATALOGUE.md               every DAX measure and its SQL column
    SQL_ANALYSIS_GUIDE.md              how to run, filter, analyse, test and extend
```

## Quick start

```bash
# 1. create the landing tables
psql -d YOUR_DB -f sql/01_schemas_and_source_tables.sql
# 2. load your data (edit file 02: CSV, foreign data wrapper or extraction queries)
# 3. build the star and everything on top of it
psql -d YOUR_DB -f sql/03_star_schema_ddl.sql -f sql/04_etl_load_star.sql
psql -d YOUR_DB -c "CALL dw.load_star();"
psql -d YOUR_DB -f sql/05_parameters_and_helper_functions.sql -f sql/06_scope_functions.sql \
     -f sql/07_measure_functions.sql -f sql/08_reporting_views.sql -f sql/09_data_quality_and_reconciliation.sql
# 4. verify
psql -d YOUR_DB -c "SELECT * FROM bi.v_dq;" -c "SELECT * FROM bi.v_checks;"
```

## A first query

```sql
-- Executive cards for 2024
SELECT * FROM bi.m_kpi_exec(p_start := '2024-01-01', p_end := '2024-12-31');

-- Revenue and margin by month for one customer
SELECT dim_label AS month, total_revenue, gross_margin
FROM bi.m_finance_by('year_month', p_customer := 'CUST00002');
```

## Design in one paragraph

Source tables land in `src`. `dw.load_star()` builds a galaxy schema in `dw`: nine dimensions and seven facts, where loads and trips are one fact and every child fact carries its load's keys, so each dimension filters each fact directly. Maintenance links only to trucks, so it is allocated to loads by miles, which keeps customer and route margins sensible. In `bi`, scope functions take the slicers as arguments (NULL = All) and measure functions return the report's measures as columns. Reporting views call them with defaults for a BI tool.

## Documentation

- [`docs/SCHEMA_AND_RELATIONSHIPS.md`](docs/SCHEMA_AND_RELATIONSHIPS.md): architecture, entity-relationship diagram, relationship table, grain, data dictionary.
- [`docs/MEASURE_CATALOGUE.md`](docs/MEASURE_CATALOGUE.md): the DAX to SQL map for all 166 measures, and the function reference.
- [`docs/SQL_ANALYSIS_GUIDE.md`](docs/SQL_ANALYSIS_GUIDE.md): running, filtering, analysis walkthrough, testing, performance, extending, other dialects, troubleshooting.

## Reference findings (the dataset the report was built on)

| Measure | Value |
|---|---|
| Revenue | $262.5M |
| Gross Profit and margin | about $161.2M, 61.4% (contribution margin: excludes driver pay and overhead) |
| Loads | about 85,000 |
| Revenue and cost per mile | $2.15 and about $0.83 |
| Fuel | about 36.4% of revenue |
| On-time delivery | 55.7% against a 95% target |
| Drivers | 124 active; idle 28% to 29% for all, MPG about 6.45 |
| Customers | 200; top 18 hold 31.9% |
| Safety | 170 incidents, 1.4 per million miles |

## Conventions

- Schemas: `src` (landing), `dw` (star), `bi` (analytics). Everything is schema-qualified.
- Measure columns are snake_case versions of the DAX names (`On-Time %` is `on_time_pct`).
- Filters are arguments; NULL means All.
- Types are cast explicitly in every function so result types always match their declarations.

## Licence

Add the licence of your choice before publishing.
