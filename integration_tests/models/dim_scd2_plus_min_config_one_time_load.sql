/*see minimum requred configuration in schema.yml */
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
order by id, SourceSystem_UpdatedDate, Staging_LoadDate