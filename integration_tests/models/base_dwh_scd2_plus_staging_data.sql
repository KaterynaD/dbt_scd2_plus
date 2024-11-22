with source as (
      select * from {{ source('dwh', 'scd2_plus_staging_data') }}
),
renamed as (
    select
        

    from source
)
select * from renamed
  