-- 07_estimate_fuel_savings.sql
-- Project : Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Question: How much fuel, CO2 and cost could be saved if every plant above its peer median reached that median?
-- Input   : cfpp_plant_ranking (151 plants)
-- Method  : excess fuel = actual fuel - fuel at the peer median heat
--           rate; plants at or below the median contribute 0.
--           The median is used because half of similar plants already
--           achieve it, so the target is proven to be reachable.
-- Assumptions (external datas, see the assumptions CTE):
--   CO2 factor 95.52 kg/MMBtu  EPA GHG Emission Factors Hub 2025, coal, mixed (electric power sector)
--   Coal cost  2.41 USD/MMBtu  EIA Electric Power Annual, Table 7.17, 2025, electric power sector average

CREATE OR REPLACE TABLE `rdw-data-projects.cfpp_eia.cfpp_plant_savings` AS
WITH
-- 1. External assumptions, kept in one place with their sources.
assumptions AS (
  SELECT
    95.52 AS co2_kg_per_mmbtu,         -- EPA GHG Emission Factors Hub 2025
    2.41  AS coal_cost_usd_per_mmbtu   -- EIA Electric Power Annual, Table 7.17
),

-- 2. Excess fuel versus the peer median (0 if at or below the median).
excess AS (
  SELECT
    plant_id,
    plant_name,
    plant_state,
    latitude,
    longitude,
    peer_group,
    capacity_factor,
    netgen_mwh,
    fuel_mmbtu,
    heat_rate_btu_kwh,
    peer_median_btu_kwh,
    gap_vs_peer_pct,
    IF(gap_vs_peer_btu_kwh > 0,
       fuel_mmbtu - peer_median_btu_kwh * netgen_mwh / 1000,
       0) AS excess_fuel_mmbtu
  FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
)

-- 3. Convert to CO2 and cost; rank plants and build the Pareto curve.
SELECT
  e.plant_id,
  e.plant_name,
  e.plant_state,
  e.latitude,
  e.longitude,
  e.peer_group,
  e.capacity_factor,
  e.netgen_mwh,
  e.fuel_mmbtu,
  e.heat_rate_btu_kwh,
  e.peer_median_btu_kwh,
  e.gap_vs_peer_pct,
  ROUND(e.excess_fuel_mmbtu)                             AS excess_fuel_mmbtu,
  ROUND(e.excess_fuel_mmbtu * a.co2_kg_per_mmbtu / 1000) AS excess_co2_tonnes,
  ROUND(e.excess_fuel_mmbtu * a.coal_cost_usd_per_mmbtu) AS excess_fuel_cost_usd,
  RANK() OVER (ORDER BY e.excess_fuel_mmbtu DESC)        AS savings_rank,
  ROUND(
    SUM(e.excess_fuel_mmbtu) OVER (
      ORDER BY e.excess_fuel_mmbtu DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    / SUM(e.excess_fuel_mmbtu) OVER (), 3)               AS cumulative_share
FROM excess AS e
CROSS JOIN assumptions AS a;


-- Check 1 (shape): one row per plant.
SELECT
  COUNT(*)                 AS row_count,
  COUNT(DISTINCT plant_id) AS plant_count
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`;


-- Check 2 (logic): only plants above their peer median have excess fuel. 
SELECT
  COUNTIF(excess_fuel_mmbtu > 0)                         AS plants_with_excess,
  COUNTIF(excess_fuel_mmbtu > 0
          AND heat_rate_btu_kwh <= peer_median_btu_kwh)  AS wrong_sign
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`;


-- Check 3 (sample): Powerton checked by hand.
-- Fuel at median: 10,196 x 3,354,454.07 / 1000 = 34,202,014 MMBtu.
SELECT
  plant_name,
  fuel_mmbtu,
  netgen_mwh,
  peer_median_btu_kwh,
  excess_fuel_mmbtu,
  excess_co2_tonnes,
  excess_fuel_cost_usd
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`
WHERE plant_id = 879;


-- Q1. What is the total savings potential, under two scenarios?
SELECT
  COUNTIF(excess_fuel_mmbtu > 0)                           AS plants_above_median,
  ROUND(SUM(excess_fuel_mmbtu) / 1e6, 1)                   AS full_gap_fuel_million_mmbtu,
  ROUND(SUM(excess_fuel_mmbtu) / SUM(fuel_mmbtu) * 100, 1) AS full_gap_pct_of_fleet_fuel,
  ROUND(SUM(excess_co2_tonnes) / 1e6, 2)                   AS full_gap_co2_million_tonnes,
  ROUND(SUM(excess_fuel_cost_usd) / 1e6, 1)                AS full_gap_cost_million_usd,
  ROUND(SUM(excess_co2_tonnes) * 0.5 / 1e6, 2)             AS half_gap_co2_million_tonnes,
  ROUND(SUM(excess_fuel_cost_usd) * 0.5 / 1e6, 1)          AS half_gap_cost_million_usd
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`;


-- Q2. Which 10 plants have the largest savings potential?
SELECT
  savings_rank,
  plant_name,
  plant_state,
  peer_group,
  heat_rate_btu_kwh,
  peer_median_btu_kwh,
  gap_vs_peer_pct,
  capacity_factor,
  ROUND(excess_fuel_mmbtu / 1e6, 2)    AS excess_fuel_million_mmbtu,
  ROUND(excess_co2_tonnes / 1e3)       AS excess_co2_thousand_tonnes,
  ROUND(excess_fuel_cost_usd / 1e6, 1) AS excess_cost_million_usd
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`
WHERE savings_rank <= 10
ORDER BY savings_rank;


-- Q3. Is the savings potential concentrated in a few plants (Pareto)?
SELECT
  COUNTIF(excess_fuel_mmbtu > 0)                AS plants_above_median,
  MIN(IF(cumulative_share >= 0.5, savings_rank, NULL)) AS plants_for_50_pct,
  MIN(IF(cumulative_share >= 0.8, savings_rank, NULL)) AS plants_for_80_pct
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`;


-- Q4. How is the potential split between peer groups?
SELECT
  peer_group,
  COUNTIF(excess_fuel_mmbtu > 0)                           AS plants_above_median,
  ROUND(SUM(excess_fuel_mmbtu) / 1e6, 1)                   AS excess_fuel_million_mmbtu,
  ROUND(SUM(excess_fuel_mmbtu) / SUM(fuel_mmbtu) * 100, 1) AS pct_of_group_fuel
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`
GROUP BY peer_group
ORDER BY excess_fuel_million_mmbtu DESC;