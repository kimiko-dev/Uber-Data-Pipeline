import os
from pathlib import Path

from dagster_dbt import DbtCliResource
from dagster._utils import file_relative_path

dbt_project_dir = Path(__file__).joinpath("..", "..", "..").resolve()
dbt = DbtCliResource(project_dir=os.fspath(dbt_project_dir))

# If DAGSTER_DBT_PARSE_PROJECT_ON_LOAD is set, a manifest will be created at run time.
# Otherwise, we expect a manifest to be present in the project's target directory.
if os.getenv("DAGSTER_DBT_PARSE_PROJECT_ON_LOAD"):
    dbt_manifest_path = (
        dbt.cli(
            ["--quiet", "parse"],
            target_path=Path("target"),
        )
        .wait()
        .target_path.joinpath("manifest.json")
    )
else:
    dbt_manifest_path = dbt_project_dir.joinpath("target", "manifest.json")

# airbyte configs

AIRBYTE_CONNECTION_ID = os.environ.get("AIRBYTE_CONNECTION_ID", "50dfde7d-49de-48a8-b346-60a212e20b12" )

AIRBYTE_CONFIG = {
    "host" : os.environ.get("AIRBYTE_HOST", "localhost"),
    "port" : os.environ.get("AIRBYTE_PORT", "8000"),
    "username" : "airbyte",
    "password" : os.environ.get("AIRBYTE_PASSWORD")
}

# dbt configs

DBT_PROJECT_DIR = file_relative_path(__file__, "../../dbt_project")
DBT_PROFILES_DIR = file_relative_path(__file__, "../../dbt_project")
DBT_CONFIG = {"project_dir": DBT_PROJECT_DIR, "profiles_dir": DBT_PROFILES_DIR}