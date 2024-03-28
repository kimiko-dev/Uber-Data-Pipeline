-- Retrieve the top 3 most common pickup dates for each base number in the raw_data_janjune_15 table, ranked by the number of pickups on each date?

WITH date_extract_cte AS (
    SELECT base.base_name AS `base_name`,
          raw.dispatching_base_num AS `dispatching_base_num`,
          DATE(raw.pickup_date) AS `pick_up_date`
    FROM airbyte_uber_data.raw_data_janjune_15 AS raw
    JOIN airbyte_uber_data.base_num_and_name AS base ON base.base_num = raw.dispatching_base_num
),
ranked_cte AS (
    SELECT base_name AS `Base Name`,
           dispatching_base_num AS `Dispatching Base Number`,
           RANK() OVER(PARTITION BY dispatching_base_num ORDER BY COUNT(*) DESC) AS `Rank`,
           COUNT(*) AS `Count`,
           pick_up_date AS `Pick Up Date`
    FROM date_extract_cte
    GROUP BY base_name, dispatching_base_num, pick_up_date
)

SELECT *
FROM ranked_cte
WHERE ranked_cte.rank IN (1,2,3)
ORDER BY ranked_cte.`Base NAME` ASC, ranked_cte.rank ASC