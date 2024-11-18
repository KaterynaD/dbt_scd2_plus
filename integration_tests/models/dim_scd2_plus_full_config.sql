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

select *
from {{ source('dwh','scd2_plus_staging_data') }}
where (Staging_LoadDate='{{  var('loaddate') }}' or '{{  var('loaddate') }}' = '1900-01-01')
order by id, SourceSystem_UpdatedDate, Staging_LoadDate