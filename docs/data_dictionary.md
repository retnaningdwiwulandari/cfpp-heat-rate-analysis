# Data dictionary

This file describes the three tables in `data/`. They are exports of the final BigQuery tables and feed the Data Studio dashboard.

| File | Grain (1 row =) | Rows | Built in |
|---|---|---|---|
| `dash_plant_ranking.csv` | one plant | 151 | `sql/04_rank_plants.sql` |
| `dash_plant_savings.csv` | one plant | 151 | `sql/07_estimate_fuel_savings.sql` |
| `dash_monthly_performance.csv` | one plant in one month | 1,812 (151 x 12) | `sql/06_compare_load_vs_heat_rate.sql` |

In BigQuery they are the tables `cfpp_plant_ranking`, `cfpp_plant_savings` and `cfpp_monthly_performance`, exported with `sql/08_export_dashboard_data.sql`.

All three tables cover the same 151 plants: coal-fired steam turbine plants that are not combined heat and power, burn at least 90% coal, generated at least 100,000 MWh in 2025, and belong to one of four peer groups (Subcritical, Supercritical, Fluidized bed, Lignite).

## Units and key terms

- **Heat rate**: fuel burned per unit of electricity, in Btu/kWh. Lower is better. Calculated as `fuel_mmbtu / netgen_mwh * 1000`. Thermal efficiency = 3,412 / heat rate.
- **Capacity factor**: actual generation divided by the maximum possible generation at nameplate capacity. 1.0 means the plant ran at full power all the time.
- **Peer group**: plants with the same technology or fuel. Each plant is compared with its own peer group, never with the whole fleet.
- **Peer median**: the median heat rate of the peer group. Half of the plants in the group already reach it.

## Shared columns

| Column | Type | Unit | Description |
|---|---|---|---|
| `plant_id` | integer | | EIA plant code. Use this to join the tables. |
| `plant_name` | text | | Plant name as reported to EIA-923. |
| `plant_state` | text | | Two-letter US state code. |
| `latitude`, `longitude` | decimal | degrees | Plant location from EIA-860. Not in the monthly table. |
| `peer_group` | text | | Subcritical, Supercritical, Fluidized bed or Lignite. Rules are in `sql/03_build_cfpp_plants.sql`. |
| `capacity_mw` | decimal | MW | Nameplate capacity of the plant's coal units (EIA-860). |
| `capacity_factor` | decimal | 0 to 1 | `netgen_mwh / (capacity_mw * 8760)` for the year. |
| `fuel_mmbtu` | decimal | MMBtu | Coal burned for electricity in 2025 (monthly table: in that month). |
| `netgen_mwh` | decimal | MWh | Net electricity generated from coal (monthly table: in that month). |
| `heat_rate_btu_kwh` | integer | Btu/kWh | Annual heat rate. |
| `peer_median_btu_kwh` | integer | Btu/kWh | Median heat rate of the plant's peer group. |
| `gap_vs_peer_pct` | decimal | % | How far the plant is above (+) or below (-) its peer median. |

## dash_plant_ranking.csv

How each plant ranks within its peer group and across the fleet.

| Column | Type | Unit | Description |
|---|---|---|---|
| `steam_technology` | text | | Subcritical, Supercritical or Ultra-supercritical, taken from the largest coal unit. |
| `boiler_type` | text | | Pulverized coal, Fluidized bed or Unknown. |
| `primary_coal` | text | | Coal type with the most fuel burned: BIT (bituminous), SUB (subbituminous), LIG (lignite), WC (waste coal). |
| `avg_operating_year` | integer | year | Start year of the coal units, weighted by capacity. |
| `heat_rate_kcal_kwh` | integer | kcal/kWh | Heat rate in kcal/kWh (`heat_rate_btu_kwh * 0.252`). |
| `gap_vs_peer_btu_kwh` | integer | Btu/kWh | `heat_rate_btu_kwh - peer_median_btu_kwh`. |
| `fleet_rank` | integer | | 1 = lowest heat rate of all 151 plants. |
| `peer_rank` | integer | | 1 = lowest heat rate in its peer group. |
| `peer_size` | integer | | Number of plants in the peer group. |
| `peer_quartile` | integer | 1 to 4 | 1 = best 25% of the peer group, 4 = worst 25%. |

## dash_plant_savings.csv

How much fuel, CO2 and cost each plant would save in a year if it reached its peer median.

| Column | Type | Unit | Description |
|---|---|---|---|
| `excess_fuel_mmbtu` | decimal | MMBtu/year | `fuel_mmbtu - peer_median_btu_kwh * netgen_mwh / 1000`. Zero for plants at or below the median. |
| `excess_co2_tonnes` | decimal | tonnes/year | `excess_fuel_mmbtu * 95.52 / 1000`. Factor: EPA GHG Emission Factors Hub 2025. |
| `excess_fuel_cost_usd` | decimal | USD/year | `excess_fuel_mmbtu * 2.41`. Coal cost: EIA Electric Power Annual, Table 7.17. |
| `savings_rank` | integer | | 1 = largest excess fuel. All 77 plants with zero excess share rank 75. |
| `cumulative_share` | decimal | 0 to 1 | Running share of total excess fuel, from rank 1 down. Used for the Pareto view. |

## dash_monthly_performance.csv

Each plant's monthly heat rate compared with its own annual heat rate.

| Column | Type | Unit | Description |
|---|---|---|---|
| `month` | integer | 1 to 12 | Month of 2025. |
| `month_start` | date | | First day of the month, for time series charts. |
| `hours_in_month` | integer | hours | Days in the month x 24. |
| `monthly_cf` | decimal | 0 to 1 | `netgen_mwh / (capacity_mw * hours_in_month)`. |
| `monthly_heat_rate_btu_kwh` | integer | Btu/kWh | Heat rate in that month. Empty when the plant generated nothing. |
| `annual_heat_rate_btu_kwh` | integer | Btu/kWh | The plant's heat rate for the full year. |
| `pct_vs_annual` | decimal | % | `(monthly / annual - 1) * 100`. Positive means the month was less efficient than the plant's own average. |
| `load_band` | text | | `monthly_cf` grouped into 10% bands (00-10% to 80-100%), or Offline. |

### Notes

- **Offline months (88 rows)**: net generation was zero or negative, so heat rate cannot be calculated. In 8 of these rows EIA reported no data at all. They are kept in the table and excluded from the load band analysis.
- **Negative net generation**: a plant that is shut down still draws power for its own equipment, so EIA can report a small negative value.
