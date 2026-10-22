alter table private.finn_config add column if not exists api_keys jsonb not null default '[]';
alter table private.finn_config add column if not exists models text[] not null
  default array['gemini-3.8-flash', 'gemini-3.7-flash', 'gemini-3.6-flash', 'gemini-3.5-flash'];

update private.finn_config
set api_keys = jsonb_build_array(jsonb_build_object(
  'id', gen_random_uuid()::text,
  'label', case when endpoint like '%googleapis%' then 'Google AI' else 'OpenRouter' end,
  'endpoint', endpoint,
  'key', api_key
))
where id = 1 and api_key is not null and api_keys = '[]'::jsonb;

create or replace function public.admin_get_finn_config() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  c private.finn_config;
begin
  if not public.is_admin() then
    raise exception 'not_allowed';
  end if;
  select * into c from private.finn_config where id = 1;
  return jsonb_build_object(
    'keys', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k ->> 'id',
        'label', k ->> 'label',
        'endpoint', k ->> 'endpoint',
        'hint', '...' || right(k ->> 'key', 4)
      ) order by ord)
      from jsonb_array_elements(c.api_keys) with ordinality as t(k, ord)
    ), '[]'::jsonb),
    'models', to_jsonb(c.models),
    'system_prompt', c.system_prompt,
    'updated_at', c.updated_at
  );
end;
$$;

create or replace function public.admin_save_finn_key(
  key_id text default null,
  key_label text default null,
  key_endpoint text default null,
  key_value text default null
) returns text
language plpgsql security definer set search_path = '' as $$
declare
  keys jsonb;
  found boolean := false;
  out_id text := key_id;
  item jsonb;
  result jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'not_allowed';
  end if;
  select api_keys into keys from private.finn_config where id = 1;
  if key_id is not null then
    for item in select value from jsonb_array_elements(keys) loop
      if item ->> 'id' = key_id then
        found := true;
        item := item
          || jsonb_build_object('label', coalesce(nullif(btrim(key_label), ''), item ->> 'label'))
          || jsonb_build_object('endpoint', coalesce(nullif(btrim(key_endpoint), ''), item ->> 'endpoint'))
          || jsonb_build_object('key', coalesce(nullif(btrim(key_value), ''), item ->> 'key'));
      end if;
      result := result || jsonb_build_array(item);
    end loop;
  end if;
  if not found then
    if nullif(btrim(key_value), '') is null or nullif(btrim(key_endpoint), '') is null then
      raise exception 'key_and_endpoint_required';
    end if;
    out_id := gen_random_uuid()::text;
    result := coalesce(keys, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'id', out_id,
      'label', coalesce(nullif(btrim(key_label), ''), 'Key'),
      'endpoint', btrim(key_endpoint),
      'key', btrim(key_value)
    ));
  end if;
  update private.finn_config set api_keys = result, updated_at = now() where id = 1;
  return out_id;
end;
$$;

create or replace function public.admin_remove_finn_key(key_id text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'not_allowed';
  end if;
  update private.finn_config
  set api_keys = coalesce((
        select jsonb_agg(k order by ord)
        from jsonb_array_elements(api_keys) with ordinality as t(k, ord)
        where k ->> 'id' <> key_id
      ), '[]'::jsonb),
      updated_at = now()
  where id = 1;
end;
$$;

create or replace function public.admin_order_finn_keys(key_ids text[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'not_allowed';
  end if;
  update private.finn_config
  set api_keys = coalesce((
        select jsonb_agg(k order by coalesce(array_position(key_ids, k ->> 'id'), 1000 + ord))
        from jsonb_array_elements(api_keys) with ordinality as t(k, ord)
      ), '[]'::jsonb),
      updated_at = now()
  where id = 1;
end;
$$;

create or replace function public.admin_set_finn_models(new_models text[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'not_allowed';
  end if;
  update private.finn_config
  set models = coalesce((select array_agg(btrim(m) order by ord) from unnest(new_models) with ordinality as t(m, ord) where btrim(m) <> ''), models),
      updated_at = now()
  where id = 1;
end;
$$;

revoke execute on function public.admin_save_finn_key from anon;
revoke execute on function public.admin_remove_finn_key from anon;
revoke execute on function public.admin_order_finn_keys from anon;
revoke execute on function public.admin_set_finn_models from anon;
