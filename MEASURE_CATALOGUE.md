# Measure catalogue: DAX to SQL

Every one of the 166 measures of the Power BI model and the SQL column that replaces it. Names follow one rule: lower case, spaces and symbols become underscores, and `%` becomes `pct` (`On-Time %` is `on_time_pct`, `Revenue (Trip-based)` is `revenue_trip_based`). Two names are special: `7 Day Avg` is `loads_booked_7day_avg` and `% On-time Deliveries` is `pct_on_time_deliveries`.

## 1. How the SQL measures work

- Every measure function takes the same filter arguments, where **NULL means All**: `p_start`, `p_end` (inclusive load-date range), `p_customer`, `p_route`, `p_driver`, `p_truck`, `p_booking`. Extra filters: `p_facility`, `p_incident_type`, `p_state`, `p_type`.
- **Overall packs** (`m_finance`, `m_service`, `m_driver_overall`, `m_fleet_overall`, `m_fuel_overall`, `m_safety_overall`, `m_customer_overall`) return one row of cards.
- **By-dimension packs** (`m_finance_by`, `m_delivery_by`, `m_fuel_by`, `m_safety_by`, `m_maintenance_by`) take a dimension name first and return one row per group (`dim_key`, `dim_label`, then the measures).
- **Scorecards** (`m_driver_scorecard`, `m_truck_scorecard`, `m_customer_scorecard`, `m_route_scorecard`) return one row per driver, truck, customer or route, with ranks, flags and colours.
- Parameters are read with `bi.param('name')`; the 11 value measures are in `bi.v_parameter_values`.
- Tag **V** means the measure is used by a visual of the finished report; **B** means it was built during the project (supporting, optional or retired).

## 2. Function reference

| Function | Arguments | What it returns |
|---|---|---|
| `bi.m_finance` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Finance and volume measures: revenue, miles, fuel, allocated maintenance, Gross Profit, margins, per-mile figures, MPG, idle, route and pricing ratios. |
| `bi.m_finance_by` | p_dimension, p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Finance measures grouped by any dimension (Dashboard 1, 2, 7 charts). Dimensions: year, quarter, month_number, year_month, day_name, customer, customer_type, freight_type, route, origin_city, destination_city, booking_type, load_type, driver, tenure_band, truck, truck_make, model_year, truck_age_band. |
| `bi.m_time_overall` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Prior-year comparison for the selected window (SAMEPERIODLASTYEAR). With no dates it compares each year with the one before, so pass dates for a headline YoY. |
| `bi.m_revenue_trend` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Monthly revenue with prior year, YoY, MoM, YTD and rolling 12 months. Rolling 12 needs 12 months in the window. |
| `bi.m_loads_daily` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Loads booked per day with the 7-day average (7 Day Avg). Days with no loads are skipped, as AVERAGEX does. |
| `bi.m_service` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_facility | Service measures: on-time, detention, cancellations, transit time and the Customer Service Score (Dashboard 2 cards). |
| `bi.m_delivery_by` | p_dimension, p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_facility | Delivery and detention measures grouped by any dimension (on-time trend, facility charts, detention histogram). Dimensions: year, quarter, month_number, year_month, day_name, customer, route, driver, booking_type, facility, facility_city, facility_state, detention_bucket. |
| `bi.m_driver_fleet` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Driver-level inputs aggregated for the whole fleet; the fleet Driver Score is the reference for the score colour. |
| `bi.m_driver_scorecard` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | One row per driver (DRV_UNKNOWN excluded): score, rank, bucket, colour, Top N flag and the low-miles filter. |
| `bi.m_driver_overall` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Dashboard 3 cards: workforce, productivity, fuel economy, idle, on-time, safety, turnover and tenure. |
| `bi.m_driver_by_tenure` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Driver Score by tenure band (computed on band totals, DRV_UNKNOWN excluded). |
| `bi.m_idle_band` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Trips by idle share (Trips[Idle Ratio] and Trips[Idle Band]). |
| `bi.m_truck_scorecard` | p_start, p_end, p_truck, p_type | One row per truck: maintenance, utilization, last service, service status and colours, Top N flag. |
| `bi.m_fleet_overall` | p_start, p_end, p_truck, p_type | Dashboard 4 cards: fleet size and age, maintenance cost, downtime, availability, overdue trucks, utilization. |
| `bi.m_maintenance_by` | p_dimension, p_start, p_end, p_truck, p_type | Maintenance measures grouped by any dimension (cost by month, by type, by model year). Dimensions: year, quarter, month_number, year_month, maintenance_type, truck, truck_make, model_year, truck_age_band. |
| `bi.m_trailer_util_by_type` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Trailer utilization by trailer type. |
| `bi.m_fuel_overall` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_state | Dashboard 5 fuel cards and what-if panel: cost, price, MPG, idle fuel cost, savings to the target MPG, price scenario. |
| `bi.m_fuel_by` | p_dimension, p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_state | Fuel cost, gallons and price grouped by any dimension (cost and price by month). Dimensions: year, quarter, month_number, year_month, state, customer, route, driver, truck. |
| `bi.m_fuel_by_state` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_state | Fuel spend and price by state, with the price gap to the fleet average and its colour. States with no value are excluded. |
| `bi.m_safety_overall` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type | Dashboard 5 safety cards. safety_incident is the rate per 100,000 miles (the legacy Safety incident measure); incidents_per_1m_miles is the rate used elsewhere. |
| `bi.m_safety_by` | p_dimension, p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type | Safety measures grouped by any dimension (incidents by type and month). Dimensions: year, quarter, month_number, year_month, incident_type, customer, route, driver, truck. |
| `bi.m_safety_by_driver` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type | Incidents per driver (DRV_UNKNOWN excluded) with the Top N Incident Driver Flag. |
| `bi.m_latest_incidents` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking, p_incident_type, p_limit | The most recent incidents (default 20). |
| `bi.m_customer_scorecard` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | One row per customer: revenue, margin, on-time, rank, Pareto class, churn status and wallet share. |
| `bi.m_customer_overall` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Dashboard 6 cards. New Customers and Retention need a year; Wallet Share is only meaningful for one year. |
| `bi.m_route_scorecard` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | One row per route: profit, margin, cost and revenue per mile, distance and rate realization, tier, rank and Top/Bottom N flags. |
| `bi.m_lane_matrix` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Gross margin by origin and destination (the lane matrix). |
| `bi.m_city_network` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Loads out and in per city, and the balance between them (Network City). |
| `bi.m_margin_bridge` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | The margin waterfall: revenue, fuel, maintenance and the Gross Profit total. |
| `bi.m_scenario` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | What-if: revenue moved by the Rate Change parameter and fuel by the Fuel Price Change parameter. |
| `bi.m_kpi_exec` | p_start, p_end, p_customer, p_route, p_driver, p_truck, p_booking | Dashboard 1 cards and the dynamic Headline text. Pass dates for a meaningful YoY. |
| `bi.fleet_maint_cost_per_mile` | p_start, p_end | Fleet Maint Cost per Mile: all maintenance in the window over all miles in the window (helper used by m_finance). |
| `bi.f_*` | see file 05 | Score, status and colour functions: `f_driver_score`, `f_driver_bucket`, `f_color_driver_score`, `f_service_score`, `f_service_status`, `f_color_service_status`, `f_color_on_time`, `f_color_utilization`, `f_color_cost_per_mile`, `f_color_price_variance`, `f_abc_class`, `f_color_abc`, `f_churn_status`, `f_color_churn`, `f_route_tier`, `f_color_route_tier` |
| `bi.sdiv`, `bi.param`, `dw.data_as_of` | file 05 | DIVIDE, parameter value, Data As Of |

## 3. Measure to SQL mapping

| DAX measure | Home table | Folder | Tag | SQL function | SQL column | Also in |
|---|---|---|---|---|---|---|
| On-Time Target Value | On-Time Target | 0 Parameters | B | `bi.v_parameter_values` | `on_time_target_value` |  |
| Utilization Target Value | Utilization Target | 0 Parameters | B | `bi.v_parameter_values` | `utilization_target_value` |  |
| Driver Pay per Mile Value | Driver Pay per Mile | 0 Parameters | B | `bi.v_parameter_values` | `driver_pay_per_mile_value` |  |
| Detention Rate Value | Detention Rate per Hour | 0 Parameters | B | `bi.v_parameter_values` | `detention_rate_value` |  |
| Idle Burn Value | Idle Burn Gal per Hour | 0 Parameters | B | `bi.v_parameter_values` | `idle_burn_value` |  |
| Target MPG Value | Target MPG | 0 Parameters | B | `bi.v_parameter_values` | `target_mpg_value` |  |
| Fuel Price Change Value | Fuel Price Change | 0 Parameters | B | `bi.v_parameter_values` | `fuel_price_change_value` |  |
| Rate Change Value | Rate Change | 0 Parameters | B | `bi.v_parameter_values` | `rate_change_value` |  |
| Top N Value | Top N | 0 Parameters | B | `bi.v_parameter_values` | `top_n_value` |  |
| Service Interval Value | Service Interval Days | 0 Parameters | B | `bi.v_parameter_values` | `service_interval_value` |  |
| Churn Days Value | Churn Days | 0 Parameters | B | `bi.v_parameter_values` | `churn_days_value` |  |
| Data As Of | Loads | 1 Core | B | `dw.data_as_of` | `data_as_of` |  |
| Total Revenue | Loads | 1 Core | V | `bi.m_finance` | `total_revenue` | `m_finance_by`, `m_revenue_trend`, `m_lane_matrix` |
| Customer Revenue | Customers | 1 Core | V | `bi.m_finance` | `customer_revenue` | `m_finance_by`, `m_customer_scorecard` |
| Route Revenue | Routes | 1 Core | V | `bi.m_finance` | `route_revenue` | `m_finance_by`, `m_route_scorecard` |
| Load Count | Routes | 1 Core | V | `bi.m_finance` | `load_count` | `m_finance_by`, `m_customer_scorecard`, `m_route_scorecard` |
| Loads Booked | Loads | 1 Core | V | `bi.m_finance` | `loads_booked` | `m_finance_by`, `m_loads_daily`, `m_service` |
| Trip Count | Trips | 1 Core | B | `bi.m_finance` | `trip_count` | `m_finance_by`, `m_driver_scorecard`, `m_idle_band` |
| Total Miles | Trips | 1 Core | B | `bi.m_finance` | `total_miles` | `m_finance_by`, `m_driver_fleet`, `m_driver_scorecard` |
| Revenue Per Mile | Loads | 1 Core | V | `bi.m_finance` | `revenue_per_mile` | `m_finance_by`, `m_route_scorecard`, `m_kpi_exec` |
| Revenue Per Load | Loads | 1 Core | V | `bi.m_finance` | `revenue_per_load` | `m_finance_by`, `m_service` |
| Revenue (Trip-based) | Trips | 1 Core | B | `bi.m_finance` | `revenue_trip_based` | `m_finance_by`, `m_driver_scorecard`, `m_truck_scorecard` |
| Fuel Cost | Fuel Purchases | 1 Core | V | `bi.m_finance` | `fuel_cost` | `m_finance_by`, `m_fuel_overall`, `m_fuel_by` |
| Fuel Gallons | Fuel Purchases | 1 Core | V | `bi.m_finance` | `fuel_gallons` | `m_finance_by`, `m_fuel_overall`, `m_fuel_by` |
| Fuel Gallons Used | Trips | 1 Core | B | `bi.m_finance` | `fuel_gallons_used` | `m_finance_by` |
| Maintenance Cost | Fuel Purchases | 1 Core | V | `bi.m_truck_scorecard` | `maintenance_cost` | `m_fleet_overall`, `m_maintenance_by` |
| Fleet Maint Cost per Mile | Maintenance Record | 1 Core: profitability | B | `bi.m_finance` | `fleet_maint_cost_per_mile` | `fleet_maint_cost_per_mile` |
| Maintenance Cost Allocated | Maintenance Record | 1 Core: profitability | B | `bi.m_finance` | `maintenance_cost_allocated` | `m_finance_by` |
| Gross Profit | Loads | 1 Core: profitability | V | `bi.m_finance` | `gross_profit` | `m_finance_by`, `m_revenue_trend`, `m_route_scorecard` |
| Gross Margin | Loads | 1 Core: profitability | V | `bi.m_finance` | `gross_margin` | `m_finance_by`, `m_revenue_trend`, `m_route_scorecard` |
| Total Cost | Loads | 1 Core: profitability | B | `bi.m_finance` | `total_cost` | `m_finance_by` |
| Route Cost per Mile | Routes | 1 Core: profitability | V | `bi.m_finance` | `route_cost_per_mile` | `m_finance_by`, `m_route_scorecard` |
| Profit per Mile | Routes | 1 Core: profitability | B | `bi.m_finance` | `profit_per_mile` | `m_finance_by`, `m_route_scorecard` |
| Customer Margin | Customers | 1 Core: profitability | B | `bi.m_finance` | `customer_margin` | `m_finance_by`, `m_customer_scorecard` |
| Customer Margin % | Customers | 1 Core: profitability | V | `bi.m_finance` | `customer_margin_pct` | `m_finance_by`, `m_customer_scorecard`, `m_customer_overall` |
| Driver Cost | Driver Monthly Metrics | 1 Core: profitability | B | `bi.m_finance` | `driver_cost` | `m_finance_by` |
| Total Operating Cost | Driver Monthly Metrics | 1 Core: profitability | B | `bi.m_finance` | `total_operating_cost` | `m_finance_by` |
| Cost per Mile | Driver Monthly Metrics | 1 Core: profitability | V | `bi.m_finance` | `cost_per_mile` | `m_finance_by` |
| Revenue PY | Loads | 2 Time | B | `bi.m_revenue_trend` | `revenue_py` | `m_time_overall`, `m_kpi_exec` |
| Revenue YoY % | Loads | 2 Time | V | `bi.m_revenue_trend` | `revenue_yoy_pct` | `m_time_overall`, `m_kpi_exec` |
| Revenue MoM % | Loads | 2 Time | B | `bi.m_revenue_trend` | `revenue_mom_pct` |  |
| Revenue YTD | Loads | 2 Time | B | `bi.m_revenue_trend` | `revenue_ytd` |  |
| Revenue Rolling 12M | Loads | 2 Time | B | `bi.m_revenue_trend` | `revenue_rolling_12m` |  |
| Gross Profit PY | Loads | 2 Time | B | `bi.m_revenue_trend` | `gross_profit_py` | `m_time_overall` |
| Gross Profit YoY % | Loads | 2 Time | B | `bi.m_revenue_trend` | `gross_profit_yoy_pct` | `m_time_overall`, `m_kpi_exec` |
| 7 Day Avg | Loads | 2 Time | V | `bi.m_loads_daily` | `loads_booked_7day_avg` |  |
| Total Deliveries | Delivery Events | 3 Service | B | `bi.m_service` | `total_deliveries` | `m_delivery_by`, `m_customer_scorecard` |
| On-Time Deliveries | Delivery Events | 3 Service | B | `bi.m_service` | `on_time_deliveries` | `m_delivery_by`, `m_customer_scorecard` |
| Late Deliveries | Loads | 3 Service | V | `bi.m_service` | `late_deliveries` | `m_delivery_by`, `m_customer_scorecard` |
| On-Time % | Loads | 3 Service | V | `bi.m_service` | `on_time_pct` | `m_delivery_by`, `m_driver_fleet`, `m_kpi_exec` |
| % On-time Deliveries | Delivery Events | 3 Service | V | `bi.m_service` | `pct_on_time_deliveries` | `m_delivery_by` |
| Average Detention | Delivery Events | 3 Service | V | `bi.m_service` | `average_detention` | `m_delivery_by`, `m_kpi_exec` |
| Detention Hours | Delivery Events | 3 Service | B | `bi.m_service` | `detention_hours` | `m_delivery_by` |
| Detention Cost | Delivery Events | 3 Service | B | `bi.m_service` | `detention_cost` | `m_delivery_by` |
| Detained Stops % | Delivery Events | 3 Service | B | `bi.m_service` | `detained_stops_pct` | `m_delivery_by`, `m_customer_scorecard` |
| Detention Cost per Load | Delivery Events | 3 Service | B | `bi.m_service` | `detention_cost_per_load` |  |
| Loads Delivered | Loads | 3 Service | V | `bi.m_service` | `loads_delivered` | `m_finance`, `m_finance_by` |
| Cancelled Loads | Loads | 3 Service | B | `bi.m_service` | `cancelled_loads` | `m_finance`, `m_finance_by` |
| Cancellation Rate | Loads | 3 Service | B | `bi.m_service` | `cancellation_rate` | `m_finance`, `m_finance_by`, `m_customer_scorecard` |
| Average Transit Time | Loads | 3 Service | V | `bi.m_service` | `average_transit_time` | `m_finance`, `m_finance_by` |
| Customer Service Score | Loads | 3 Service | V | `bi.m_service` | `customer_service_score` | `m_customer_scorecard` |
| Delivery Volume Share | Loads | 3 Service | B | `bi.m_finance` | `delivery_volume_share` | `m_finance_by` |
| Active Drivers | Drivers | 4 Drivers | V | `bi.m_driver_overall` | `active_drivers` |  |
| Drivers With Trips | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `drivers_with_trips` | `m_driver_by_tenure`, `m_finance`, `m_finance_by` |
| Miles per Driver | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `miles_per_driver` |  |
| Revenue per Driver | Drivers | 4 Drivers | V | `bi.m_driver_overall` | `revenue_per_driver` | `m_driver_scorecard` |
| Avg MPG | Drivers | 4 Drivers | V | `bi.m_driver_overall` | `avg_mpg` | `m_driver_scorecard`, `m_driver_by_tenure`, `m_driver_fleet` |
| Idle % | Drivers | 4 Drivers | V | `bi.m_driver_overall` | `idle_pct` | `m_driver_scorecard`, `m_driver_by_tenure`, `m_driver_fleet` |
| Driver On-Time % | Drivers | 4 Drivers | V | `bi.m_driver_overall` | `driver_on_time_pct` | `m_driver_scorecard`, `m_driver_by_tenure`, `m_service` |
| Driver On-Time % (Monthly) | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `driver_on_time_pct_monthly` | `m_driver_scorecard` |
| Incidents per 1M Miles | Drivers | 4 Drivers | V | `bi.m_driver_overall` | `incidents_per_1m_miles` | `m_driver_scorecard`, `m_driver_by_tenure`, `m_driver_fleet` |
| Driver Score | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `driver_score` | `m_driver_scorecard`, `m_driver_by_tenure` |
| Driver Rank | Drivers | 4 Drivers | B | `bi.m_driver_scorecard` | `driver_rank` |  |
| Driver Bucket | Drivers | 4 Drivers | B | `bi.m_driver_scorecard` | `driver_bucket` |  |
| Top N Driver Flag | Drivers | 4 Drivers | B | `bi.m_driver_scorecard` | `top_n_driver_flag` |  |
| Low Miles Filter | Drivers | 4 Drivers | B | `bi.m_driver_scorecard` | `low_miles_filter` |  |
| Driver Score Color | Drivers | 4 Drivers | B | `bi.m_driver_scorecard` | `driver_score_color` | `m_driver_by_tenure` |
| Idle % vs Fleet | Drivers | 4 Drivers | B | `bi.m_driver_scorecard` | `idle_pct_vs_fleet` |  |
| Idle % Best Driver | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `idle_pct_best_driver` |  |
| Idle % Worst Driver | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `idle_pct_worst_driver` |  |
| Drivers Terminated | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `drivers_terminated` |  |
| Turnover % | Drivers | 4 Drivers | V | `bi.m_driver_overall` | `turnover_pct` |  |
| Avg Tenure (yrs) | Drivers | 4 Drivers | B | `bi.m_driver_overall` | `avg_tenure_yrs` |  |
| Labor Cost | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `labor_cost` | `m_truck_scorecard`, `m_maintenance_by` |
| Parts Cost | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `parts_cost` | `m_truck_scorecard`, `m_maintenance_by` |
| Maintenance Events | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `maintenance_events` | `m_truck_scorecard`, `m_maintenance_by` |
| Avg Cost per Event | Trucks | 5 Fleet | B | `bi.m_fleet_overall` | `avg_cost_per_event` | `m_truck_scorecard`, `m_maintenance_by` |
| Downtime Hours | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `downtime_hours` | `m_truck_scorecard`, `m_maintenance_by` |
| Active Trucks | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `active_trucks` |  |
| Fleet Age (yrs) | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `fleet_age_yrs` |  |
| Maint Cost per Mile (actual) | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `maint_cost_per_mile_actual` | `m_truck_scorecard` |
| Miles Between Service | Trucks | 5 Fleet | B | `bi.m_fleet_overall` | `miles_between_service` | `m_truck_scorecard` |
| Availability % | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `availability_pct` |  |
| Days Since Last Service | Trucks | 5 Fleet | V | `bi.m_truck_scorecard` | `days_since_last_service` |  |
| Overdue Trucks | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `overdue_trucks` |  |
| Service Status | Trucks | 5 Fleet | V | `bi.m_truck_scorecard` | `service_status` |  |
| Top N Truck Flag | Trucks | 5 Fleet | V | `bi.m_truck_scorecard` | `top_n_truck_flag` |  |
| Trailer Utilization % | Trucks | 5 Fleet | V | `bi.m_fleet_overall` | `trailer_utilization_pct` | `m_trailer_util_by_type` |
| Fleet Utilization % | Truck Utilization Metrics | 5 Fleet | V | `bi.m_fleet_overall` | `fleet_utilization_pct` | `m_truck_scorecard`, `m_kpi_exec` |
| Avg Price per Gallon | Fuel Purchases | 6 Fuel & Safety | V | `bi.m_fuel_overall` | `avg_price_per_gallon` | `m_fuel_by_state`, `m_fuel_by` |
| Fuel Cost per Mile | Fuel Purchases | 6 Fuel & Safety | B | `bi.m_fuel_overall` | `fuel_cost_per_mile` |  |
| Fuel % of Revenue | Fuel Purchases | 6 Fuel & Safety | V | `bi.m_fuel_overall` | `fuel_pct_of_revenue` |  |
| State Price vs Fleet Avg | Fuel Purchases | 6 Fuel & Safety | B | `bi.m_fuel_by_state` | `state_price_vs_fleet_avg` |  |
| Idle Hours | Fuel Purchases | 6 Fuel & Safety | B | `bi.m_fuel_overall` | `idle_hours` | `m_finance`, `m_finance_by` |
| Idle Fuel Gallons | Fuel Purchases | 6 Fuel & Safety | B | `bi.m_fuel_overall` | `idle_fuel_gallons` |  |
| Idle Fuel Cost | Fuel Purchases | 6 Fuel & Safety | V | `bi.m_fuel_overall` | `idle_fuel_cost` |  |
| Fuel Savings to Target MPG | Fuel Purchases | 6 Fuel & Safety | B | `bi.m_fuel_overall` | `fuel_savings_to_target_mpg` |  |
| Fuel Cost Scenario | Fuel Purchases | 6 Fuel & Safety | B | `bi.m_fuel_overall` | `fuel_cost_scenario` |  |
| Fuel Scenario Margin Impact | Fuel Purchases | 6 Fuel & Safety | B | `bi.m_fuel_overall` | `fuel_scenario_margin_impact` |  |
| Safety Incidents | Safety Incidents | 6 Fuel & Safety | V | `bi.m_safety_overall` | `safety_incidents` | `m_safety_by_driver`, `m_safety_by`, `m_kpi_exec` |
| Safety incident | Safety Incidents | 6 Fuel & Safety | V | `bi.m_safety_overall` | `safety_incident` | `m_kpi_exec` |
| At-Fault Incidents | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_overall` | `at_fault_incidents` | `m_safety_by` |
| At-Fault % | Safety Incidents | 6 Fuel & Safety | V | `bi.m_safety_overall` | `at_fault_pct` | `m_safety_by` |
| Preventable Incidents | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_overall` | `preventable_incidents` | `m_safety_by` |
| Preventable % | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_overall` | `preventable_pct` | `m_safety_by` |
| Injury Incidents | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_overall` | `injury_incidents` | `m_safety_by` |
| Total Claims | Safety Incidents | 6 Fuel & Safety | V | `bi.m_safety_overall` | `total_claims` | `m_safety_by_driver`, `m_safety_by` |
| Damage Cost | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_overall` | `damage_cost` | `m_safety_by` |
| Cost per Incident | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_overall` | `cost_per_incident` | `m_safety_by` |
| Days Since Last Incident | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_overall` | `days_since_last_incident` |  |
| Top N Incident Driver Flag | Safety Incidents | 6 Fuel & Safety | B | `bi.m_safety_by_driver` | `top_n_incident_driver_flag` |  |
| Price Variance Color | Fuel Purchases | 6 Fuel & Safety | V | `bi.m_fuel_by_state` | `price_variance_color` |  |
| Active Customers | Customers | 7 Customers | V | `bi.m_customer_overall` | `active_customers` | `m_finance`, `m_finance_by` |
| Avg Revenue per Customer | Customers | 7 Customers | V | `bi.m_customer_overall` | `avg_revenue_per_customer` |  |
| Customer On-Time % | Customers | 7 Customers | V | `bi.m_customer_scorecard` | `customer_on_time_pct` | `m_service`, `m_delivery_by` |
| Customer Rank | Customers | 7 Customers | V | `bi.m_customer_scorecard` | `customer_rank` |  |
| Top N Customer Flag | Customers | 7 Customers | V | `bi.m_customer_scorecard` | `top_n_customer_flag` |  |
| Top N Customer Share | Customers | 7 Customers | V | `bi.m_customer_overall` | `top_n_customer_share` |  |
| Cumulative Revenue % | Customers | 7 Customers | V | `bi.m_customer_scorecard` | `cumulative_revenue_pct` |  |
| ABC Class | Customers | 7 Customers | V | `bi.m_customer_scorecard` | `abc_class` |  |
| ABC Color | Customers | 7 Customers | V | `bi.m_customer_scorecard` | `abc_color` |  |
| New Customers | Customers | 7 Customers | V | `bi.m_customer_overall` | `new_customers` |  |
| Retained Customers | Customers | 7 Customers | B | `bi.m_customer_overall` | `retained_customers` |  |
| Retention % | Customers | 7 Customers | V | `bi.m_customer_overall` | `retention_pct` |  |
| Repeat Customers | Customers | 7 Customers | B | `bi.m_customer_overall` | `repeat_customers` |  |
| Repeat Rate | Customers | 7 Customers | B | `bi.m_customer_overall` | `repeat_rate` |  |
| Days Since Last Load | Customers | 7 Customers | V | `bi.m_customer_scorecard` | `days_since_last_load` |  |
| At-Risk Customers | Customers | 7 Customers | V | `bi.m_customer_overall` | `at_risk_customers` |  |
| Churn Status | Churn Days | 7 Customers | V | `bi.m_customer_scorecard` | `churn_status` |  |
| Churn Status Color | Churn Days | 7 Customers | V | `bi.m_customer_scorecard` | `churn_status_color` |  |
| Wallet Share | Customers | 7 Customers | V | `bi.m_customer_overall` | `wallet_share` |  |
| Margin vs Fleet | Routes | 8 Routes | B | `bi.m_route_scorecard` | `margin_vs_fleet` |  |
| Route Profit Tier | Routes | 8 Routes | V | `bi.m_route_scorecard` | `route_profit_tier` |  |
| Route Tier Color | Loads | 8 Routes | V | `bi.m_route_scorecard` | `route_tier_color` |  |
| Route Rank | Routes | 8 Routes | B | `bi.m_route_scorecard` | `route_rank` |  |
| Top N Route Flag | Routes | 8 Routes | V | `bi.m_route_scorecard` | `top_n_route_flag` |  |
| Bottom N Route Flag | Routes | 8 Routes | B | `bi.m_route_scorecard` | `bottom_n_route_flag` |  |
| Expected Miles | Routes | 8 Routes | B | `bi.m_route_scorecard` | `expected_miles` | `m_finance`, `m_finance_by` |
| Distance Variance % | Routes | 8 Routes | V | `bi.m_route_scorecard` | `distance_variance_pct` | `m_finance`, `m_finance_by` |
| Expected Linehaul Revenue | Routes | 8 Routes | B | `bi.m_route_scorecard` | `expected_linehaul_revenue` | `m_finance`, `m_finance_by` |
| Rate Realization % | Routes | 8 Routes | V | `bi.m_route_scorecard` | `rate_realization_pct` | `m_finance`, `m_finance_by` |
| Outbound Loads | Loads | 8 Routes | V | `bi.m_city_network` | `outbound_loads` |  |
| Inbound Loads | Loads | 8 Routes | V | `bi.m_city_network` | `inbound_loads` |  |
| Lane Balance | Loads | 8 Routes | B | `bi.m_city_network` | `lane_balance` |  |
| Lane Balance % | Loads | 8 Routes | V | `bi.m_city_network` | `lane_balance_pct` |  |
| Margin Bridge Value | Loads | 8 Routes | V | `bi.m_margin_bridge` | `margin_bridge_value` |  |
| Revenue Scenario | Routes | 8 Routes | B | `bi.m_scenario` | `revenue_scenario` |  |
| Cost Scenario | Routes | 8 Routes | B | `bi.m_scenario` | `cost_scenario` |  |
| Profit Scenario | Routes | 8 Routes | B | `bi.m_scenario` | `profit_scenario` |  |
| Profit Scenario Delta | Routes | 8 Routes | B | `bi.m_scenario` | `profit_scenario_delta` |  |
| Margin Scenario % | Routes | 8 Routes | B | `bi.m_scenario` | `margin_scenario_pct` |  |
| Cost per Mile Color | Truck Utilization Metrics | 9 Formatting | V | `bi.m_truck_scorecard` | `cost_per_mile_color` |  |
| Service Status Color | Trucks | 9 Formatting | V | `bi.m_truck_scorecard` | `service_status_color` |  |
| On-Time Status Color | Loads | 9 Formatting | B | `bi.m_service` | `on_time_status_color` | `m_kpi_exec`, `m_delivery_by` |
| Utilization Status Color | Truck Utilization Metrics | 9 Formatting | B | `bi.m_fleet_overall` | `utilization_status_color` | `m_kpi_exec` |
| Headline | Loads | 9 Formatting | B | `bi.m_kpi_exec` | `headline` |  |

## 4. Where SQL and DAX differ

| Topic | SQL behaviour |
|---|---|
| Maintenance allocation | Allocated at each calendar month's cost per mile when the star is loaded. Whole months and years reconcile to actual maintenance; a customer or route slice can differ slightly from DAX, which uses the selected period's ratio. |
| Prior-year measures | Shift the selected date window by one year and keep the other filters. For a month selected across several years, DAX shifts each date and SQL shifts the window. |
| Ranks and flags | Computed over the rows in scope (DAX ALLSELECTED). Top N uses the `top_n` parameter. |
| Scores and colours | Same weights and thresholds as the report. The fleet reference for the driver score colour is computed over the same scope. |
| Rows with no trip_id | Keep NULL keys; they drop out of date-filtered results, as in the report. |
| Slicer state | There is no slicer table: filters are function arguments, so every call is explicit and repeatable. |

