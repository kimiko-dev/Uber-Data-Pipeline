-- Determine the percentile of each base number based on the total number of pickups per month in the raw_data_janjune_15 table?

WITH month_extract AS (
    SELECT base.base_name AS `Dispatching Base Name`,
           EXTRACT(MONTH FROM raw.pickup_date) AS `Month_num`,
           CASE
                WHEN EXTRACT(MONTH FROM raw.pickup_date) = 1 THEN 'January'
                WHEN EXTRACT(MONTH FROM raw.pickup_date) = 2 THEN 'February'
                WHEN EXTRACT(MONTH FROM raw.pickup_date) = 3 THEN 'March'
                WHEN EXTRACT(MONTH FROM raw.pickup_date) = 4 THEN 'April'
                WHEN EXTRACT(MONTH FROM raw.pickup_date) = 5 THEN 'May'
                WHEN EXTRACT(MONTH FROM raw.pickup_date) = 6 THEN 'June'
            END AS `Month`
    FROM {{ source("airbyte_uber_data", "raw_data_janjune_15") }} AS raw
    JOIN {{ source("airbyte_uber_data", "base_num_and_name") }} AS base ON base.base_num = raw.dispatching_base_num
),

counting_cte AS (
    SELECT month_extract.`Dispatching Base Name` AS `Dispatching Base Name`,
           month_extract.month_num AS month_num,
           month_extract.month AS `Month`,
           COUNT(*) AS `Count per Base per Month`,
           (SELECT COUNT(*) FROM month_extract AS sub WHERE sub.month = month_extract.month) AS `Count per Month`
    FROM month_extract
    GROUP BY month_extract.month, month_extract.`Dispatching Base Name`, month_extract.month_num
)

SELECT counting_cte.`Dispatching Base Name`,
       counting_cte.month,
       counting_cte.`Count per Base per Month`,
       (counting_cte.`Count per Base per Month` / counting_cte.`Count per Month`) * 100 AS `Percentile of Pick Ups`
FROM counting_cte
ORDER BY counting_cte.month_num ASC, counting_cte.`Count per Base per Month` DESC