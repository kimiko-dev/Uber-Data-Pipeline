
  
    

    create or replace table `uber-data-pipeline-417021`.`airbyte_uber_data`.`total_number_of_pickups_in_may_by_base_name`
      
    
    

    OPTIONS()
    as (
      -- Calculate the total number of pickups for each base name in the raw_data_janjune_15 table, considering only records where the pickup date is within the month of May.

SELECT base.base_name AS `Dispatching Base Name`,
       COUNT(*) AS `Number of Pick Ups for Base`
FROM airbyte_uber_data.raw_data_janjune_15 AS raw
JOIN airbyte_uber_data.base_num_and_name AS base ON base.base_num = raw.dispatching_base_num
WHERE EXTRACT(MONTH FROM raw.pickup_date) = 5
GROUP BY base.base_name
ORDER BY COUNT(*) DESC
    );
  