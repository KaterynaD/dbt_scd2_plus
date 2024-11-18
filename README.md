# Slowly Changing Dimension Type 2 (scd2) Custom Materialization dbt Package

## What does this dbt package do?

Create scd2

## How do I use the dbt package?

### Step 1: Prerequisites

To use this dbt package, you must have the following:

- A Snowflake, Redshift, PostgreSQL destination.

### Step 2: Install the package

Include the following facebook_ads_source package version in your packages.yml file.

packages:
  - package: dbt_scd2_plus

### Step 3: Configure model

### Step 4: Run dbt