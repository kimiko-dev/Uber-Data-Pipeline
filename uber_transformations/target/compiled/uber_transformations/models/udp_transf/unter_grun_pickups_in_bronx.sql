-- Retrieve the pickup date, affiliated base name, borough, and zone for all records in the raw_data_janjune_15 table where the affiliated base name is Unter and Grun, and the pickup location is the Bronx borough.

SELECT raw.pickup_date AS `Pickup Date`,
       base.base_name AS `Base Name`,
       t_zone.borough AS `Borough`,
       t_zone.zone AS `Zone`
FROM `uber-data-pipeline-417021`.`airbyte_uber_data`.`raw_data_janjune_15` AS raw
JOIN `uber-data-pipeline-417021`.`airbyte_uber_data`.`base_num_and_name` AS base ON base.base_num = raw.affiliated_base_num
JOIN `uber-data-pipeline-417021`.`airbyte_uber_data`.`taxi_zone_lookup` AS t_zone ON t_zone.locationid = raw.locationid
WHERE base.base_name IN ('Unter', 'Grun') AND t_zone.Borough = 'Bronx'