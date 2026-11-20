-- 04_rank_plants.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Question: Which plants are the most and least efficient compared with plants of the same technology (peer group)?
-- Input: cfpp_plants (in_analysis = TRUE, peer_group <> 'Other')
-- Method: window functions rank each plant in the whole fleet and within its peer group; the peer median is the benchmark.

CREATE OR REPLACE TABLE `rdw-data-projects.cfpp_eia.cfpp_plant_ranking` AS
WITH base AS (
  SELECT
    plant_id,
    plant_name,
    plant_state,
    latitude,
    longitude,
    peer_group,
    steam_technology,
    boiler_type,
    primary_coal,
    capacity_mw,
    avg_operating_year,
    capacity_factor,
    netgen_mwh,
    fuel_mmbtu,
    heat_rate_btu_kwh                       AS hr,
    PERCENTILE_CONT(heat_rate_btu_kwh, 0.5)
      OVER (PARTITION BY peer_group)        AS peer_median_hr
  FROM `rdw-data-projects.cfpp_eia.cfpp_plants`
  WHERE in_analysis
    AND peer_group <> 'Other'
)
SELECT
  plant_id,
  plant_name,
  plant_state,
  latitude,
  longitude,
  peer_group,
  steam_technology,
  boiler_type,
  primary_coal,
  capacity_mw,
  avg_operating_year,
  ROUND(capacity_factor, 3)                           AS capacity_factor,
  netgen_mwh,
  fuel_mmbtu,
  ROUND(hr)                                           AS heat_rate_btu_kwh,
  ROUND(hr * 0.252)                                   AS heat_rate_kcal_kwh,
  ROUND(peer_median_hr)                               AS peer_median_btu_kwh,
  ROUND(hr - peer_median_hr)                          AS gap_vs_peer_btu_kwh,
  ROUND((hr / peer_median_hr - 1) * 100, 1)           AS gap_vs_peer_pct,
  RANK()   OVER (ORDER BY hr)                         AS fleet_rank,
  RANK()   OVER (PARTITION BY peer_group ORDER BY hr) AS peer_rank,
  COUNT(*) OVER (PARTITION BY peer_group)             AS peer_size,
  NTILE(4) OVER (PARTITION BY peer_group ORDER BY hr) AS peer_quartile
FROM base;


-- Check 1 (shape): one row per plant.
SELECT
  COUNT(*)                 AS row_count,
  COUNT(DISTINCT plant_id) AS plant_count
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`;


-- Check 2 (sample): Trimble County checked by hand against EIA-923.
-- Coal ST rows: fuel 69,737,061 + 10,067,127 = 79,804,188 MMBtu;
--               generation 6,878,279.6 + 996,915.58 = 7,875,195.18 MWh.
SELECT
  plant_name,
  peer_group,
  heat_rate_btu_kwh,
  heat_rate_kcal_kwh,
  peer_median_btu_kwh,
  gap_vs_peer_pct,
  peer_rank,
  peer_size,
  peer_quartile
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
WHERE plant_id = 6071;


-- Q1. How does heat rate differ between peer groups?
SELECT
  peer_group,
  COUNT(*)                                        AS plant_count,
  MIN(heat_rate_btu_kwh)                          AS best_btu_kwh,
  ANY_VALUE(peer_median_btu_kwh)                  AS median_btu_kwh,
  MAX(heat_rate_btu_kwh)                          AS worst_btu_kwh,
  MAX(heat_rate_btu_kwh) - MIN(heat_rate_btu_kwh) AS spread_btu_kwh
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
GROUP BY peer_group
ORDER BY median_btu_kwh;


-- Q2. Which plants are the 3 best and 3 worst in each peer group?
SELECT
  peer_group,
  peer_rank,
  plant_name,
  plant_state,
  heat_rate_btu_kwh,
  gap_vs_peer_pct,
  capacity_factor
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
WHERE peer_rank <= 3
   OR peer_rank > peer_size - 3
ORDER BY peer_group, peer_rank;