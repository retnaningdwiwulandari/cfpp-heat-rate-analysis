-- 00_check_row_counts.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Goal: Verify that all four CSV files were loaded into BigQuery completely before any exploration or cleaning.
-- Method: count rows in each table and compare with the source file.

SELECT
  'raw_923_genfuel_2025'            AS table_name,
  COUNT(*)                          AS row_count
FROM `rdw-data-projects.cfpp_eia.raw_923_genfuel_2025`

UNION ALL

SELECT
  'raw_860_plant_2025'              AS table_name,
  COUNT(*)                          AS row_count
FROM `rdw-data-projects.cfpp_eia.raw_860_plant_2025`

UNION ALL

SELECT
  'raw_860_generator_operable_2025' AS table_name,
  COUNT(*)                          AS row_count
FROM `rdw-data-projects.cfpp_eia.raw_860_generator_operable_2025`

UNION ALL

SELECT
  'raw_860_generator_retired_2025'  AS table_name,
  COUNT(*)                          AS row_count
FROM `rdw-data-projects.cfpp_eia.raw_860_generator_retired_2025`;