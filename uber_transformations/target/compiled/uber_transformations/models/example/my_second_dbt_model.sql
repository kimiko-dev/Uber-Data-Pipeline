-- Use the `ref` function to select from other models

select *
from `uber-data-pipeline-417021`.`airbyte_uber_data`.`my_first_dbt_model`
where id = 1