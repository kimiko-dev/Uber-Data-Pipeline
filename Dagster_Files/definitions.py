import os

from dagster import Definitions, ScheduleDefinition, define_asset_job
from dagster_dbt import DbtCliResource

from .airbyte import airbyte_assets
from .dbt import uber_transformations_dbt_assets
from .constants import dbt_project_dir
from .schedules import schedules

defs = Definitions(
    assets=[uber_transformations_dbt_assets, airbyte_assets],
    resources={
        "dbt": DbtCliResource(project_dir=os.fspath(dbt_project_dir)),
    },
    schedules=[
        ScheduleDefinition(
            job=define_asset_job("all_assets", selection="*"), cron_schedule="@daily" #updates all assets once a day
        ),
    ],
)