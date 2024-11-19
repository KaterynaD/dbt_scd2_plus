{{ config(
   materialized='scd2_plus',
   
   unique_key='id',

   check_cols=['label','amount'],
   

   updated_at='SourceSystem_UpdatedDate'
   

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
where Staging_LoadDate='{{  var('loaddate') }}' /*to emulate ongoing load */
order by id, SourceSystem_UpdatedDate, Staging_LoadDate