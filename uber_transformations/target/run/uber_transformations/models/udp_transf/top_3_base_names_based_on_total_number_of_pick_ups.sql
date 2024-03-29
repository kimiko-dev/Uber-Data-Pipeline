
  
    

    create or replace table `uber-data-pipeline-417021`.`airbyte_uber_data`.`top_3_base_names_based_on_total_number_of_pick_ups`
      
    
    

    OPTIONS()
    as (
      -- Retrieve the top 3 base numbers along with their associated names from the base_num_and_name table based on the total number of pickups recorded in the raw_data_janjune_15 table.

SELECT base.base_num AS `Dispatching Base Number`,
       base.base_name AS `Base Name`,
       COUNT(raw.pickup_date) AS `Total Number of Pick Ups`
FROM airbyte_uber_data.raw_data_janjune_15 AS raw
JOIN airbyte_uber_data.base_num_and_name AS base ON base.base_num = raw.dispatching_base_num
GROUP BY base.base_num, base.base_name
ORDER BY COUNT(raw.pickup_date) DESC
LIMIT 3
    );
  