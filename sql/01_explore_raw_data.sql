-- 01_explore_raw_data.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Goal: Explore raw EIA-923 data before cleaning. Every "Decision" below becomes a cleaning rule in 02_clean_cfpp_monthly.sql.
-- Input: raw_923_genfuel_2025 (18,889 rows; 1 row = plant x prime mover x fuel type, with monthly values as columns)

-- Q1. Which fuel types exist, and how many rows does each have?
SELECT
  Reported_Fuel_Type_Code,
  COUNT(*) AS row_count
FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
GROUP BY Reported_Fuel_Type_Code
ORDER BY row_count DESC;

-- Q2. Which prime movers are used by coal rows?
SELECT
  Reported_Prime_Mover,
  COUNT(*) AS row_count
FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
WHERE Reported_Fuel_Type_Code IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
GROUP BY Reported_Prime_Mover
ORDER BY row_count DESC;

-- Q3. Does one coal ST plant appear in more than one row?
SELECT
  Plant_Id,
  Plant_Name,
  COUNT(*) AS row_count
FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
WHERE
  Reported_Fuel_Type_Code IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
  AND Reported_Prime_Mover = 'ST'
GROUP BY Plant_Id, Plant_Name
ORDER BY row_count DESC;

-- Q4. How many coal ST rows have missing values in heat rate inputs?
SELECT
  COUNT(*) AS total_rows,
  COUNTIF(Net_Generation_Megawatthours IS NULL) AS missing_netgen_annual,
  COUNTIF(Elec_Fuel_Consumption_MMBtu IS NULL) AS missing_fuel_annual,
  COUNTIF(Netgen_January = '.') AS missing_netgen_jan,
  COUNTIF(Elec_MMBtu_January = '.') AS missing_fuel_jan
FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`
WHERE
  Reported_Fuel_Type_Code IN ('BIT', 'SUB', 'LIG', 'ANT', 'RC', 'WC')
  AND Reported_Prime_Mover = 'ST'
  AND Plant_Id <> 99999;
