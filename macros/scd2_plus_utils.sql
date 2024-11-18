{% macro scd2_plus_build_table_sql(config, sql, create_flg=true) %}

    {% set now = modules.datetime.datetime.now() %}


    {% set unique_key = config['unique_key'] %}
    {% set updated_at = config['updated_at'] %}
    {% set loaded_at = config['loaded_at']|default(updated_at, true) %}

    {% set check_cols = config['check_cols'] %}
    {% set punch_thru_cols = config['punch_thru_cols'] %}
    {% set update_cols = config['update_cols'] %}

    {% set loaddate = config['loaddate']|default(now, true) %}
    


    {% set scd_id_col_name = config['scd_id_col_name']|default('scd_id', true) %}
    {% set scd_valid_from_col_name = config['scd_valid_from_col_name']|default('valid_from', true) %}
    {% set scd_valid_to_col_name = config['scd_valid_to_col_name']|default('valid_to', true) %}
    {% set scd_record_version_col_name = config['scd_record_version_col_name']|default('record_version', true) %}
    {% set scd_loaddate_col_name = config['scd_loaddate_col_name']|default('loaddate', true) %}
    {% set scd_updatedate_col_name = config['scd_updatedate_col_name']|default('updatedate', true) %}

    

    {% set scd_valid_from_min_date = config['scd_valid_from_min_date']|default('3000-01-01', true) %}
    {% set scd_valid_to_max_date = config['scd_valid_to_max_date']|default('1900-01-01', true) %}

    {% set scd_id_expr = snapshot_hash_arguments([unique_key, updated_at]) %}

    {% set scd_hash_expr = snapshot_hash_arguments(check_cols) %}




    with sbq as 
    (	

     /*original model select*/
     {{ sql }}

    ) 
    ,dedup_data as
    (
     /*Records with the same unique_key and updated_at but older loaded_at will take precedence (rn=1) when duplicates are present in the same bach*/
     /*Random record is loaded if there are few records with the same unique_key,updated_at and loaded_at. */
     select
      *,
      row_number() over(partition by {{ unique_key }}, {{ updated_at }} order by {{ loaded_at }} desc) rn
     from sbq
    )
    ,raw_data as 
    (
      /*hash value for all columns where we need to track changes*/
      /*service scd columns which depends on raw data */
      select 
        *,
       {{ scd_hash_expr }} as scd_hash,
       {{ scd_id_expr }} as {{ scd_id_col_name }},        
       {{ updated_at }} as  {{ scd_valid_from_col_name }}
    from dedup_data
    where dedup_data.rn=1
    )    
    ,int_data as 
    (
      /*previous scd_hash*/
      select
       *,
       /*for Update cols: Need a value from the next record even if it is not included in the final dim */
      {% for c in update_cols %} 
       last_value({{ c }}) over(partition by id, scd_hash order by {{ updated_at }} RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as last_{{ c }} ,
      {% endfor %}
       lag(scd_hash) over(partition by {{ unique_key }} order by {{ updated_at }}) prev_scd_hash,
       lead(scd_hash) over(partition by {{ unique_key }} order by {{ updated_at }}) next_scd_hash
      from raw_data
    )
    ,data as 
    (
      select
       {{ scd_id_col_name }},  
       {{ scd_valid_from_col_name }},
       {{ unique_key }},
       /* check cols - Kimball Type II) setting: A new dimension record version is inserted*/
      {% for c in check_cols %} 
       {{ c }}, 
      {% endfor %}
       /* Punch through cols - (Kimbal Type I) setting: These attributes in all the dimension record versions are updated*/
      {% for c in punch_thru_cols %} 
       last_value({{ c }}) over(partition by {{ unique_key }} order by {{ scd_valid_from_col_name }} RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as {{ c }}, 
      {% endfor %}
       /*Update cols - These attributes in the last dimension record version are updated.*/
      {% for c in update_cols %} 
       case 
         when next_scd_hash=scd_hash then last_{{ c }}
         else {{ c }}
       end as {{ c }}, 
      {% endfor %}
       scd_hash,
       prev_scd_hash,
       next_scd_hash
       from int_data
    )
    ,final_data as
    (  
      select
       {{ scd_id_col_name }},  
       {{ scd_valid_from_col_name }},
       coalesce(lead({{ scd_valid_from_col_name }}) over(partition by {{ unique_key }} order by {{ scd_valid_from_col_name }}), cast(case when '{{ scd_valid_to_max_date }}'='1900-01-01' then null else '{{ scd_valid_to_max_date }}' end as timestamp)) as {{ scd_valid_to_col_name }},
       row_number() over(partition by {{ unique_key }} order by {{ scd_valid_from_col_name }}) as {{ scd_record_version_col_name }},
       {{ unique_key }},
      {% for c in check_cols %} 
       {{ c }}, 
      {% endfor %}
      {% for c in punch_thru_cols %} 
       {{ c }},
      {% endfor %}
      {% for c in update_cols %} 
       {{ c }},
      {% endfor %}       
       cast('{{ loaddate }}' as timestamp) as    {{ scd_loaddate_col_name }},
       cast('{{ loaddate }}' as timestamp) as    {{ scd_updatedate_col_name }},
       scd_hash
      from data
      where coalesce(prev_scd_hash,'~')<>scd_hash
    )
      select
       {{ scd_id_col_name }},
    
    {# The query is used in "create table as select..." and "insert/update" in an existing table #}
    {# scd_valid_from_min_date should be used (if configured) only in "create table as select.."#}

    {% if create_flg %}  

       case
        when {{ scd_record_version_col_name }}=1 then
         cast(case when '{{ scd_valid_from_min_date }}'='3000-01-01' then {{ scd_valid_from_col_name }} else '{{ scd_valid_from_min_date }}' end as timestamp)
        else cast({{ scd_valid_from_col_name }} as timestamp)
       end as {{ scd_valid_from_col_name }},

    {% else %}

        cast({{ scd_valid_from_col_name }} as timestamp) as {{ scd_valid_from_col_name }},

    {% endif %}

       {{ scd_valid_to_col_name }},
       {{ scd_record_version_col_name }},
       {{ unique_key }},
      {% for c in check_cols %} 
       {{ c }}, 
      {% endfor %}
      {% for c in punch_thru_cols %} 
       {{ c }},
      {% endfor %}
      {% for c in update_cols %} 
       {{ c }},
      {% endfor %}       
       cast('{{ loaddate }}' as timestamp) as    {{ scd_loaddate_col_name }},
       cast('{{ loaddate }}' as timestamp) as    {{ scd_updatedate_col_name }},
       scd_hash
      from final_data
    /*final query - only rows with a change in scd_hash*/

{% endmacro %}

{% macro scd2_plus_merge_sql(target, config, sql) %}

    {% set now = modules.datetime.datetime.now() %}

    {% set unique_key = config['unique_key'] %}
    {% set updated_at = config['updated_at'] %}
    {% set loaded_at = config['loaded_at']|default(updated_at, true) %}

    {% set check_cols = config['check_cols'] %}
    {% set punch_thru_cols = config['punch_thru_cols'] %}
    {% set update_cols = config['update_cols'] %}

    {% set loaddate = config['loaddate']|default(now, true) %}


    {% set scd_id_col_name = config['scd_id_col_name']|default('scd_id', true) %}
    {% set scd_valid_from_col_name = config['scd_valid_from_col_name']|default('valid_from', true) %}
    {% set scd_valid_to_col_name = config['scd_valid_to_col_name']|default('valid_to', true) %}
    {% set scd_record_version_col_name = config['scd_record_version_col_name']|default('record_version', true) %}
    {% set scd_loaddate_col_name = config['scd_loaddate_col_name']|default('loaddate', true) %}
    {% set scd_updatedate_col_name = config['scd_updatedate_col_name']|default('updatedate', true) %}

    {% set scd_valid_from_min_date = config['scd_valid_from_min_date']|default('3000-01-01', true) %}
    {% set scd_valid_to_max_date = config['scd_valid_to_max_date']|default('1900-01-01', true) %}

    {# sql to load new data is the same as to create table #}
    {% set new_data_sql = dbt_scd2_plus.scd2_plus_build_table_sql(config = config, sql = model['compiled_code'], create_flg=false) %}

    
    {% set int_table_name = 'int' ~ '_' ~ this.table ~ '_' ~ invocation_id | replace("-", "_") %}

    {# For development only: #}
    {# set int_table_name = 'abc' #}
    {# drop table if exists  {{ int_table_name }}; #}

    /*staging table for only new changed data*/
    create  temporary table {{ int_table_name }} as
    with stg_data as 
    (
      {{ new_data_sql }}
    )    
    ,existing_data as 
    (
    /*-- we need existing data from dim to compare with new add/not add with/without changes --*/
    select
     *
    from  {{ target }} dim
    where dim.{{ unique_key }} in (select stg.{{ unique_key }} from stg_data stg)
    )
    ,data as 
    (
      /*1 - new data, not in dim before,  2 new version of existing data in dim for the same id and updated_at date--*/
      select 
       stg.* ,
       case when dim.{{ scd_id_col_name }} is null then 1 else 2 end new_data
      from stg_data stg 
      left outer join existing_data dim 
      on stg.{{ scd_id_col_name }} = dim.{{ scd_id_col_name }}
      union all
       /* existing data for comparizon (prev_scd_hash) */
      select 
       *,
       0 new_data 
      from existing_data
    )
      select
       *,
       /*-----------------------------------------------------------*/
       lag(scd_hash) over(partition by {{ unique_key }} order by  {{ scd_valid_from_col_name }} ) prev_scd_hash
       /*-----------------------------------------------------------*/
      from data;

    /*insert new  in the target table */
    insert into {{ target }}
    select 
       {{ scd_id_col_name }},  
       {{ scd_valid_from_col_name }},
       {{ scd_valid_to_col_name }},
       {{ scd_record_version_col_name }},
       {{ unique_key }},
      {% for c in check_cols %} 
       {{ c }}, 
      {% endfor %}
      {% for c in punch_thru_cols %} 
       {{ c }},
      {% endfor %}
      {% for c in update_cols %} 
       {{ c }},
      {% endfor %}
       {{ scd_loaddate_col_name }}, 
       {{ scd_updatedate_col_name }},
       scd_hash  
    from {{ int_table_name }}
    where new_data=1 and
            coalesce(prev_scd_hash,'~')<>scd_hash
      order by {{ unique_key }}, {{ scd_updatedate_col_name }};

    /* Update the same version in the target table (duplicates by unique_key and updated_at, but different check_cols) */

    update {{ target }}
    set
    {% for c in check_cols %} 
     {{ c }} = data.{{ c }} ,
    {% endfor %} 
    {% for c in update_cols %} 
     {{ c }} = data.{{ c }} ,
    {% endfor %}
    {{ scd_updatedate_col_name }} = cast('{{ loaddate }}' as timestamp)
    from {{ int_table_name }} data
    where {{ target }}.{{ unique_key }} = data.{{ unique_key }} and 
          {{ target }}.{{ scd_id_col_name }} = data.{{ scd_id_col_name }} and
          {{ target }}.scd_hash <> data.scd_hash and 
          data.new_data=2;

    /*----------------Adjusting {{ valid_from }} - {{ valid_to }} in a case of backdated transactions*/
    with data as 
    (
     select
      {{ unique_key }},
      {{ scd_id_col_name }},
      {{ scd_valid_from_col_name }},
      coalesce(lead({{ scd_valid_from_col_name }}) over (partition by {{ unique_key }} order by {{ scd_valid_from_col_name }}), cast(case when '{{ scd_valid_to_max_date }}'='1900-01-01' then null else '{{ scd_valid_to_max_date }}' end as timestamp)) as {{ scd_valid_to_col_name }},
      row_number() over(partition by {{ unique_key }} order by {{ scd_valid_from_col_name }}) as {{ scd_record_version_col_name }}
     from {{ target }} dim
     where {{ unique_key }} in (select {{ unique_key }} from {{ target }} where {{ scd_loaddate_col_name }}='{{ loaddate }}')
    )
    update {{ target }}
    set {{ scd_valid_to_col_name }}=data.{{ scd_valid_to_col_name }},
        {{ scd_record_version_col_name }} = data.{{ scd_record_version_col_name }},
        {{ scd_valid_from_col_name }} = 
        case
        when data.{{ scd_record_version_col_name }}=1 then
         cast(case when '{{ scd_valid_from_min_date }}'='3000-01-01' then data.{{ scd_valid_from_col_name }} else '{{ scd_valid_from_min_date }}' end as timestamp)
        else cast(data.{{ scd_valid_from_col_name }} as timestamp)
       end 
    from data
    where {{ target }}.{{ unique_key }} = data.{{ unique_key }} and 
          {{ target }}.{{ scd_id_col_name }} = data.{{ scd_id_col_name }};
      


  
    /* Update existing records with latest values of punch_thru_cols even if a record does not have changes in check_cols */
    /* Punch through cols - (Kimbal Type I) setting: These attributes in all the dimension record versions are updated*/

    {% if  punch_thru_cols|length > 0 %}

    with data as 
    (
     select distinct
      {{ unique_key }},     
     {% for c in punch_thru_cols %} 
       last_value({{ c }}) over(partition by {{ unique_key }} order by {{ scd_valid_from_col_name }} RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as {{ c }} {% if not loop.last %} , {% endif %}
     {% endfor %}
     from {{ int_table_name }}
    )
    update {{ target }}
    set 
    {% for c in punch_thru_cols %} 
     {{ c }} = data.{{ c }} ,
    {% endfor %}
     {{ scd_updatedate_col_name }} = cast('{{ loaddate }}' as timestamp)
    from data
    where {{ target }}.{{ unique_key }} = data.{{ unique_key }};

    {% endif %}

    /* Update existing last dimension record version with latest values of update_cols even if a record does not have changes in check_cols */
    /* Update cols - These attributes in the last dimension record version are updated.*/   

    {% if  update_cols|length > 0 %}

    with data as 
    (
    select distinct
     {{ unique_key }},     
    {% for c in update_cols %} 
      last_value({{ c }}) over(partition by {{ unique_key }} order by {{ scd_valid_from_col_name }} RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as {{ c }} {% if not loop.last %} , {% endif %}
    {% endfor %}
    from {{ int_table_name }}
    )
    update {{ target }}
    set 
    {% for c in update_cols %} 
     {{ c }} = data.{{ c }} ,
    {% endfor %}
      {{ scd_updatedate_col_name }} = cast('{{ loaddate }}' as timestamp)
    from data
    where {{ target }}.{{ unique_key }} = data.{{ unique_key }} and
          ({{ target }}.{{ scd_valid_to_col_name }} is null or 
           {{ target }}.{{ scd_valid_to_col_name }}=cast(case when '{{ scd_valid_to_max_date }}'='1900-01-01' then null else '{{ scd_valid_to_max_date }}' end as timestamp));

    {% endif %}

    /* No need in intermediate data table anymore */
    drop table {{ int_table_name }};
{% endmacro %}