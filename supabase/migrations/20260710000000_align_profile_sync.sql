-- Apply after 20260709000000_nuvio_compatible_backend.sql.
-- Aligns profile replacement with the documented six-profile public API.

create or replace function public.sync_push_profiles(p_profiles jsonb, p_client_max_profiles integer default 4, p_origin_client_id text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  item jsonb;
  keep_ids integer[] := '{}';
  idx integer;
  v_client_max_profiles integer := least(greatest(coalesce(p_client_max_profiles, 4), 1), 6);
begin
  for item in select * from jsonb_array_elements(coalesce(p_profiles, '[]'::jsonb)) loop
    idx := (item->>'profile_index')::integer;
    if idx is null or idx < 1 or idx > v_client_max_profiles then
      continue;
    end if;

    keep_ids := array_append(keep_ids, idx);
    insert into public.profiles(
      user_id, profile_index, name, avatar_color_hex, uses_primary_addons,
      uses_primary_plugins, avatar_id, avatar_url
    )
    values (
      v_owner,
      idx,
      coalesce(item->>'name', ''),
      coalesce(item->>'avatar_color_hex', '#1E88E5'),
      coalesce((item->>'uses_primary_addons')::boolean, false),
      coalesce((item->>'uses_primary_plugins')::boolean, false),
      nullif(item->>'avatar_id', ''),
      nullif(item->>'avatar_url', '')
    )
    on conflict (user_id, profile_index) do update
      set name = excluded.name,
          avatar_color_hex = excluded.avatar_color_hex,
          uses_primary_addons = excluded.uses_primary_addons,
          uses_primary_plugins = excluded.uses_primary_plugins,
          avatar_id = excluded.avatar_id,
          avatar_url = excluded.avatar_url;
  end loop;

  delete from public.profiles
  where user_id = v_owner
    and profile_index between 1 and v_client_max_profiles
    and (array_length(keep_ids, 1) is null or profile_index <> all(keep_ids));
end;
$$;

create or replace function public.sync_delete_profile_data(p_profile_id integer, p_origin_client_id text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
begin
  if p_profile_id = 1 then
    raise exception 'Primary profile cannot be deleted';
  end if;

  delete from public.plugins where user_id = v_owner and profile_id = p_profile_id;
  delete from public.addons where user_id = v_owner and profile_id = p_profile_id;
  delete from public.library_items where user_id = v_owner and profile_id = p_profile_id;
  delete from public.watch_progress where user_id = v_owner and profile_id = p_profile_id;
  delete from public.watch_progress_events where user_id = v_owner and profile_id = p_profile_id;
  delete from public.watched_items where user_id = v_owner and profile_id = p_profile_id;
  delete from public.watched_item_events where user_id = v_owner and profile_id = p_profile_id;
  delete from public.collections where user_id = v_owner and profile_id = p_profile_id;
  delete from public.home_catalog_settings where user_id = v_owner and profile_id = p_profile_id;
  delete from public.profile_settings_blobs where user_id = v_owner and profile_id = p_profile_id;
  delete from public.provider_credentials where user_id = v_owner and profile_id = p_profile_id;
  delete from public.profile_pins where user_id = v_owner and profile_index = p_profile_id;
  delete from public.profiles where user_id = v_owner and profile_index = p_profile_id;
end;
$$;

notify pgrst, 'reload schema';
