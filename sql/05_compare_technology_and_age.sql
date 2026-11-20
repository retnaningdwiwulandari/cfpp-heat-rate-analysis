-- 05_compare_technology_and_age.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Question: Are older plants less efficient? Does the technology gap hold across plant generations?
-- Input: cfpp_plant_ranking (151 plants)
-- Method: group plants into eras by capacity-weighted operating year;
--         compare median (typical plant) and generation-weighted heat
--         rate (fleet efficiency); compare eras within the same
--         technology to remove the effect of technology mix.
-- Limits: survivorship bias: the least efficient old plants have
--         already retired, so results describe plants still running
--         in 2025 only. Small cells (n < 5) are not reliable.
-- Note: heat_rate_btu_kwh in the ranking table is rounded, so medians may differ by 1 Btu/kWh from unrounded values.

-- Q1. Do older plants have higher heat rates?
WITH plants AS (
  SELECT
    heat_rate_btu_kwh,
    fuel_mmbtu,
    netgen_mwh,
    CASE
      WHEN avg_operating_year < 1970 THEN '1. Before 1970'
      WHEN avg_operating_year < 1980 THEN '2. 1970-1979'
      WHEN avg_operating_year < 1990 THEN '3. 1980-1989'
      ELSE '4. 1990 and later'
    END AS era
  FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
),
with_median AS (
  SELECT
    *,
    PERCENTILE_CONT(heat_rate_btu_kwh, 0.5)
      OVER (PARTITION BY era) AS era_median
  FROM plants
)
SELECT
  era,
  COUNT(*)                                       AS plant_count,
  ROUND(ANY_VALUE(era_median))                   AS median_btu_kwh,
  ROUND(SUM(fuel_mmbtu) / SUM(netgen_mwh) * 1000) AS weighted_btu_kwh
FROM with_median
GROUP BY era
ORDER BY era;


-- Q2. Within the same technology, does age matter?
WITH plants AS (
  SELECT
    peer_group,
    heat_rate_btu_kwh,
    CASE
      WHEN avg_operating_year < 1970 THEN '1. Before 1970'
      WHEN avg_operating_year < 1980 THEN '2. 1970-1979'
      WHEN avg_operating_year < 1990 THEN '3. 1980-1989'
      ELSE '4. 1990 and later'
    END AS era
  FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
  WHERE peer_group IN ('Subcritical', 'Supercritical')
),
with_median AS (
  SELECT
    *,
    PERCENTILE_CONT(heat_rate_btu_kwh, 0.5)
      OVER (PARTITION BY era, peer_group) AS cell_median
  FROM plants
)
SELECT
  era,
  peer_group,
  COUNT(*)                      AS plant_count,
  ROUND(ANY_VALUE(cell_median)) AS median_btu_kwh
FROM with_median
GROUP BY era, peer_group
ORDER BY era, peer_group;


-- Q3. How strongly do age and capacity factor relate to heat rate?
SELECT
  peer_group,
  COUNT(*)                                                       AS plant_count,
  ROUND(CORR(2025 - avg_operating_year, heat_rate_btu_kwh), 2)  AS corr_age_heat_rate,
  ROUND(CORR(capacity_factor, heat_rate_btu_kwh), 2)            AS corr_cf_heat_rate
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
GROUP BY peer_group
ORDER BY plant_count DESC;