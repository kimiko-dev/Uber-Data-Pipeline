# Uber Data Pipeline

## _Table of Contents_

1. [Introduction](#1-introduction)

2. [Local Postgres Setup](#2-local-postgres-setup)

    2.1 [Creating the Database](#21-creating-the-database)

    2.2 [Populating the Database Tables](#22-populating-the-database-tables)

    2.3 [Configuring the Database for Airbyte](#23-configuring-the-database-for-airbyte)

3. [Google Cloud Platform Setup](#3-google-cloud-platform-setup)

    3.1 [Airbyte Service Account](#31-airbyte-service-account)

    3.2 [Creating a GCS Bucket for GCS Staging](#32-creating-a-gcs-bucket-for-gcs-staging)

    3.3 [Creating BigQuery Credentials for dbt](#33-creating-bigquery-credentials-for-dbt)

4. [Airbyte](#4-airbyte)

    4.1 [Setting Up the Postgres Source](#41-setting-up-the-postgres-source)

    4.2 [Setting Up the BigQuery Destination](#42-setting-up-the-bigquery-destination)

    4.3 [Syncing the Data](#43-syncing-the-data)

5. [dbt (Data Build Tool)](#5-dbt-data-build-tool)

    5.1 [dbt Set Up](#51-dbt-set-up)

    5.2 [dbt Models](#52-dbt-models)

6. [Dagster](#6-dagster)

    6.1 [Dagster Configuration](#61-dagster-configuration)

    6.2 [Testing the Pipeline](#62-testing-the-pipeline)

7. [Kubernetes](#7-kubernetes)

[TO DO](#to-do)

----

## 1. Introduction

This is still a work in progress. But so far, I have extracted and loaded over 14 million pieces of Uber ride data from a local postgres source into a Google BigQuery destination using Airbyte, transformed the data using dbt and orchestrate the whole ELT pipeline using dagster! I am currently working on implementing Kubernetes, and I will write the README.md once the project is fully completed.

## 2. Local Postgres Setup

In this stage, we will configure a local Postgres database, and populate it with the Uber Data.

### 2.1 Creating the Database

Upon launching the Postgres CLI using `sudo -u postgres psql`, we run the command `postgres=# CREATE DATABASE uber_data;` which creates the database named 'uber_data'. To check that this database has been succesfully created, we run `postgres=# \l`.

Now, we need to create tables inside the database. First, we change to the correct database by running `postgres=# \c uber_data`. Here, we will create 3 tables using:

```
uber_data=# CREATE TABLE taxi_zone_lookup (LocationID SMALLINT PRIMARY KEY, Borough TEXT, Zone TEXT);

uber_data=# CREATE TABLE base_num_and_name (base_num VARCHAR(6) PRIMARY KEY, base_name TEXT);

uber_data#= CREATE TABLE raw_data_janjune_15 (Dispatching_base_num VARCHAR(6) REFERENCES base_num_and_name(base_num), Pickup_date TIMESTAMP WITHOUT TIME ZONE, Affiliated_base_num VARCHAR(6) REFERENCES base_num_and_name(base_num), locationID SMALLINT REFERENCES taxi_zone_lookup(LocationID));
```

To check if the tables have been created, we run `uber_data=# \dt`.

Following this, we are ready to populate the tables with the data.

### 2.2 Populating the Database Tables

We need to create an interactive session (`sudo -u postgres psql` didn’t work (permission denied)). To do this, we run `psql -d postgres -U postgres`.

We now need to change to the 'uber_data' database, again by using the command `postgres=# \c uber_data`.

Let's copy the CSV data to the tables, we do this by using:

```
uber_data=# \copy taxi_zone_lookup(LocationID, Borough, Zone) FROM ‘/home/kimiko/Desktop/Uber_Data_Pipeline/taxi-zone-lookup.csv’ DELIMITER ‘,’ CSV HEADER;

uber_data=# \copy base_num_and_name(base_num, base_name) FROM ‘/home/kimiko/Desktop/Uber_Data_Pipeline/base-num-and-name.csv’ DELIMITER ‘,’ CSV HEADER;

uber_data=# \copy raw_data_janjune_15(Dispatching_base_num, Pickup_date, Affiliated_base_num, locationID) FROM ‘/home/kimiko/Desktop/Uber_Data_Pipeline/uber-raw-data-janjune-15.csv’ DELIMITER ‘,’ CSV HEADER;
```

To check we have populated the database correctly, we can run `uber_data=# SELECT COUNT(*) FROM <table name>;`, replacing '<table count>' for each table we created.

When the results have been returned, we can deduce that I have succesfully populated the source database! 

### 2.3 Configuring the Database for Airbyte

I will be using the CDC Update Method on Airbyte, so we will need to set up a few more things on Postgres.

_(In hind sight, I should have set up a new read-only user for airbyte to increase security!)_

We must grant Postgres the REPLICATION permissions, which can be done by running `postgres=# ALTER USER postgres REPLICATION;`

Now, we must enable logical replication on the database To do this, we configure the following parameters in the 'postgresql.conf' file for the Postgres Database:

```
wal_level = logical # WAL = Write-Ahead Logging, wal_level determines the level of info written to the WAL files.

max_wal_senders = 1 # the max num of of simultaneously active WAL sender processes.

max_replication_slots = 1 # limits the number of replication slots that can be concurrently  on the primary server, since airbyte is the only standby server requiring replication data from the primary server, setting 1 is appropriate.
```

Next, we need to create a replication slot on the postgres database, we can do this by running `SELECT pg_create_logical_replication_slot('airbyte_slot', 'pgoutput');`

Now for each table we wish to replicate with CDC, we simply execute:

```
ALTER TABLE taxi_zone_lookup REPLICA IDENTITY DEFUALT;
ALTER TABLE base_num_and_name REPLICA IDENTITY DEFUALT;
ALTER TABLE raw_data_janjune_15 REPLICA IDENTITY DEFUALT;
```

and create a postgres publication, using:

`CREATE PUBLICATION airbyte_publication FOR TABLE taxi_zone_lookup, base_num_and_name, raw_data_janjune_15;`

Completing this, we should be ready to add this as a source in Airbyte!

## 3. Google Cloud Platform Setup

I will be using Big Query as the destination for Airbyte, where we will be able to transform the data here using dbt. 

### 3.1 Airbyte Service Account

After making a new GCP project, we need to enable the IAM API alongside the BigQuery API.

To create a service account, we go here:

![creating_service_account_for_airbyte](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/creating_service_account_for_airbyte.png?raw=true)

and then press create serivce account, give it a service account name, which will then generate a service account ID.

We now need to add roles to this account, which are: Storage Object Admin, BigQuery User and BigQuery Data Editor.

We need to get the JSON key for the service account, to do this we select out newly created service account on the Service Accounts page on the IAM dashboard, click the keys button, then add key
and create a new key, key type is JSON. Then hit create.

### 3.2 Creating a GCS Bucket for GCS Staging

Since we will be using the GCS Staging Method as the Loading Method, we need to make a GCS Bucket. We first Navigate to the GCS console and create a new GCS Bucket, making sure that Protection Tools is set to none, and make sure the bucket does not have a retention policy.

Now, we must create HMAC key and access ID. To do so, go to GCS settings, select the Interoperability tab, click + Create a key for the service account, select the service account we made above and then hit create key. I then noted down the key and ID.

### 3.3 Creating BigQuery Credentials for dbt

First, we navigate to the credentials/wizard on GCP.

Then we configure:

![gcp_dbt_creds_1](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/gcp_dbt_creds_1.png?raw=true)

Click next, then write

![gcp_dbt_creds_2](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/gcp_dbt_creds_2.png?raw=true)

Then hit Create and Continue. After this, we need to assign the roles!

![gcp_dbt_creds_3](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/gcp_dbt_creds_3.png?raw=true)

Lastly, we need to generate a json file containing the service account key. We go to the service account page, select the appropriate account, which is 'dbt-user' in this case,

![gcp_dbt_json_1](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/gcp_dbt_json_1.png?raw=true)

then click add key, selecting the following:

![gcp_dbt_json_2](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/gcp_dbt_json_2.png?raw=true)

Now, we need to put this key in the correct folder, so dbt has the credentials to access the data and create new tables from models.

Which completes everything we need to do in order for dbt to work.

## 4. Airbyte

In this stage, we will be setting up a connector on Airbyte to migrate data from a local Postgres database to Google BigQuery.

### 4.1 Setting Up the Postgres Source

In order to do this, we must first start the local Posgres engine.

Then to start Airbyte, in the terminal we run: `cd airbyte` > `sudo ./run-ab-platform.sh` > and then go to `localhost:8000` in the browser, which takes us to the Airbyte UI.

After this, we configure the connector like so:

![airbyte_postgres_source](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/airbyte_postgres_source.png?raw=true)

We then hit test connection, and everything was all clear.

### 4.2 Setting Up the BigQuery Destination

Similar to before, we configure the destination like so:

![airbyte_bq_destination](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/airbyte_bq_destination.png?raw=true)

We then hit test connection, and everything was all clear.

### 4.3 Syncing the Data

After the test for the BigQuery destination passed, we are taken to a new connection page, like so:

![airbyte_sync_page](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/airbyte_sync_page.png?raw=true)

Here, I made the Schedule type Manual for the time being, as I will be using Dagster to schedule workflows.

I left the rest of the settings as defualt.

Then, at the bottom of the page, I pressed the setup connection button, which took me to the sync page.

I pressed the Sync now button, and after a few minutes, I was greeted with success.

![airbyte_success](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/airbyte_success.png?raw=true)

On BigQuery, we can see that the tables are there and have the correct data:

__The base_num_and_name Table on BigQuery:__

![bq_base_num_and_name](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/bq_base_num_and_name.png?raw=true)

__The raw_data_janjune_15 Table on BigQuery:__

![bq_raw_data_janjune_15](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/bq_raw_data_janjune_15.png?raw=true)

__The taxi_zone_lookup Table on BigQuery:__

![bq_taxi_zone_lookup](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/bq_taxi_zone_lookup.png?raw=true)

## 5 dbt (Data Build Tool)

dbt is the T part of the ELT pipeline, where I transformed the data into valuable insights.

### 5.1 dbt Set Up

First, we navigate to the directory where we want to build the dbt models.

In this directory, we create a new conda environment, and then run the command `pip install dbt-core dbt-bigquery`. Which successfully installs dbt for use in BigQuery.

Next, to initialise a new dbt project, we run `dbt init uber_transformations` which creates the 'uber_transformations' directory. We are met with a few configuration settings, which are: 

![dbt_3](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dbt_3.png?raw=true)

Then, we `cd uber_transformations` and then run `dbt debug` to get:

![dbt_4](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dbt_4.png?raw=true)

To test things further, I executed `dbt run`, but I was met with an error. This was due to an incorrect location. To fix this, I needed to change the 'profiles.yml' file in the '.dbt' directory:

![dbt_5](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dbt_5.png?raw=true)

I simply removed the 'location:' line, saved the file and then executed `dbt run` again, which gave no errors.

So, I headed to BigQuery and saw:

![dbt_6](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dbt_6.png?raw=true)

Which indicates success to me!! 

Since these were the defualt models, I will delete them and create my own dbt models so they can make tables, based on questions. 

In the 'uber_transformations/dbt_project.yml' file, I made sure to include:

![dbt_7](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dbt_7.png?raw=true)

as this is the new directory where the new queries will be written.

Ontop of this, I needed to configure the [sources.yml](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/dbt_Models/sources.yml) file so that the tables could be referenced correctly in the dbt models (and also for use in Dagster)

### 5.2 dbt Models

I came up with a few questions I can write queries on, they are:

Retrieve the pickup date, affiliated base name, borough, and zone for all records in the raw_data_janjune_15 table where the affiliated base name is Unter and Grun, and the pickup location is the Bronx borough. [unter_grun_pickups_in_bronx.sql](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/dbt_Models/unter_grun_pickups_in_bronx.sql)

__Result:__

![unter_grun_pickups_in_bronx](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/unter_grun_pickups_in_bronx.png?raw=true)

----

Calculate the total number of pickups for each base name in the raw_data_janjune_15 table, considering only records where the pickup date is within the month of May. [total_pickups_in_may_by_base.sql](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/dbt_Models/total_pickups_in_may_by_base.sql)

__Result:__

![total_pickups_in_may_by_base](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/total_pickups_in_may_by_base.png?raw=true)

----

Retrieve the top 3 base numbers along with their associated names from the base_num_and_name table based on the total number of pickups recorded in the raw_data_janjune_15 table. [top_3_base_names_by_total_pickups.sql](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/dbt_Models/top_3_base_names_by_total_pickups.sql)

__Result:__

![top_3_base_names_by_total_pickups](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/top_3_base_names_by_total_pickups.png?raw=true)

----

Retrieve the top 3 most common pickup dates for each base number in the raw_data_janjune_15 table, ranked by the number of pickups on each date? [top_3_pickup_dates_per_base.sql](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/dbt_Models/top_3_pickup_dates_per_base.sql)

__Result:__

![top_3_pickup_dates_per_base](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/top_3_pickup_dates_per_base.png?raw=true)

----

How does the pickup count (per month) for each base compare with the average pickup per month count across all bases? [pickup_count_vs_average_per_base_name.sql](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/dbt_Models/pickup_count_vs_average_per_base.sql)

__Result:__

![pick_up_count_vs_average_per_base_name](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/monthly_pick_up_count_vs_average_per_base_name.png?raw=true)

----

Determine the percentile of each base number based on the total number of pickups per month in the raw_data_janjune_15 table? [pickup_percentile_by_base_per_month.sql](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/dbt_Models/pickup_percentile_by_base_per_month.sql)

__Result:__

![pickup_percentile_by_base_per_month](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/pickup_percentile_by_base_per_month.png?raw=true)

## 6 Dagster

Dagster is used for orchestrating the whole ELT pipeline, which will be really important later on when testing the long term functionality of this pipeline.

### 6.1 Dagster Configuration

Firstly, we need to install Dagster into the conda environment using `pip install dagster dagster-dbt dagster-webserver dagster-airbyte`.

To create a new Dagster project, we need to change to the directory where the dbt project is located (more importantly, where the dbt_project.yml file is located) as Dagster will build the dbt assests when we run `dagster-dbt project scaffold --project-name uber_pipeline_orchestrator`.

After this, I changed directory to 'uber_pipeline_orchestrator' and ran `dagster dev`, which creates a UI on 'localhost:3000'.

I was greeted with this:

![dagster_1](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dagster_1.png?raw=true)

where we can see all of the dbt assets in Dagster.

Now, we need to change some files in order to set up the Airbyte assets in Dagster.

Next, I renamed the 'assets.py' file to [dbt.py](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Dagster_Files/dbt.py). However, since this file is referenced elsewhere we need to update it there. The file where it was referenced in is [definitions.py](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Dagster_Files/definitions.py). 

In the [constants.py](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Dagster_Files/constants.py) file, we set `AIRBYTE_CONNECTION_ID` and `AIRBYTE_CONFIG` accordingly.

I then created a new file called [airbyte.py](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Dagster_Files/airbyte.py), where I initialise an Airbyte resource and load the assets from the airbyte instance with a specific `key_prefix`.

Now, in the [definitions.py](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Dagster_Files/definitions.py) file, we add airbyte_assets after importing the [airbyte.py](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Dagster_Files/airbyte.py) file.

We can reload the Dagster UI to check if the new asset has been loaded correctly, we see its lineage here:

![dagster_2](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dagster_2.png?raw=true)

The next step is to connect the two assets by creating a job and a schedule, which (again) is done in the [definitions.py](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Dagster_Files/definitions.py) file. The DAG is set to be triggered daily, but I will be changing this later when I implement a more industry specific scenario.

After saving, we can reload the Dagster UI, where we see the streams:

![dagster_3](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dagster_3.png?raw=true)

### 6.2 Testing the Pipeline 

Let's do a dry run to verify that everything is working correctly! We need to make sure we start the postgres engine and the airbyte servver. 

We hit the materialize button, and we see that everything is starting to be materialized:

![dagster_4](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dagster_4.png?raw=true)

After letting Dagster do its thing, we can see that the pipeline has successfully been executed!

![dagster_5](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/dagster_5.png?raw=true)

We can see that this pipeline took around 15.5 mins to execute fully.

## 7 Kubernetes

## TO DO

- containerize the whole project in kubernetes
- simulate trip data as a near-real time stream
    - use kafka to consume this data, and produce it to a local postgres database (consumers and producers written in java!)
    - trigger the Dag to run every hour to load and transform the data (batch)
    - then containerize this improvement!! 