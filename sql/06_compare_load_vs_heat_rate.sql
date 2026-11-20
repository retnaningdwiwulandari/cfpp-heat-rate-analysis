-- 06_compare_load_vs_heat_rate.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Question: Does running at low load raise heat rate?
-- Problem: comparing plants mixes two effects: low load may raise heat rate, OR inefficient plants may simply be dispatched less?
-- Method  : compare each plant with ITSELF. For every plant-month,
--           calculate the monthly capacity factor and the % difference
--           between monthly and the plant's own annual heat rate.
--           Technology, age, fuel and design stay constant.
-- Input   : cfpp_monthly, cfpp_plants (in_analysis, capacity_factor_valid, peer_group <> 'Other')

CREATE OR REPLACE TABLE `rdw-data-projects.cfpp_eia.cfpp_monthly_performance` AS
WITH
-- 1. Plants in the analysis with stable capacity during 2025.
plants AS (
  SELECT
    plant_id,
    plant_name,
    plant_state,
    peer_group,
    capacity_mw,
    heat_rate_btu_kwh AS annual_hr
  FROM `rdw-data-projects.cfpp_eia.cfpp_plants`
  WHERE in_analysis
    AND capacity_factor_valid
    AND peer_group <> 'Other'
),

-- 2. Their 12 months. INNER JOIN keeps only months of these plants.
monthly AS (
  SELECT
    m.plant_id,
    p.plant_name,
    p.plant_state,
    p.peer_group,
    m.month,
    DATE(2025, m.month, 1)                                 AS month_start,
    p.capacity_mw,
    m.fuel_mmbtu,
    m.netgen_mwh,
    EXTRACT(DAY FROM LAST_DAY(DATE(2025, m.month, 1))) * 24 AS hours_in_month,
    p.annual_hr
  FROM `rdw-data-projects.cfpp_eia.cfpp_monthly` AS m
  INNER JOIN plants AS p
    ON p.plant_id = m.plant_id
),

-- 3. Monthly capacity factor and heat rate.
metrics AS (
  SELECT
    *,
    netgen_mwh / (capacity_mw * hours_in_month) AS monthly_cf,
    IF(netgen_mwh > 0 AND fuel_mmbtu > 0,
       fuel_mmbtu / netgen_mwh * 1000, NULL)    AS monthly_hr
  FROM monthly
)

-- 4. Compare each month with the plant's own annual heat rate.
SELECT
  plant_id,
  plant_name,
  plant_state,
  peer_group,
  month,
  month_start,
  capacity_mw,
  fuel_mmbtu,
  netgen_mwh,
  hours_in_month,
  ROUND(monthly_cf, 3)                         AS monthly_cf,
  ROUND(monthly_hr)                            AS monthly_heat_rate_btu_kwh,
  ROUND(annual_hr)                             AS annual_heat_rate_btu_kwh,
  ROUND((monthly_hr / annual_hr - 1) * 100, 1) AS pct_vs_annual,
  CASE
    WHEN monthly_hr IS NULL THEN 'Offline'
    WHEN monthly_cf < 0.1   THEN '00-10%'
    WHEN monthly_cf < 0.2   THEN '10-20%'
    WHEN monthly_cf < 0.3   THEN '20-30%'
    WHEN monthly_cf < 0.4   THEN '30-40%'
    WHEN monthly_cf < 0.5   THEN '40-50%'
    WHEN monthly_cf < 0.6   THEN '50-60%'
    WHEN monthly_cf < 0.7   THEN '60-70%'
    WHEN monthly_cf < 0.8   THEN '70-80%'
    ELSE '80-100%'
  END                                          AS load_band
FROM metrics;


-- Check 1 (shape): 151 plants x 12 months.
SELECT
  COUNT(*)                 AS row_count,
  COUNT(DISTINCT plant_id) AS plant_count
FROM `rdw-data-projects.cfpp_eia.cfpp_monthly_performance`;


-- Check 2 (physical plausibility): capacity factor cannot exceed 1, because a plant cannot generate more than its capacity.
SELECT
  MAX(monthly_cf)                AS max_monthly_cf,
  COUNTIF(load_band = 'Offline') AS offline_months
FROM `rdw-data-projects.cfpp_eia.cfpp_monthly_performance`;


-- Check 3 (sample): Trimble County, January, checked by hand.
-- Hours: 31 x 24 = 744.
SELECT
  plant_name,
  month,
  hours_in_month,
  monthly_cf,
  monthly_heat_rate_btu_kwh,
  annual_heat_rate_btu_kwh,
  pct_vs_annual,
  load_band
FROM `rdw-data-projects.cfpp_eia.cfpp_monthly_performance`
WHERE plant_id = 6071
  AND month = 1;


-- Q1. How does monthly heat rate change with load, within each plant?
WITH months AS (
  SELECT
    load_band,
    plant_id,
    pct_vs_annual,
    PERCENTILE_CONT(pct_vs_annual, 0.5)
      OVER (PARTITION BY load_band) AS band_median
  FROM `rdw-data-projects.cfpp_eia.cfpp_monthly_performance`
  WHERE load_band <> 'Offline'
)
SELECT
  load_band,
  COUNT(*)                         AS month_count,
  COUNT(DISTINCT plant_id)         AS plant_count,
  ROUND(ANY_VALUE(band_median), 1) AS median_pct_vs_annual
FROM months
GROUP BY load_band
ORDER BY load_band;


-- Q2. Is the pattern the same in every technology group?
WITH months AS (
  SELECT
    peer_group,
    pct_vs_annual,
    CASE
      WHEN monthly_cf < 0.2 THEN '1. Low (<20%)'
      WHEN monthly_cf < 0.4 THEN '2. Medium (20-40%)'
      ELSE '3. High (>=40%)'
    END AS load_group
  FROM `rdw-data-projects.cfpp_eia.cfpp_monthly_performance`
  WHERE load_band <> 'Offline'
),
with_median AS (
  SELECT
    *,
    PERCENTILE_CONT(pct_vs_annual, 0.5)
      OVER (PARTITION BY peer_group, load_group) AS cell_median
  FROM months
)
SELECT
  peer_group,
  load_group,
  COUNT(*)                         AS month_count,
  ROUND(ANY_VALUE(cell_median), 1) AS median_pct_vs_annual
FROM with_median
GROUP BY peer_group, load_group
ORDER BY peer_group, load_group;


-- Q3. How much extra fuel was burned in low-load months?
-- Method : extra fuel = actual fuel - fuel the plant would have used at its own annual heat rate (annual HR x generation / 1000).
SELECT
  COUNT(*)                                          AS low_load_months,
  COUNT(DISTINCT plant_id)                          AS plant_count,
  ROUND(SUM(fuel_mmbtu
            - annual_heat_rate_btu_kwh * netgen_mwh / 1000)) AS extra_fuel_mmbtu,
  ROUND(SUM(fuel_mmbtu - annual_heat_rate_btu_kwh * netgen_mwh / 1000)
        / SUM(fuel_mmbtu) * 100, 1)                 AS extra_fuel_pct
FROM `rdw-data-projects.cfpp_eia.cfpp_monthly_performance`
WHERE load_band IN ('00-10%', '10-20%');