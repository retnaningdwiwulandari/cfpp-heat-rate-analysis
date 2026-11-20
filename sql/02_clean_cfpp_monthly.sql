-- 02_clean_cfpp_monthly.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Goal: Build a clean plant-month table for coal-fired steam turbine plants. All later analysis reads from this table.
-- Input: raw_923_genfuel_2025 (1 row = plant x prime mover x fuel, with 12 monthly columns)
-- Rules: (see 01_explore_raw_data.sql)
--   1. Coal fuels only: BIT, SUB, LIG, ANT, RC, WC              (Q1)
--   2. Steam turbine only: ST                                   (Q2)
--   3. Drop Plant_Id 99999, a state-level estimate              (Q3)
--   4. Drop CHP plants: fuel is shared with process heat        (domain rule)
--   5. Convert '.' to NULL with SAFE_CAST                       (Q4)
--   6. Unpivot 12 monthly columns into 12 rows
--   7. Sum all coal rows to one row per plant per month         (Q3)

CREATE OR REPLACE TABLE `rdw-data-projects.cfpp_eia.cfpp_monthly` AS
WITH coal_rows AS (
  SELECT
    Plant_Id,
    Plant_Name,
    Plant_State,
    [
      STRUCT(1  AS month, SAFE_CAST(Elec_MMBtu_January   AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_January   AS FLOAT64) AS netgen_mwh),
      STRUCT(2  AS month, SAFE_CAST(Elec_MMBtu_February  AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_February  AS FLOAT64) AS netgen_mwh),
      STRUCT(3  AS month, SAFE_CAST(Elec_MMBtu_March     AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_March     AS FLOAT64) AS netgen_mwh),
      STRUCT(4  AS month, SAFE_CAST(Elec_MMBtu_April     AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_April     AS FLOAT64) AS netgen_mwh),
      STRUCT(5  AS month, SAFE_CAST(Elec_MMBtu_May       AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_May       AS FLOAT64) AS netgen_mwh),
      STRUCT(6  AS month, SAFE_CAST(Elec_MMBtu_June      AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_June      AS FLOAT64) AS netgen_mwh),
      STRUCT(7  AS month, SAFE_CAST(Elec_MMBtu_July      AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_July      AS FLOAT64) AS netgen_mwh),
      STRUCT(8  AS month, SAFE_CAST(Elec_MMBtu_August    AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_August    AS FLOAT64) AS netgen_mwh),
      STRUCT(9  AS month, SAFE_CAST(Elec_MMBtu_September AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_September AS FLOAT64) AS netgen_mwh),
      STRUCT(10 AS month, SAFE_CAST(Elec_MMBtu_October   AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_October   AS FLOAT64) AS netgen_mwh),
      STRUCT(11 AS month, SAFE_CAST(Elec_MMBtu_November  AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_November  AS FLOAT64) AS netgen_mwh),
      STRUCT(12 AS month, SAFE_CAST(Elec_MMBtu_December  AS FLOAT64) AS fuel_mmbtu, SAFE_CAST(Netgen_December  AS FLOAT64) AS netgen_mwh)
    ] AS months
  FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
  WHERE Reported_Fuel_Type_Code IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
    AND Reported_Prime_Mover = 'ST'
    AND Plant_Id <> 99999
    AND Combined_Heat_And_Power_Plant = FALSE
)
SELECT
  Plant_Id               AS plant_id,
  ANY_VALUE(Plant_Name)  AS plant_name,
  ANY_VALUE(Plant_State) AS plant_state,
  m.month,
  SUM(m.fuel_mmbtu)      AS fuel_mmbtu,
  SUM(m.netgen_mwh)      AS netgen_mwh
FROM coal_rows, UNNEST(months) AS m
GROUP BY plant_id, m.month;


-- Check 1 (shape): 1 row per plant per month.
SELECT
  COUNT(*)                 AS row_count,
  COUNT(DISTINCT plant_id) AS plant_count
FROM `rdw-data-projects.cfpp_eia.cfpp_monthly`;


-- Check 2 (total): the 12 monthly values must add up to the raw annual total.
WITH totals AS (
  SELECT
    (SELECT SUM(netgen_mwh)
     FROM `rdw-data-projects.cfpp_eia.cfpp_monthly`) AS monthly_sum_mwh,
    (SELECT SUM(Net_Generation_Megawatthours)
     FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
     WHERE Reported_Fuel_Type_Code IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
       AND Reported_Prime_Mover = 'ST'
       AND Plant_Id <> 99999
       AND Combined_Heat_And_Power_Plant = FALSE)     AS annual_sum_mwh
)
SELECT
  ROUND(monthly_sum_mwh, 2)                                           AS monthly_sum_mwh,
  ROUND(annual_sum_mwh, 2)                                            AS annual_sum_mwh,
  ROUND(monthly_sum_mwh - annual_sum_mwh, 2)                          AS diff_mwh,
  ROUND((monthly_sum_mwh - annual_sum_mwh) / annual_sum_mwh * 100, 7) AS diff_pct
FROM totals;


-- Check 3 (sample): one plant-month checked by hand against the raw file (example below: Trimble County, January = BIT + SUB + RC + WC rows).
SELECT
  plant_id,
  plant_name,
  month,
  fuel_mmbtu,
  netgen_mwh
FROM `rdw-data-projects.cfpp_eia.cfpp_monthly`
WHERE plant_id = 6071
  AND month = 1;