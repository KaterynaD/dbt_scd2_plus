# Slowly Changing Dimension Type 2 (scd2) Custom Materialization dbt Package

## What does this dbt package do?

This DBT package provides a materialization that builds advanced version of slowly changing dimension type 2  (scd2):
- A new record is added if there is a change in **check_cols** column list like it's done in the original Check dbt snapshot strategy.
- It uses **updated_at** column like in the original Timestamp dbt snapshot strategy to define the time limits when a record is valid (valid_from - valid_to columns). 
- You can load data in a batch like on e time, historical, initial load. The batch may contain several version of the same entity or even duplicates (the same **updated_at** and **unique_key** ). There is a deduplication embedded in the logic.
- If there is not a complete duplicate record (the same **updated_at** and **unique_key** but different **check_cols** ), the logic can use **loaded_at**(data loaded in a staging area timestamp) to update **check_cols** with most recent known values.
- The dimension is loaded incrementally. It means, if an underlying table does not exist, it's created from the first data batch. Otherwise, new records are inserted and existing updated if needed.
- The load process supports * backdated * transactions. It means, if there is already an entity version in the dimension for a specific time period and later, you receive in your staging area, a new version of the same entity for the part of the existing time period (change in a past, already loaded data), the existing record in the dimension must be split in 2. See example below
- Along with Kimball Type II setting in **check_cols** , you can configure Kimbal Type I setting in **punch_thru_cols** column list. These attributes in **all** dimension record versions are updated.
-**update_cols** column lists are updated only in the**last**dimension recordversion.
- scd2_plus materialized dimension has these service columns:
  - Dimension primary key as a combination of **unique_key** and **updated_at** . It's **scd_id** by default, but can be configured in **scd_id_col_name** 
  - Dimension record version **start** timestamp is **valid_from** by default, but can be customized in**scd_valid_from_col_name** 
  - Dimension record version **end** timestamp is **valid_from** by default, but can be customized in  **scd_valid_to_col_name** 
  - Dimension record version **ordering number** is **record_version** by default and custom column name can be configured in **scd_record_version_col_name** 
  - Data loaded in a record at **LoadDate** timestamp, customizable in **scd_loaddate_col_name** 
  - Data updated in a record at **UpdateDate** , customizable in **scd_updatedate_col_name** 
- **LoadDate** and **UpdateDate** can be populated from **loaddate** provided, if you want to have the same timestamp all your models or generated in the macros now() timestamp.
- The first entity record **valid_from** in the dimension can be teh first **updated_at** (default) or any timestamp you provide in **scd_valid_from_min_date** . Setting **scd_valid_from_min_date** to **1900-01-01**allows to use the first entity record in a fact table transactions with transaction dates before the entity first**updated_at**value e.g. before the entity was born.
- The last entity record **valid_to** in the dimension is **NULL** by default, but you can override it with **scd_valid_to_max_date** . Setting **scd_valid_to_max_date** to something like **3000-01-01** will simplify joining fact records to the dimension.
- There is also **scd2_plus_validation** test to check consistancy in **valid_from** and **valid_to** . It means no gaps in or intesection of versions periods in an entity. If not a default names are set in **scd_valid_from_col_name** , **scd_valid_to_col_name** and **scd_record_version_col_name** , they should be specified in the test.

## How do I use the dbt package?

### Step 1: Prerequisites

To use this dbt package, you must have the following:

- A Snowflake, Redshift, PostgreSQL destination.
- Staging data with a **unique key** and **updated** columns

### Step 2: Install the package

Include  dbt_scd2_plus package  in your packages.yml file.

```
packages:
  - git: "https://github.com/KaterunaD/dbt_scd2_plus"
```
### Step 3: Configure model

** Minimum configuration** 

```
{{ config(
   materialized='scd2_plus',
   
   unique_key='id',

   check_cols=['label','amount'],
   updated_at='SourceSystem_UpdatedDate',
  
) }}

select 
id,
label,
amount,
SourceSystem_UpdatedDate
from {{ source('dwh','scd2_plus_staging_data') }}
order by id, SourceSystem_UpdatedDate

```

** More customization** 

```
{{ config(
   materialized='scd2_plus',
   
   unique_key='id',

   check_cols=['label','amount'],
   punch_thru_cols=['name','birthdayDate'],
   update_cols=['description'],

   updated_at='SourceSystem_UpdatedDate',
   loaded_at='Staging_LoadDate',

   loaddate = var('loaddate'),

   scd_id_col_name = 'component_id',
   scd_valid_from_col_name='valid_from_dt',
   scd_valid_to_col_name='valid_to_dt',
   scd_record_version_col_name='version',
   scd_loaddate_col_name='loaded_at',
   scd_updatedate_col_name='updated_at',
   
   scd_valid_to_min_date='1900-01-01',
   scd_valid_to_max_date='3000-01-01'

   

) }}

select 
id,
name,
label,
amount,
birthdayDate,
description,
SourceSystem_UpdatedDate,
Staging_LoadDate
from {{ source('dwh','scd2_plus_staging_data') }}
where (Staging_LoadDate='{{  var('loaddate') }}' or '{{  var('loaddate') }}' = '1900-01-01')
order by id, SourceSystem_UpdatedDate, Staging_LoadDate

```
### Step 4: Add test

In a schema.yml

```
models:
  - name: dim_scd2_plus_full_config
    tests:
      - dbt_scd2_plus.scd2_plus_validation:
          unique_key: 'id'
          scd_valid_from_col_name: 'valid_from_dt'
          scd_valid_to_col_name:  'valid_to_dt'

```

### Step 5: Run dbt

```
dbt run
```
### Step 5: Run test

```
dbt test
```