-- How does the pickup count (per month) for each base compare with the average pickup per month count across all bases?

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

monthly_counts_and_avg AS (
    SELECT month_extract.`Dispatching Base Name` AS `Dispatching Base Name`,
           month_extract.month_num,
           month_extract.Month AS `Month`,
           COUNT(*) AS `Monthly Count`,
           AVG(COUNT(*)) OVER (PARTITION BY month_extract.month) AS `Average for Month`
    FROM month_extract
    GROUP BY month_extract.`Dispatching Base Name`, month_extract.Month, month_extract.month_num
)

SELECT monthly_counts_and_avg.`Dispatching Base Name` AS `Dispatching Base Name`,
       monthly_counts_and_avg.month,
       monthly_counts_and_avg.`Monthly Count`,
       monthly_counts_and_avg.`Average for Month`,
       ((monthly_counts_and_avg.`Monthly Count` / monthly_counts_and_avg.`Average for Month`) - 1) * 100 AS `Percentage Difference`
FROM monthly_counts_and_avg
ORDER BY monthly_counts_and_avg.month_num ASC, monthly_counts_and_avg.`Monthly Count` DESC