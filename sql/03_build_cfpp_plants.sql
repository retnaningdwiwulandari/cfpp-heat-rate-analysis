-- 03_build_cfpp_plants.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Goal: Build one row per coal plant with annual heat rate, unit details from EIA-860, peer group, and analysis flags.
-- Input: cfpp_monthly, raw_923_genfuel_2025, raw_860_generator_operable_2025, raw_860_generator_retired_2025, raw_860_plant_2025.
-- Key rule: every source is summarized to 1 row per plant BEFORE the join, so the join cannot duplicate rows.
-- Flags: in_analysis = has heat rate AND coal share >= 90%
--                      AND net generation >= 100,000 MWh
--                      capacity_factor_valid = has EIA-860 capacity AND no coal unit retired during 2025
-- Limits: technology is assigned per plant (largest coal unit), not per unit; capacity factor uses nameplate capacity.

CREATE OR REPLACE TABLE `rdw-data-projects.cfpp_eia.cfpp_plants` AS
WITH
-- 1. Annual coal fuel and generation per plant from the clean table.
plant_annual AS (
  SELECT
    plant_id,
    ANY_VALUE(plant_name)  AS plant_name,
    ANY_VALUE(plant_state) AS plant_state,
    SUM(fuel_mmbtu)        AS fuel_mmbtu,
    SUM(netgen_mwh)        AS netgen_mwh
  FROM `rdw-data-projects.cfpp_eia.cfpp_monthly`
  GROUP BY plant_id
),

-- 2. Main coal type per plant: the coal with the largest fuel use.
primary_coal AS (
  SELECT
    Plant_Id AS plant_id,
    ANY_VALUE(Reported_Fuel_Type_Code
              HAVING MAX Elec_Fuel_Consumption_MMBtu) AS primary_coal
  FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
  WHERE Reported_Fuel_Type_Code IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
    AND Reported_Prime_Mover = 'ST'
    AND Plant_Id <> 99999
    AND Combined_Heat_And_Power_Plant = FALSE
  GROUP BY Plant_Id
),

-- 3. Steam turbine generation from ALL fuels (coal + gas + oil), used to measure how coal-dominant each plant is.
st_all_fuels AS (
  SELECT
    Plant_Id                          AS plant_id,
    SUM(Net_Generation_Megawatthours) AS st_netgen_all_fuels_mwh
  FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
  WHERE Reported_Prime_Mover = 'ST'
  GROUP BY Plant_Id
),

-- 4. Coal-capable steam units from EIA-860.
coal_units AS (
  SELECT
    Plant_Code            AS plant_id,
    Nameplate_Capacity_MW AS capacity_mw,
    Operating_Year        AS operating_year,
    CASE
      WHEN Ultrasupercritical_Technology = TRUE THEN 'Ultra-supercritical'
      WHEN Supercritical_Technology      = TRUE THEN 'Supercritical'
      WHEN Subcritical_Technology        = TRUE THEN 'Subcritical'
      ELSE 'Unknown'
    END AS steam_technology,
    CASE
      WHEN Fluidized_Bed_Technology   = TRUE THEN 'Fluidized bed'
      WHEN Pulverized_Coal_Technology = TRUE THEN 'Pulverized coal'
      WHEN Stoker_Technology          = TRUE THEN 'Stoker'
      ELSE 'Unknown'
    END AS boiler_type
  FROM `rdw-data-projects.cfpp_eia.raw_860_generator_operable_2025`
  WHERE Prime_Mover = 'ST'
    AND (Energy_Source_1 IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
      OR Energy_Source_2 IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC'))
),

-- 5. Units summarized to 1 row per plant.
plant_units AS (
  SELECT
    plant_id,
    SUM(capacity_mw) AS capacity_mw,
    COUNT(*)         AS unit_count,
    -- capacity-weighted average operating year
    CAST(ROUND(SUM(capacity_mw * operating_year) / SUM(capacity_mw)) AS INT64)
                     AS avg_operating_year,
    -- technology of the largest coal unit
    ANY_VALUE(steam_technology HAVING MAX capacity_mw) AS steam_technology,
    ANY_VALUE(boiler_type      HAVING MAX capacity_mw) AS boiler_type
  FROM coal_units
  GROUP BY plant_id
),

-- 6. Plants that retired a coal unit during 2025 (capacity changed mid-year). 
retired_2025 AS (
  SELECT DISTINCT
    Plant_Code AS plant_id
  FROM `rdw-data-projects.cfpp_eia.raw_860_generator_retired_2025`
  WHERE Prime_Mover = 'ST'
    AND (Energy_Source_1 IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
      OR Energy_Source_2 IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC'))
    AND SAFE_CAST(Retirement_Year AS INT64) = 2025
),

-- 7. Join everything. Every input above has exactly 1 row per plant.
joined AS (
  SELECT
    a.plant_id,
    a.plant_name,
    a.plant_state,
    SAFE_CAST(p.Latitude  AS FLOAT64)                    AS latitude,
    SAFE_CAST(p.Longitude AS FLOAT64)                    AS longitude,
    p.Sector_Name                                        AS sector_name,
    c.primary_coal,
    u.capacity_mw,
    u.unit_count,
    u.avg_operating_year,
    2025 - u.avg_operating_year                          AS avg_age_years,
    u.steam_technology,
    u.boiler_type,
    a.fuel_mmbtu,
    a.netgen_mwh,
    SAFE_DIVIDE(a.netgen_mwh, s.st_netgen_all_fuels_mwh) AS coal_share,
    IF(a.netgen_mwh > 0 AND a.fuel_mmbtu > 0,
       a.fuel_mmbtu / a.netgen_mwh * 1000, NULL)         AS heat_rate_btu_kwh,
    SAFE_DIVIDE(a.netgen_mwh, u.capacity_mw * 8760)      AS capacity_factor,
    r.plant_id IS NOT NULL                               AS has_unit_retired_2025
  FROM plant_annual AS a
  LEFT JOIN primary_coal AS c ON c.plant_id = a.plant_id
  LEFT JOIN st_all_fuels AS s ON s.plant_id = a.plant_id
  LEFT JOIN plant_units  AS u ON u.plant_id = a.plant_id
  LEFT JOIN retired_2025 AS r ON r.plant_id = a.plant_id
  LEFT JOIN `rdw-data-projects.cfpp_eia.raw_860_plant_2025` AS p
    ON p.Plant_Code = a.plant_id
)

-- 8. Add peer group and analysis flags.
SELECT
  *,
  CASE
    WHEN boiler_type = 'Fluidized bed'                                THEN 'Fluidized bed'
    WHEN primary_coal = 'LIG'                                         THEN 'Lignite'
    WHEN steam_technology IN ('Supercritical', 'Ultra-supercritical') THEN 'Supercritical'
    WHEN steam_technology = 'Subcritical'                             THEN 'Subcritical'
    ELSE 'Other'
  END AS peer_group,
  IFNULL(heat_rate_btu_kwh IS NOT NULL
         AND coal_share >= 0.9
         AND netgen_mwh >= 100000, FALSE)      AS in_analysis,
  IFNULL(capacity_mw IS NOT NULL
         AND NOT has_unit_retired_2025, FALSE) AS capacity_factor_valid
FROM joined;


-- Check 1 (shape): the join must not duplicate plants.
SELECT
  COUNT(*)                 AS row_count,
  COUNT(DISTINCT plant_id) AS plant_count
FROM `rdw-data-projects.cfpp_eia.cfpp_plants`;


-- Check 2 (total): total generation must match the monthly table.
WITH totals AS (
  SELECT
    (SELECT SUM(netgen_mwh) FROM `rdw-data-projects.cfpp_eia.cfpp_plants`)  AS plants_sum_mwh,
    (SELECT SUM(netgen_mwh) FROM `rdw-data-projects.cfpp_eia.cfpp_monthly`) AS monthly_sum_mwh
)
SELECT
  ROUND(plants_sum_mwh, 2)                   AS plants_sum_mwh,
  ROUND(monthly_sum_mwh, 2)                  AS monthly_sum_mwh,
  ROUND(plants_sum_mwh - monthly_sum_mwh, 2) AS diff_mwh
FROM totals;

-- Check 3 (distribution): plants per peer group, analysis set only.
SELECT
  peer_group,
  COUNT(*)   AS plant_count
FROM `rdw-data-projects.cfpp_eia.cfpp_plants`
WHERE in_analysis
GROUP BY peer_group
ORDER BY plant_count DESC;

-- Check 4 (completeness): plants without location data. They are coal docks and storage terminals that report coal stocks to
--                         EIA-923 but generate nothing, so none enter the analysis.
SELECT
  COUNTIF(latitude IS NULL)                 AS missing_location,
  COUNTIF(latitude IS NULL AND in_analysis) AS missing_location_in_analysis
FROM `rdw-data-projects.cfpp_eia.cfpp_plants`;


-- Check 5 (sample): Trimble County checked by hand against EIA-860.
-- Coal units: unit 1 (566.1 MW, 1990, subcritical) and unit 2 (834 MW, 2011, supercritical).
SELECT
  plant_id,
  plant_name,
  primary_coal,
  capacity_mw,
  unit_count,
  avg_operating_year,
  steam_technology,
  ROUND(coal_share, 3)        AS coal_share,
  ROUND(heat_rate_btu_kwh)    AS heat_rate_btu_kwh,
  ROUND(capacity_factor, 3)   AS capacity_factor,
  peer_group,
  in_analysis
FROM `rdw-data-projects.cfpp_eia.cfpp_plants`
WHERE plant_id = 6071;
