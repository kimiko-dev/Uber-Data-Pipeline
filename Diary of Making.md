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

## 1. Introduction

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

### 3.3 Creating BigQuery Credentials for DBT

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

I pressed the Sync now button, and after a few minutes, I was greeted with a success.

![airbyte_success](https://github.com/kimiko-dev/Uber-Data-Pipeline/blob/master/Images/airbyte_success.png?raw=true)