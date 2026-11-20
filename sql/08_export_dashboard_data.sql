-- 08_export_dashboard_data.sql
-- Project: Heat rate analysis of US coal-fired power plants (EIA 2025)
-- Goal: Define the exact data behind the Looker Studio dashboard.

-- E1. Page 1: savings, ranking and location per plant
SELECT *
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_savings`
ORDER BY savings_rank, plant_name;

-- E2. Page 2: plant age and technology vs heat rate
SELECT *
FROM `rdw-data-projects.cfpp_eia.cfpp_plant_ranking`
ORDER BY peer_group, peer_rank;

-- E3. Page 2: monthly load vs heat rate per plant
SELECT *
FROM `rdw-data-projects.cfpp_eia.cfpp_monthly_performance`
ORDER BY plant_id, month;