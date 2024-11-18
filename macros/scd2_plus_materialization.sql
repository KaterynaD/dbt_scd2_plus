{% materialization scd2_plus, default %}



  {% set config = model['config'] %}

  {% set unique_key = config['unique_key'] %}
  {% if unique_key|length == 0 %}
   {{ exceptions.raise_compiler_error('Required parameter "unique_key" is not set!') }}
  {% endif %}
  {% set updated_at = config['updated_at'] %}
  {% if updated_at|length == 0 %}
   {{ exceptions.raise_compiler_error('Required parameter "updated_at" is not set!') }}
  {% endif %}  
  {% set check_cols = config['check_cols'] %}
    {% if check_cols|length == 0 %}
   {{ exceptions.raise_compiler_error('Required parameter "check_cols" is not set!') }}
  {% endif %}  

  
  {% set target_table = model.get('alias', model.get('name')) %}

  {% set target_relation_exists, target_relation = get_or_create_relation(
          database=model.database,
          schema=model.schema,
          identifier=target_table,
          type='table') %}

  {% if not target_relation.is_table %}
    {% do exceptions.relation_wrong_type(target_relation, 'table') %}
  {% endif %}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}

  -- `BEGIN` happens here:
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {# Build relation SQL#}

  {% if not target_relation_exists %}
  
   {% set build_sql = dbt_scd2_plus.scd2_plus_build_table_sql(config = config, sql = model['compiled_code'], create_flg=true) %}
   {% set final_sql = create_table_as(False, target_relation, build_sql) %}

 {% else %}

   {% set final_sql = dbt_scd2_plus.scd2_plus_merge_sql(target = target_relation, config = config, sql = model['compiled_code']) %}

 {% endif %}

  {# Execute SQL to create a new relation or insert/update into existing#}

  {% call statement('main') %}
      {{ final_sql }}
  {% endcall %}

  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {% set should_revoke = should_revoke(target_relation_exists, full_refresh_mode=False) %}
  {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}

  {% do persist_docs(target_relation, model) %}

  -- `COMMIT` happens here

  {{ adapter.commit() }}

  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}