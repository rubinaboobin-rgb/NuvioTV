-- Additive parity layer for the public Nuvio backend contract.
-- This intentionally does not import the self-host baseline bootstrap or roles.

create schema if not exists nuvio_private;

create table if not exists nuvio_private.instance_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into nuvio_private.instance_settings(key, value)
values ('default_catalog_url', 'https://catalog.nuvio.tv/manifest.json')
on conflict (key) do nothing;

create or replace function public.nuvio_default_catalog_url()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select value from nuvio_private.instance_settings where key = 'default_catalog_url'),
    'https://catalog.nuvio.tv/manifest.json'
  );
$$;

alter table public.avatar_catalog add column if not exists is_active boolean not null default true;
alter table public.avatar_catalog add column if not exists created_at timestamptz not null default now();
update public.avatar_catalog set is_active = enabled where is_active is distinct from enabled;

alter table public.collections add column if not exists id uuid default extensions.gen_random_uuid();
alter table public.collections add column if not exists created_at timestamptz not null default now();
update public.collections set id = extensions.gen_random_uuid() where id is null;
alter table public.collections alter column id set not null;

alter table public.profile_settings_blobs add column if not exists id uuid default extensions.gen_random_uuid();
alter table public.profile_settings_blobs add column if not exists created_at timestamptz not null default now();
update public.profile_settings_blobs set id = extensions.gen_random_uuid() where id is null;
alter table public.profile_settings_blobs alter column id set not null;

alter table public.home_catalog_settings add column if not exists id uuid default extensions.gen_random_uuid();
update public.home_catalog_settings set id = extensions.gen_random_uuid() where id is null;
alter table public.home_catalog_settings alter column id set not null;

alter table public.profiles add column if not exists profile_id integer not null default 1;
alter table public.profiles add column if not exists pin_enabled boolean not null default false;
alter table public.profiles add column if not exists pin_hash text;
alter table public.profiles add column if not exists pin_updated_at timestamptz;
alter table public.profiles add column if not exists failed_pin_attempts integer not null default 0;
alter table public.profiles add column if not exists pin_locked_until timestamptz;
update public.profiles set profile_id = profile_index where profile_id = 1 and profile_index <> 1;

create or replace function public.sync_profile_identity_columns()
returns trigger
language plpgsql
as $$
begin
  new.profile_id := new.profile_index;
  return new;
end;
$$;

drop trigger if exists profile_identity_columns_sync on public.profiles;
create trigger profile_identity_columns_sync
before insert or update on public.profiles
for each row execute function public.sync_profile_identity_columns();

create table if not exists public.profile_tracker_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null,
  tracker text not null check (tracker in ('mal', 'anilist', 'kitsu')),
  enabled_statuses text[] not null default '{}',
  row_order text[] not null default '{}',
  send_progress boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id, tracker)
);

create table if not exists public.user_tracker_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null,
  tracker text not null check (tracker in ('mal', 'anilist', 'kitsu')),
  access_token text not null,
  refresh_token text,
  expires_at timestamptz,
  tracker_user_id text,
  tracker_username text,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id, tracker)
);

create table if not exists public.library_item_events (
  event_id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null,
  operation text not null check (operation in ('upsert', 'delete')),
  content_id text not null,
  content_type text not null,
  name text not null default '',
  poster text,
  poster_shape text not null default 'POSTER',
  background text,
  description text,
  release_info text,
  imdb_rating real,
  genres text[] not null default '{}',
  addon_base_url text,
  added_at bigint not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.sync_push_audit_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  surface text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  auth_uid uuid,
  profile_id integer,
  platform text,
  request_user_agent text,
  request_ip text,
  request_method text,
  request_path text,
  old_row_count integer,
  incoming_row_count integer,
  deleted_row_count integer,
  old_payload_hash text,
  incoming_payload_hash text,
  deleted_item_hashes jsonb not null default '[]',
  metadata jsonb not null default '{}'
);

-- The official baseline retains this RPC but omits the backing table. Keep the
-- client contract usable on Supabase Cloud instead of shipping a broken RPC.
create table if not exists public.sync_invalidations (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer,
  surface text not null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.tracker_tv_login_sessions (
  code text primary key,
  tracker text not null check (tracker in ('mal', 'anilist', 'kitsu')),
  device_nonce text not null,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'ready', 'expired')),
  access_token text,
  refresh_token text,
  expires_in integer,
  tracker_user_id text,
  tracker_username text,
  redirect_base_url text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists public.user_activity_events (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_user_id uuid,
  profile_id integer,
  platform text not null default 'unknown',
  app_version text,
  device_id text,
  device_name text,
  event_type text not null,
  entity_type text,
  entity_key text,
  action text,
  status text not null check (status in ('started', 'succeeded', 'failed', 'skipped')),
  duration_ms integer,
  item_count integer,
  error_code text,
  error_message text,
  correlation_id uuid,
  metadata jsonb not null default '{}'
);

create table if not exists public.user_session_devices (
  session_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  client_name text not null,
  client_version text,
  platform text not null,
  device_name text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  installation_id text not null,
  primary key (user_id, installation_id)
);

do $$
begin
  if to_regclass('auth.sessions') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.user_session_devices'::regclass
         and conname = 'user_session_devices_session_id_fkey'
     ) then
    alter table public.user_session_devices
      add constraint user_session_devices_session_id_fkey
      foreign key (session_id) references auth.sessions(id) on delete cascade;
  end if;
end;
$$;

create index if not exists library_item_events_owner_cursor
  on public.library_item_events(user_id, profile_id, event_id);
create index if not exists profile_tracker_settings_owner
  on public.profile_tracker_settings(user_id, profile_id);
create index if not exists user_tracker_tokens_owner
  on public.user_tracker_tokens(user_id, profile_id);
create index if not exists user_activity_events_owner_created
  on public.user_activity_events(user_id, created_at desc);
create index if not exists user_session_devices_user
  on public.user_session_devices(user_id, last_seen_at desc);
create index if not exists sync_invalidations_owner
  on public.sync_invalidations(user_id, profile_id, created_at desc);

create or replace function public.handle_new_profile_default_addons()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  catalog_url text := public.nuvio_default_catalog_url();
begin
  if current_setting('nuvio.skip_profile_defaults', true) = 'on' then
    return new;
  end if;

  if new.uses_primary_addons = false then
    insert into public.addons(user_id, profile_id, url, name, enabled, sort_order)
    select new.user_id, new.profile_index, catalog_url, 'Nuvio Catalog Addon', true, 0
    where not exists (
      select 1 from public.addons
      where user_id = new.user_id and profile_id = new.profile_index and md5(url) = md5(catalog_url)
    );

    insert into public.addons(user_id, profile_id, url, name, enabled, sort_order)
    select new.user_id, new.profile_index, 'https://opensubtitles-v3.strem.io', 'OpenSubtitles v3', true, 1
    where not exists (
      select 1 from public.addons
      where user_id = new.user_id and profile_id = new.profile_index
        and md5(url) = md5('https://opensubtitles-v3.strem.io')
    );
  end if;
  return new;
end;
$$;

create or replace function public.handle_new_user_default_addons()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.addons(user_id, profile_id, url, name, enabled, sort_order)
  values (new.id, 1, public.nuvio_default_catalog_url(), 'Nuvio Catalog Addon', true, 0)
  on conflict (user_id, profile_id, url) do nothing;
  insert into public.addons(user_id, profile_id, url, name, enabled, sort_order)
  values (new.id, 1, 'https://opensubtitles-v3.strem.io', 'OpenSubtitles v3', true, 1)
  on conflict (user_id, profile_id, url) do nothing;
  return new;
end;
$$;

drop trigger if exists on_profile_created_addons on public.profiles;
create trigger on_profile_created_addons
after insert on public.profiles
for each row execute function public.handle_new_profile_default_addons();

drop trigger if exists on_auth_user_created_addons on auth.users;
create trigger on_auth_user_created_addons
after insert on auth.users
for each row execute function public.handle_new_user_default_addons();

create or replace function public.sync_set_origin_client_id(p_origin_client_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('app.origin_client_id', coalesce(left(nullif(trim(p_origin_client_id), ''), 96), ''), true);
end;
$$;

create or replace function public.sync_current_origin_client_id()
returns text
language sql
stable
as $$
  select nullif(current_setting('app.origin_client_id', true), '')
$$;

create or replace function public.emit_sync_invalidation(
  p_user_id uuid,
  p_profile_id integer,
  p_surface text,
  p_metadata jsonb default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then return; end if;
  insert into public.sync_invalidations(user_id, profile_id, surface, metadata)
  values (p_user_id, p_profile_id, p_surface, coalesce(p_metadata, '{}'));
end;
$$;

create or replace function public.record_library_item_delta_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    if exists (select 1 from auth.users where id = old.user_id) then
      insert into public.library_item_events(
        user_id, profile_id, operation, content_id, content_type, name, poster,
        poster_shape, background, description, release_info, imdb_rating, genres,
        addon_base_url, added_at
      ) values (
        old.user_id, old.profile_id, 'delete', old.content_id, old.content_type,
        coalesce(old.name, ''), old.poster, coalesce(old.poster_shape, 'POSTER'),
        old.background, old.description, old.release_info, old.imdb_rating,
        coalesce(old.genres, '{}'), old.addon_base_url, coalesce(old.added_at, 0)
      );
    end if;
    return old;
  end if;

  insert into public.library_item_events(
    user_id, profile_id, operation, content_id, content_type, name, poster,
    poster_shape, background, description, release_info, imdb_rating, genres,
    addon_base_url, added_at
  ) values (
    new.user_id, new.profile_id, 'upsert', new.content_id, new.content_type,
    coalesce(new.name, ''), new.poster, coalesce(new.poster_shape, 'POSTER'),
    new.background, new.description, new.release_info, new.imdb_rating,
    coalesce(new.genres, '{}'), new.addon_base_url, coalesce(new.added_at, 0)
  );
  return new;
end;
$$;

drop trigger if exists library_item_delta_events_trigger on public.library_items;
create trigger library_item_delta_events_trigger
after insert or update or delete on public.library_items
for each row execute function public.record_library_item_delta_event();

insert into public.library_item_events(
  user_id, profile_id, operation, content_id, content_type, name, poster, poster_shape,
  background, description, release_info, imdb_rating, genres, addon_base_url, added_at
)
select li.user_id, li.profile_id, 'upsert', li.content_id, li.content_type, li.name, li.poster,
       coalesce(li.poster_shape, 'POSTER'), li.background, li.description, li.release_info,
       li.imdb_rating, coalesce(li.genres, '{}'), li.addon_base_url, coalesce(li.added_at, 0)
from public.library_items li
where not exists (
  select 1 from public.library_item_events e
  where e.user_id = li.user_id and e.profile_id = li.profile_id
    and e.content_id = li.content_id and e.content_type = li.content_type
);

create or replace function public.sync_get_library_delta_cursor(p_profile_id integer default 1)
returns bigint
language sql
security definer
set search_path = public
as $$
  select coalesce(max(event_id), 0)::bigint
  from public.library_item_events
  where user_id = public.require_sync_owner() and profile_id = p_profile_id;
$$;

create or replace function public.sync_pull_library_delta(
  p_profile_id integer default 1,
  p_since_event_id bigint default 0,
  p_limit integer default 1000
)
returns table(
  event_id bigint,
  operation text,
  content_id text,
  content_type text,
  name text,
  poster text,
  poster_shape text,
  background text,
  description text,
  release_info text,
  imdb_rating real,
  genres text[],
  addon_base_url text,
  added_at bigint
)
language sql
security definer
set search_path = public
as $$
  select event_id, operation, content_id, content_type, name, poster, poster_shape,
         background, description, release_info, imdb_rating, genres, addon_base_url,
         added_at
  from public.library_item_events
  where user_id = public.require_sync_owner()
    and profile_id = p_profile_id
    and event_id > greatest(coalesce(p_since_event_id, 0), 0)
  order by event_id asc
  limit least(greatest(coalesce(p_limit, 1000), 1), 1000);
$$;

create or replace function public.sync_push_library_items(
  p_items jsonb,
  p_profile_id integer default 1,
  p_origin_client_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  item jsonb;
begin
  if p_profile_id is null or p_profile_id not between 1 and 6 then
    raise exception 'Invalid profile id';
  end if;
  perform public.sync_set_origin_client_id(p_origin_client_id);

  for item in select value from jsonb_array_elements(coalesce(p_items, '[]')) loop
    if btrim(coalesce(item->>'content_id', '')) = ''
       or btrim(coalesce(item->>'content_type', '')) = '' then
      continue;
    end if;

    insert into public.library_items(
      user_id, profile_id, content_id, content_type, name, poster, poster_shape,
      background, description, release_info, imdb_rating, genres, addon_base_url, added_at
    ) values (
      v_owner, p_profile_id, item->>'content_id', item->>'content_type',
      coalesce(item->>'name', ''), item->>'poster', coalesce(item->>'poster_shape', 'POSTER'),
      item->>'background', item->>'description', item->>'release_info',
      nullif(item->>'imdb_rating', '')::real,
      case when jsonb_typeof(item->'genres') = 'array'
        then array(select jsonb_array_elements_text(item->'genres')) else '{}' end,
      item->>'addon_base_url', coalesce(nullif(item->>'added_at', '')::bigint, 0)
    )
    on conflict (user_id, profile_id, content_id, content_type) do update set
      name = excluded.name,
      poster = excluded.poster,
      poster_shape = excluded.poster_shape,
      background = excluded.background,
      description = excluded.description,
      release_info = excluded.release_info,
      imdb_rating = excluded.imdb_rating,
      genres = excluded.genres,
      addon_base_url = excluded.addon_base_url,
      added_at = excluded.added_at,
      updated_at = now()
    where public.library_items.name is distinct from excluded.name
       or public.library_items.poster is distinct from excluded.poster
       or public.library_items.poster_shape is distinct from excluded.poster_shape
       or public.library_items.background is distinct from excluded.background
       or public.library_items.description is distinct from excluded.description
       or public.library_items.release_info is distinct from excluded.release_info
       or public.library_items.imdb_rating is distinct from excluded.imdb_rating
       or public.library_items.genres is distinct from excluded.genres
       or public.library_items.addon_base_url is distinct from excluded.addon_base_url
       or public.library_items.added_at is distinct from excluded.added_at;
  end loop;
end;
$$;

create or replace function public.sync_delete_library_items(
  p_keys jsonb,
  p_profile_id integer default 1,
  p_origin_client_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  key_item jsonb;
begin
  if p_profile_id is null or p_profile_id not between 1 and 6 then
    raise exception 'Invalid profile id';
  end if;
  perform public.sync_set_origin_client_id(p_origin_client_id);

  for key_item in select value from jsonb_array_elements(coalesce(p_keys, '[]')) loop
    delete from public.library_items
    where user_id = v_owner
      and profile_id = p_profile_id
      and content_id = key_item->>'content_id'
      and content_type = key_item->>'content_type';
  end loop;
end;
$$;

create or replace function public.get_profile_tracker_settings(p_profile_id integer)
returns setof public.profile_tracker_settings
language sql
security definer
set search_path = public
as $$
  select * from public.profile_tracker_settings
  where user_id = public.require_sync_owner() and profile_id = p_profile_id;
$$;

create or replace function public.upsert_profile_tracker_settings(
  p_profile_id integer,
  p_tracker text,
  p_enabled_statuses text[],
  p_row_order text[],
  p_send_progress boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_profile_id not between 1 and 6 then
    raise exception 'Invalid profile id';
  end if;
  if lower(trim(coalesce(p_tracker, ''))) not in ('mal', 'anilist', 'kitsu') then
    raise exception 'Invalid tracker';
  end if;

  insert into public.profile_tracker_settings(
    user_id, profile_id, tracker, enabled_statuses, row_order, send_progress, updated_at
  ) values (
    public.require_sync_owner(), p_profile_id, lower(trim(p_tracker)),
    coalesce(p_enabled_statuses, '{}'), coalesce(p_row_order, '{}'),
    coalesce(p_send_progress, true), now()
  )
  on conflict (user_id, profile_id, tracker) do update set
    enabled_statuses = excluded.enabled_statuses,
    row_order = excluded.row_order,
    send_progress = excluded.send_progress,
    updated_at = now();
end;
$$;

create or replace function public.get_tracker_tokens(p_profile_id integer)
returns setof public.user_tracker_tokens
language sql
security definer
set search_path = public
as $$
  select * from public.user_tracker_tokens
  where user_id = public.require_sync_owner() and profile_id = p_profile_id;
$$;

create or replace function public.clear_tracker_tokens(p_profile_id integer, p_tracker text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.user_tracker_tokens
  where user_id = public.require_sync_owner()
    and profile_id = p_profile_id
    and tracker = lower(trim(p_tracker));
$$;

create or replace function public.sync_normalize_non_tracker_provider_credential(
  p_provider text,
  p_credential_json jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  provider_name text := lower(trim(coalesce(p_provider, '')));
  field_name text;
  field_value text;
begin
  field_name := case
    when provider_name in ('debrid:torbox', 'debrid:premiumize', 'debrid:realdebrid',
                           'tmdb', 'mdblist', 'introdb') then 'api_key'
    when provider_name = 'animeskip' then 'client_id'
    else null
  end;

  if field_name is null then
    raise exception 'Unsupported provider credential: %', provider_name;
  end if;
  if p_credential_json is null
     or jsonb_typeof(p_credential_json) <> 'object'
     or not (p_credential_json ? field_name)
     or p_credential_json - field_name <> '{}'
     or jsonb_typeof(p_credential_json -> field_name) <> 'string' then
    raise exception 'Invalid credential payload for provider: %', provider_name;
  end if;

  field_value := trim(p_credential_json ->> field_name);
  if length(field_value) > 8192 then
    raise exception 'Credential value is too long for provider: %', provider_name;
  end if;
  return jsonb_build_object(field_name, field_value);
end;
$$;

create or replace function public.sync_seed_provider_credentials(
  p_profile_id integer,
  p_credentials jsonb,
  p_origin_client_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  provider_name text;
begin
  if p_profile_id is null or p_profile_id not between 1 and 6 then
    raise exception 'Invalid profile id';
  end if;
  if p_credentials is null or jsonb_typeof(p_credentials) <> 'array' then
    raise exception 'Provider credentials must be an array';
  end if;
  if jsonb_array_length(p_credentials) > 16 then
    raise exception 'Too many provider credentials';
  end if;
  perform public.sync_set_origin_client_id(p_origin_client_id);

  for item in select value from jsonb_array_elements(p_credentials) loop
    provider_name := lower(trim(coalesce(item->>'provider', '')));
    if provider_name = '' or not (item ? 'credential_json') then
      raise exception 'Invalid provider credential entry';
    end if;
    insert into public.provider_credentials(user_id, profile_id, provider, credential_json, updated_at)
    values (
      public.require_sync_owner(), p_profile_id, provider_name,
      public.sync_normalize_non_tracker_provider_credential(provider_name, item->'credential_json'), now()
    )
    on conflict (user_id, profile_id, provider) do nothing;
  end loop;
end;
$$;

create or replace function public.health_ping()
returns boolean
language sql
security definer
as $$
  select true;
$$;

create or replace function public.record_activity_event(
  p_event_type text,
  p_status text,
  p_profile_id integer default null,
  p_platform text default 'unknown',
  p_app_version text default null,
  p_device_id text default null,
  p_device_name text default null,
  p_entity_type text default null,
  p_entity_key text default null,
  p_action text default null,
  p_duration_ms integer default null,
  p_item_count integer default null,
  p_error_code text default null,
  p_error_message text default null,
  p_correlation_id uuid default null,
  p_metadata jsonb default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  event_id uuid;
  event_type text := nullif(left(trim(coalesce(p_event_type, '')), 128), '');
  event_status text := nullif(trim(coalesce(p_status, '')), '');
  metadata jsonb := coalesce(p_metadata, '{}');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if event_type is null then raise exception 'event_type is required'; end if;
  if event_status not in ('started', 'succeeded', 'failed', 'skipped') then
    raise exception 'Invalid activity status';
  end if;
  if pg_column_size(metadata) > 32768 then
    metadata := jsonb_build_object('truncated', true, 'reason', 'metadata exceeded 32KB limit');
  end if;

  insert into public.user_activity_events(
    user_id, actor_user_id, profile_id, platform, app_version, device_id, device_name,
    event_type, entity_type, entity_key, action, status, duration_ms, item_count,
    error_code, error_message, correlation_id, metadata
  ) values (
    public.require_sync_owner(), auth.uid(), p_profile_id,
    coalesce(nullif(left(trim(coalesce(p_platform, '')), 64), ''), 'unknown'),
    nullif(left(trim(coalesce(p_app_version, '')), 64), ''),
    nullif(left(trim(coalesce(p_device_id, '')), 128), ''),
    nullif(left(trim(coalesce(p_device_name, '')), 128), ''), event_type,
    nullif(left(trim(coalesce(p_entity_type, '')), 64), ''),
    nullif(left(trim(coalesce(p_entity_key, '')), 512), ''),
    nullif(left(trim(coalesce(p_action, '')), 64), ''), event_status,
    greatest(coalesce(p_duration_ms, 0), 0), greatest(coalesce(p_item_count, 0), 0),
    nullif(left(trim(coalesce(p_error_code, '')), 128), ''),
    nullif(left(trim(coalesce(p_error_message, '')), 1024), ''),
    p_correlation_id, metadata
  ) returning id into event_id;
  return event_id;
end;
$$;

create or replace function public.sync_export_account_backup()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid := public.require_sync_owner();
  data jsonb;
begin
  data := jsonb_build_object(
    'profiles', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_index)
      from (select profile_index, profile_id, name, avatar_color_hex,
                   uses_primary_addons, uses_primary_plugins, avatar_id, avatar_url,
                   created_at, updated_at
            from public.profiles where user_id = owner_id) row_data), '[]'),
    'addons', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, sort_order, created_at)
      from (select profile_id, url, name, enabled, sort_order, created_at, updated_at
            from public.addons where user_id = owner_id) row_data), '[]'),
    'plugins', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, sort_order, created_at)
      from (select profile_id, url, name, enabled, sort_order, repo_type, created_at, updated_at
            from public.plugins where user_id = owner_id) row_data), '[]'),
    'library_items', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, added_at desc, created_at)
      from (select profile_id, content_id, content_type, name, poster, poster_shape, background,
                   description, release_info, imdb_rating, genres, addon_base_url, added_at,
                   created_at, updated_at
            from public.library_items where user_id = owner_id) row_data), '[]'),
    'watch_progress', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, last_watched desc)
      from (select profile_id, content_id, content_type, video_id, season, episode, position,
                   duration, last_watched, progress_key
            from public.watch_progress where user_id = owner_id) row_data), '[]'),
    'watched_items', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, watched_at desc)
      from (select profile_id, content_id, content_type, title, season, episode, watched_at, created_at
            from public.watched_items where user_id = owner_id) row_data), '[]'),
    'profile_settings_blobs', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, platform)
      from (select profile_id, platform, settings_json, created_at, updated_at
            from public.profile_settings_blobs where user_id = owner_id) row_data), '[]'),
    'home_catalog_settings', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, platform)
      from (select profile_id, platform, settings_json, updated_at
            from public.home_catalog_settings where user_id = owner_id) row_data), '[]'),
    'collections', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id)
      from (select profile_id, collections_json, created_at, updated_at
            from public.collections where user_id = owner_id) row_data), '[]'),
    'profile_tracker_settings', coalesce((select jsonb_agg(to_jsonb(row_data) order by profile_id, tracker)
      from (select profile_id, tracker, enabled_statuses, row_order, send_progress, updated_at
            from public.profile_tracker_settings where user_id = owner_id) row_data), '[]')
  );

  return jsonb_build_object(
    'format', 'nuvio_account_backup',
    'version', 1,
    'scope', 'account',
    'exported_at', to_jsonb(now()),
    'sensitive_data_excluded', jsonb_build_array(
      'auth_sessions', 'linked_devices', 'profile_pin_hashes', 'tracker_tokens',
      'provider_credentials', 'audit_logs', 'login_sessions'
    ),
    'data', data
  );
end;
$$;

create or replace function public.sync_restore_account_backup(
  p_backup jsonb,
  p_mode text default 'replace'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid := public.require_sync_owner();
  data jsonb;
  item jsonb;
begin
  if lower(coalesce(nullif(trim(p_mode), ''), 'replace')) <> 'replace' then
    raise exception 'Only replace restore mode is supported';
  end if;
  if p_backup is null
     or jsonb_typeof(p_backup) <> 'object'
     or p_backup->>'format' <> 'nuvio_account_backup'
     or (p_backup->>'version')::integer <> 1 then
    raise exception 'Invalid or unsupported Nuvio backup';
  end if;
  data := coalesce(p_backup->'data', '{}');
  if jsonb_typeof(data) <> 'object' then raise exception 'Invalid backup data'; end if;

  perform set_config('nuvio.skip_profile_defaults', 'on', true);

  delete from public.library_item_events where user_id = owner_id;
  delete from public.watch_progress_events where user_id = owner_id;
  delete from public.watched_item_events where user_id = owner_id;
  delete from public.profile_tracker_settings where user_id = owner_id;
  delete from public.home_catalog_settings where user_id = owner_id;
  delete from public.profile_settings_blobs where user_id = owner_id;
  delete from public.collections where user_id = owner_id;
  delete from public.library_items where user_id = owner_id;
  delete from public.watch_progress where user_id = owner_id;
  delete from public.watched_items where user_id = owner_id;
  delete from public.addons where user_id = owner_id;
  delete from public.plugins where user_id = owner_id;
  delete from public.profile_pins where user_id = owner_id;
  delete from public.profiles where user_id = owner_id;

  for item in select value from jsonb_array_elements(coalesce(data->'profiles', '[]')) loop
    insert into public.profiles(
      user_id, profile_index, profile_id, name, avatar_color_hex, uses_primary_addons,
      uses_primary_plugins, avatar_id, avatar_url, created_at, updated_at
    ) values (
      owner_id,
      coalesce(nullif(item->>'profile_index', '')::integer, 1),
      coalesce(nullif(item->>'profile_id', '')::integer,
               nullif(item->>'profile_index', '')::integer, 1),
      coalesce(item->>'name', ''), coalesce(item->>'avatar_color_hex', '#1E88E5'),
      coalesce((item->>'uses_primary_addons')::boolean, false),
      coalesce((item->>'uses_primary_plugins')::boolean, false),
      nullif(item->>'avatar_id', ''), nullif(item->>'avatar_url', ''),
      coalesce(nullif(item->>'created_at', '')::timestamptz, now()),
      coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'addons', '[]')) loop
    insert into public.addons(user_id, profile_id, url, name, enabled, sort_order, created_at, updated_at)
    values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), nullif(item->>'url', ''),
      nullif(item->>'name', ''), coalesce((item->>'enabled')::boolean, true),
      coalesce(nullif(item->>'sort_order', '')::integer, 0),
      coalesce(nullif(item->>'created_at', '')::timestamptz, now()),
      coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id, url) do update set
      name = excluded.name, enabled = excluded.enabled, sort_order = excluded.sort_order,
      updated_at = excluded.updated_at;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'plugins', '[]')) loop
    insert into public.plugins(user_id, profile_id, url, name, enabled, sort_order, repo_type, created_at, updated_at)
    values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), nullif(item->>'url', ''),
      nullif(item->>'name', ''), coalesce((item->>'enabled')::boolean, true),
      coalesce(nullif(item->>'sort_order', '')::integer, 0), nullif(item->>'repo_type', ''),
      coalesce(nullif(item->>'created_at', '')::timestamptz, now()),
      coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id, url) do update set
      name = excluded.name, enabled = excluded.enabled, sort_order = excluded.sort_order,
      repo_type = excluded.repo_type, updated_at = excluded.updated_at;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'library_items', '[]')) loop
    insert into public.library_items(
      user_id, profile_id, content_id, content_type, name, poster, poster_shape, background,
      description, release_info, imdb_rating, genres, addon_base_url, added_at, created_at, updated_at
    ) values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), item->>'content_id',
      item->>'content_type', coalesce(item->>'name', ''), item->>'poster',
      coalesce(item->>'poster_shape', 'POSTER'), item->>'background', item->>'description',
      item->>'release_info', nullif(item->>'imdb_rating', '')::real,
      case when jsonb_typeof(item->'genres') = 'array'
        then array(select jsonb_array_elements_text(item->'genres')) else '{}' end,
      item->>'addon_base_url', coalesce(nullif(item->>'added_at', '')::bigint, 0),
      coalesce(nullif(item->>'created_at', '')::timestamptz, now()),
      coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id, content_id, content_type) do update set
      name = excluded.name, poster = excluded.poster, poster_shape = excluded.poster_shape,
      background = excluded.background, description = excluded.description,
      release_info = excluded.release_info, imdb_rating = excluded.imdb_rating,
      genres = excluded.genres, addon_base_url = excluded.addon_base_url,
      added_at = excluded.added_at, updated_at = excluded.updated_at;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'watch_progress', '[]')) loop
    insert into public.watch_progress(
      user_id, profile_id, content_id, content_type, video_id, season, episode, position,
      duration, last_watched, progress_key
    ) values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), item->>'content_id',
      item->>'content_type', coalesce(item->>'video_id', ''), nullif(item->>'season', '')::integer,
      nullif(item->>'episode', '')::integer, coalesce(nullif(item->>'position', '')::bigint, 0),
      coalesce(nullif(item->>'duration', '')::bigint, 0),
      coalesce(nullif(item->>'last_watched', '')::bigint, 0), item->>'progress_key'
    ) on conflict (user_id, profile_id, progress_key) do update set
      content_id = excluded.content_id, content_type = excluded.content_type,
      video_id = excluded.video_id, season = excluded.season, episode = excluded.episode,
      position = excluded.position, duration = excluded.duration, last_watched = excluded.last_watched;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'watched_items', '[]')) loop
    insert into public.watched_items(
      user_id, profile_id, content_id, content_type, title, season, episode, watched_at, created_at
    ) values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), item->>'content_id',
      coalesce(nullif(item->>'content_type', ''), 'movie'), coalesce(item->>'title', ''),
      nullif(item->>'season', '')::integer, nullif(item->>'episode', '')::integer,
      coalesce(nullif(item->>'watched_at', '')::bigint, 0),
      coalesce(nullif(item->>'created_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id, content_id, content_type, season_key, episode_key) do update set
      title = excluded.title, watched_at = excluded.watched_at;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'profile_settings_blobs', '[]')) loop
    insert into public.profile_settings_blobs(user_id, profile_id, platform, settings_json, created_at, updated_at)
    values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), coalesce(nullif(item->>'platform', ''), 'tv'),
      coalesce(item->'settings_json', '{}'), coalesce(nullif(item->>'created_at', '')::timestamptz, now()),
      coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id, platform) do update set
      settings_json = excluded.settings_json, updated_at = excluded.updated_at;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'home_catalog_settings', '[]')) loop
    insert into public.home_catalog_settings(user_id, profile_id, platform, settings_json, updated_at)
    values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), coalesce(nullif(item->>'platform', ''), 'tv'),
      coalesce(item->'settings_json', '{}'), coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id, platform) do update set
      settings_json = excluded.settings_json, updated_at = excluded.updated_at;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'collections', '[]')) loop
    insert into public.collections(user_id, profile_id, collections_json, created_at, updated_at)
    values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1),
      case when jsonb_typeof(item->'collections_json') = 'array' then item->'collections_json' else '[]' end,
      coalesce(nullif(item->>'created_at', '')::timestamptz, now()),
      coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id) do update set
      collections_json = excluded.collections_json, updated_at = excluded.updated_at;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'profile_tracker_settings', '[]')) loop
    insert into public.profile_tracker_settings(
      user_id, profile_id, tracker, enabled_statuses, row_order, send_progress, updated_at
    ) values (
      owner_id, coalesce(nullif(item->>'profile_id', '')::integer, 1), item->>'tracker',
      case when jsonb_typeof(item->'enabled_statuses') = 'array'
        then array(select jsonb_array_elements_text(item->'enabled_statuses')) else '{}' end,
      case when jsonb_typeof(item->'row_order') = 'array'
        then array(select jsonb_array_elements_text(item->'row_order')) else '{}' end,
      coalesce((item->>'send_progress')::boolean, true),
      coalesce(nullif(item->>'updated_at', '')::timestamptz, now())
    ) on conflict (user_id, profile_id, tracker) do update set
      enabled_statuses = excluded.enabled_statuses, row_order = excluded.row_order,
      send_progress = excluded.send_progress, updated_at = excluded.updated_at;
  end loop;

  insert into public.watch_progress_events(
    user_id, profile_id, operation, progress_key, content_id, content_type, video_id,
    season, episode, position, duration, last_watched
  ) select user_id, profile_id, 'upsert', progress_key, content_id, content_type, video_id,
           season, episode, position, duration, last_watched
    from public.watch_progress where user_id = owner_id;

  insert into public.watched_item_events(
    user_id, profile_id, operation, content_id, content_type, title, season, episode, watched_at
  ) select user_id, profile_id, 'upsert', content_id, content_type, title, season, episode, watched_at
    from public.watched_items where user_id = owner_id;

  return jsonb_build_object(
    'restored_at', to_jsonb(now()),
    'mode', 'replace',
    'counts', jsonb_build_object(
      'profiles', (select count(*) from public.profiles where user_id = owner_id),
      'addons', (select count(*) from public.addons where user_id = owner_id),
      'plugins', (select count(*) from public.plugins where user_id = owner_id),
      'library_items', (select count(*) from public.library_items where user_id = owner_id),
      'watch_progress', (select count(*) from public.watch_progress where user_id = owner_id),
      'watched_items', (select count(*) from public.watched_items where user_id = owner_id)
    )
  );
end;
$$;

create or replace function public.sync_profile_pin_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    update public.profiles
    set pin_enabled = false, pin_hash = null, pin_updated_at = now(),
        failed_pin_attempts = 0, pin_locked_until = null
    where user_id = old.user_id and profile_index = old.profile_index;
    return old;
  end if;

  update public.profiles
  set pin_enabled = true, pin_hash = new.pin_hash, pin_updated_at = new.updated_at,
      failed_pin_attempts = new.failed_attempts, pin_locked_until = new.locked_until
  where user_id = new.user_id and profile_index = new.profile_index;
  return new;
end;
$$;

drop trigger if exists profile_pin_columns_sync on public.profile_pins;
create trigger profile_pin_columns_sync
after insert or update or delete on public.profile_pins
for each row execute function public.sync_profile_pin_columns();

update public.profile_pins set updated_at = updated_at;

create or replace function public.can_access_user_data(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(auth.uid() = p_user_id, false);
$$;

create or replace function public.cleanup_anonymous_users()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  user_ids uuid[];
  deleted_count integer := 0;
begin
  if not pg_try_advisory_lock(hashtext('cleanup_anonymous_users')) then return 0; end if;
  begin
    select array_agg(id) into user_ids
    from (
      select id from auth.users
      where is_anonymous and email is null and created_at < now() - interval '30 minutes'
      limit 500
    ) candidates;
    if user_ids is not null then
      delete from auth.sessions where user_id = any(user_ids);
      delete from auth.users where id = any(user_ids);
      deleted_count := coalesce(array_length(user_ids, 1), 0);
    end if;
    perform pg_advisory_unlock(hashtext('cleanup_anonymous_users'));
    return deleted_count;
  exception when others then
    perform pg_advisory_unlock(hashtext('cleanup_anonymous_users'));
    raise;
  end;
end;
$$;

create or replace function public.delete_profile_scoped_data(p_user_id uuid, p_profile_id integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null or p_profile_id is null then return; end if;
  delete from public.addons where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.plugins where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.collections where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.home_catalog_settings where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.profile_settings_blobs where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.profile_tracker_settings where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.provider_credentials where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.user_tracker_tokens where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.watch_progress where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.library_items where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.watched_items where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.library_item_events where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.watch_progress_events where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.watched_item_events where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.sync_push_audit_logs where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.user_activity_events where user_id = p_user_id and profile_id = p_profile_id;
  delete from public.profile_pins where user_id = p_user_id and profile_index = p_profile_id;
end;
$$;

create or replace function public.cleanup_profile_scoped_data_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.delete_profile_scoped_data(old.user_id, old.profile_index);
  return old;
end;
$$;

drop trigger if exists cleanup_profile_scoped_data_before_delete on public.profiles;
create trigger cleanup_profile_scoped_data_before_delete
before delete on public.profiles
for each row execute function public.cleanup_profile_scoped_data_on_delete();

create or replace function public.clear_profile_pin_with_account_password(
  p_account_password text,
  p_profile_id integer
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  owner_id uuid := public.require_sync_owner();
  encrypted_password text;
begin
  if p_profile_id not between 1 and 6 then raise exception 'Invalid profile id'; end if;
  if nullif(trim(p_account_password), '') is null then raise exception 'Account password is required'; end if;
  select encrypted_password into encrypted_password from auth.users where id = owner_id;
  if encrypted_password is null
     or extensions.crypt(p_account_password, encrypted_password) <> encrypted_password then
    raise exception 'Invalid account password';
  end if;
  delete from public.profile_pins where user_id = owner_id and profile_index = p_profile_id;
  update public.profiles
  set pin_enabled = false, pin_hash = null, pin_updated_at = now(),
      failed_pin_attempts = 0, pin_locked_until = null
  where user_id = owner_id and profile_index = p_profile_id;
  if not found then raise exception 'Profile not found for current user'; end if;
end;
$$;

create or replace function public.fix_watch_progress_key()
returns trigger
language plpgsql
as $$
begin
  if new.content_id in ('tmdb', 'kitsu') then
    if new.content_type = 'movie' and new.video_id ~ '^\d+$' then
      new.content_id := new.content_id || ':' || new.video_id;
      new.video_id := new.content_id;
    else
      return null;
    end if;
  end if;
  if new.season is not null and new.episode is not null then
    new.progress_key := new.content_id || '_s' || new.season || 'e' || new.episode;
  else
    new.progress_key := new.content_id;
  end if;
  return new;
end;
$$;

create or replace function public.record_watch_progress_delta_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    if exists (select 1 from auth.users where id = old.user_id) then
      insert into public.watch_progress_events(
        user_id, profile_id, operation, progress_key, content_id, content_type,
        video_id, season, episode, position, duration, last_watched
      ) values (
        old.user_id, old.profile_id, 'delete', old.progress_key, old.content_id,
        old.content_type, old.video_id, old.season, old.episode, old.position,
        old.duration, old.last_watched
      );
    end if;
    return old;
  end if;
  insert into public.watch_progress_events(
    user_id, profile_id, operation, progress_key, content_id, content_type,
    video_id, season, episode, position, duration, last_watched
  ) values (
    new.user_id, new.profile_id, 'upsert', new.progress_key, new.content_id,
    new.content_type, new.video_id, new.season, new.episode, new.position,
    new.duration, new.last_watched
  );
  return new;
end;
$$;

drop trigger if exists trg_fix_watch_progress_key on public.watch_progress;
create trigger trg_fix_watch_progress_key
before insert or update on public.watch_progress
for each row execute function public.fix_watch_progress_key();

drop trigger if exists watch_progress_delta_events_trigger on public.watch_progress;
create trigger watch_progress_delta_events_trigger
after insert or update or delete on public.watch_progress
for each row execute function public.record_watch_progress_delta_event();

create or replace function public.sync_push_watch_progress(
  p_entries jsonb,
  p_profile_id integer default 1,
  p_origin_client_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid := public.require_sync_owner();
  item jsonb;
begin
  if p_profile_id is null or p_profile_id not between 1 and 6 then
    raise exception 'Invalid profile id';
  end if;
  perform public.sync_set_origin_client_id(p_origin_client_id);
  for item in select value from jsonb_array_elements(coalesce(p_entries, '[]')) loop
    if btrim(coalesce(item->>'content_id', '')) = '' then continue; end if;
    insert into public.watch_progress(
      user_id, profile_id, content_id, content_type, video_id, season, episode,
      position, duration, last_watched, progress_key
    ) values (
      owner_id, p_profile_id, item->>'content_id', coalesce(item->>'content_type', ''),
      coalesce(item->>'video_id', ''), nullif(item->>'season', '')::integer,
      nullif(item->>'episode', '')::integer, coalesce(nullif(item->>'position', '')::bigint, 0),
      coalesce(nullif(item->>'duration', '')::bigint, 0),
      coalesce(nullif(item->>'last_watched', '')::bigint, 0), coalesce(item->>'progress_key', item->>'content_id')
    ) on conflict (user_id, profile_id, progress_key) do update set
      content_id = excluded.content_id, content_type = excluded.content_type,
      video_id = excluded.video_id, season = excluded.season, episode = excluded.episode,
      position = excluded.position, duration = excluded.duration, last_watched = excluded.last_watched;
  end loop;
end;
$$;

create or replace function public.sync_delete_watch_progress(
  p_keys jsonb,
  p_profile_id integer default 1,
  p_origin_client_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_profile_id is null or p_profile_id not between 1 and 6 then
    raise exception 'Invalid profile id';
  end if;
  perform public.sync_set_origin_client_id(p_origin_client_id);
  delete from public.watch_progress
  where user_id = public.require_sync_owner()
    and profile_id = p_profile_id
    and progress_key in (
      select key_value #>> '{}'
      from jsonb_array_elements(coalesce(p_keys, '[]')) as keys(key_value)
    );
end;
$$;

insert into public.watch_progress_events(
  user_id, profile_id, operation, progress_key, content_id, content_type,
  video_id, season, episode, position, duration, last_watched
)
select wp.user_id, wp.profile_id, 'upsert', wp.progress_key, wp.content_id,
       wp.content_type, wp.video_id, wp.season, wp.episode, wp.position,
       wp.duration, wp.last_watched
from public.watch_progress wp
where not exists (
  select 1 from public.watch_progress_events e
  where e.user_id = wp.user_id and e.profile_id = wp.profile_id
    and e.progress_key = wp.progress_key
);

create or replace function public.random_tv_login_code()
returns text
language sql
set search_path = public, extensions
as $$
  select encode(extensions.gen_random_bytes(16), 'hex');
$$;

create or replace function public.start_tracker_tv_login_session(
  p_tracker text,
  p_device_nonce text,
  p_redirect_base_url text
)
returns table(code text, web_url text, expires_at timestamptz, poll_interval_seconds integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  generated_code text;
  expiry timestamptz := now() + interval '5 minutes';
begin
  if lower(trim(coalesce(p_tracker, ''))) not in ('mal', 'anilist', 'kitsu')
     or length(coalesce(p_device_nonce, '')) < 8
     or nullif(trim(p_redirect_base_url), '') is null then
    raise exception 'Invalid tracker login request';
  end if;
  loop
    generated_code := upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.tracker_tv_login_sessions where code = generated_code);
  end loop;
  insert into public.tracker_tv_login_sessions(
    code, tracker, device_nonce, owner_user_id, redirect_base_url, expires_at
  ) values (
    generated_code, lower(trim(p_tracker)), p_device_nonce,
    public.require_sync_owner(), p_redirect_base_url, expiry
  );
  return query select generated_code,
    p_redirect_base_url || case when position('?' in p_redirect_base_url) > 0 then '&' else '?' end ||
      'code=' || generated_code || '&t=' || lower(trim(p_tracker)), expiry, 3;
end;
$$;

create or replace function public.poll_tracker_tv_login_session(
  p_tracker text,
  p_code text,
  p_device_nonce text
)
returns table(
  status text,
  access_token text,
  refresh_token text,
  expires_in integer,
  user_id text,
  username text,
  poll_interval_seconds integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  row_data public.tracker_tv_login_sessions%rowtype;
  result_status text;
begin
  select * into row_data from public.tracker_tv_login_sessions
  where code = upper(trim(p_code))
    and tracker = lower(trim(p_tracker))
    and device_nonce = p_device_nonce
  for update;
  if not found or row_data.expires_at <= now() then
    delete from public.tracker_tv_login_sessions where code = upper(trim(p_code));
    return query select 'expired', null::text, null::text, null::integer,
                        null::text, null::text, 3;
    return;
  end if;
  result_status := case when row_data.status = 'ready' then 'ready' else 'pending' end;
  if result_status = 'ready' then
    delete from public.tracker_tv_login_sessions where code = row_data.code;
    return query select 'ready', row_data.access_token, row_data.refresh_token,
                        row_data.expires_in, row_data.tracker_user_id,
                        row_data.tracker_username, 3;
  end if;
  return query select 'pending', null::text, null::text, null::integer,
                      null::text, null::text, 3;
end;
$$;

create or replace function public.upsert_tracker_tokens(
  p_profile_id integer,
  p_tracker text,
  p_access_token text,
  p_refresh_token text,
  p_expires_in_seconds integer,
  p_tracker_user_id text,
  p_username text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  tracker_name text := lower(trim(coalesce(p_tracker, '')));
begin
  if p_profile_id not between 1 and 6 then raise exception 'Invalid profile id'; end if;
  if tracker_name not in ('mal', 'anilist', 'kitsu') then raise exception 'Invalid tracker'; end if;
  if nullif(p_access_token, '') is null then raise exception 'Missing access_token'; end if;
  insert into public.user_tracker_tokens(
    user_id, profile_id, tracker, access_token, refresh_token, expires_at,
    tracker_user_id, tracker_username, updated_at
  ) values (
    public.require_sync_owner(), p_profile_id, tracker_name, p_access_token, p_refresh_token,
    case when p_expires_in_seconds is null then null else now() + make_interval(secs => p_expires_in_seconds) end,
    p_tracker_user_id, p_username, now()
  ) on conflict (user_id, profile_id, tracker) do update set
    access_token = excluded.access_token,
    refresh_token = coalesce(excluded.refresh_token, public.user_tracker_tokens.refresh_token),
    expires_at = excluded.expires_at,
    tracker_user_id = coalesce(excluded.tracker_user_id, public.user_tracker_tokens.tracker_user_id),
    tracker_username = coalesce(excluded.tracker_username, public.user_tracker_tokens.tracker_username),
    updated_at = now();
end;
$$;


create or replace function public.sync_pull_profile_locks()
returns table(profile_index integer, pin_enabled boolean, pin_locked_until timestamptz)
language sql
security definer
set search_path = public
as $$
  select p.profile_index,
         coalesce(p.pin_enabled, pp.user_id is not null, false),
         coalesce(p.pin_locked_until, pp.locked_until)
  from public.profiles p
  left join public.profile_pins pp
    on pp.user_id = p.user_id and pp.profile_index = p.profile_index
  where p.user_id = public.require_sync_owner()
  order by p.profile_index;
$$;

create or replace function public.get_sync_overview()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'addons', coalesce((select jsonb_object_agg(profile_id::text, count)
      from (select profile_id, count(*)::integer as count from public.addons
            where user_id = public.require_sync_owner() group by profile_id) rows), '{}'),
    'plugins', coalesce((select jsonb_object_agg(profile_id::text, count)
      from (select profile_id, count(*)::integer as count from public.plugins
            where user_id = public.require_sync_owner() group by profile_id) rows), '{}'),
    'library_items', coalesce((select jsonb_object_agg(profile_id::text, count)
      from (select profile_id, count(*)::integer as count from public.library_items
            where user_id = public.require_sync_owner() group by profile_id) rows), '{}'),
    'watch_progress', coalesce((select jsonb_object_agg(profile_id::text, count)
      from (select profile_id, count(distinct content_id)::integer as count from public.watch_progress
            where user_id = public.require_sync_owner() group by profile_id) rows), '{}'),
    'watched_items', coalesce((select jsonb_object_agg(profile_id::text, count)
      from (select profile_id, count(distinct content_id)::integer as count from public.watched_items
            where user_id = public.require_sync_owner() group by profile_id) rows), '{}'),
    'profiles', coalesce((select jsonb_object_agg(profile_index::text,
                       jsonb_build_object('name', name, 'color', avatar_color_hex))
      from public.profiles where user_id = public.require_sync_owner()), '{}'),
    'profile_tracker_settings', coalesce((select jsonb_object_agg(profile_id::text, count)
      from (select profile_id, count(*)::integer as count from public.profile_tracker_settings
            where user_id = public.require_sync_owner() group by profile_id) rows), '{}')
  );
$$;

create or replace function public.list_my_sessions()
returns table(
  session_id uuid,
  created_at timestamptz,
  last_active_at timestamptz,
  client_name text,
  client_version text,
  platform text,
  device_name text,
  user_agent text,
  is_current boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.created_at,
         greatest(d.last_seen_at, s.refreshed_at at time zone 'UTC', s.updated_at, s.created_at),
         d.client_name, d.client_version, d.platform, d.device_name,
         left(s.user_agent, 512), s.id = nullif(auth.jwt() ->> 'session_id', '')::uuid
  from public.user_session_devices d
  join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
  where d.user_id = auth.uid() and (s.not_after is null or s.not_after > now())
  order by is_current desc, last_active_at desc;
$$;

create or replace function public.register_current_device(
  p_installation_id text,
  p_client_name text,
  p_client_version text default null,
  p_platform text default null,
  p_device_name text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  owner_id uuid := auth.uid();
begin
  if owner_id is null or session_id is null then raise exception 'Authentication required'; end if;
  if p_installation_id is null or length(p_installation_id) not between 16 and 96 then
    raise exception 'Invalid installation id';
  end if;
  insert into public.user_session_devices(
    session_id, user_id, client_name, client_version, platform, device_name, installation_id, last_seen_at
  ) values (
    session_id, owner_id, left(p_client_name, 80), left(nullif(trim(p_client_version), ''), 40),
    left(coalesce(nullif(trim(p_platform), ''), 'Unknown'), 80),
    left(nullif(trim(p_device_name), ''), 160), p_installation_id, now()
  ) on conflict (user_id, installation_id) do update set
    session_id = excluded.session_id, client_name = excluded.client_name,
    client_version = excluded.client_version, platform = excluded.platform,
    device_name = excluded.device_name, last_seen_at = now();
  return true;
end;
$$;

create or replace function public.register_current_session(
  p_client_name text,
  p_client_version text default null,
  p_platform text default null,
  p_device_name text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_session text := nullif(auth.jwt() ->> 'session_id', '');
begin
  if current_session is null then raise exception 'Authentication required'; end if;
  return public.register_current_device(
    'nuvio-session-' || replace(current_session, '-', ''),
    p_client_name, p_client_version, p_platform, p_device_name
  );
end;
$$;

create or replace function public.revoke_my_session(p_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid then
    raise exception 'Use local sign out for the current session';
  end if;
  delete from auth.sessions where id = p_session_id and user_id = auth.uid();
  return found;
end;
$$;

create or replace function public.expire_old_tv_login_sessions()
returns void
language sql
security definer
set search_path = public
as $$
  update public.tv_login_sessions set status = 'expired'
  where status = 'pending' and expires_at <= now();
$$;

create or replace function public.approve_tv_login_session(p_code text)
returns table(success boolean, message text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  perform public.expire_old_tv_login_sessions();
  update public.tv_login_sessions
  set status = 'approved', approved_user_id = auth.uid(), approved_at = now()
  where code = upper(trim(p_code)) and status = 'pending' and expires_at > now();
  if not found then return query select false, 'Invalid or expired TV login code'; return; end if;
  return query select true, 'TV login approved';
end;
$$;

create or replace function public.consume_tv_login_session(p_code text, p_device_nonce text)
returns table(approved_user_id uuid)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  row_data public.tv_login_sessions%rowtype;
begin
  perform public.expire_old_tv_login_sessions();
  select * into row_data from public.tv_login_sessions
  where code = upper(trim(p_code))
    and requester_user_id = auth.uid()
    and device_nonce_hash = encode(extensions.digest(p_device_nonce, 'sha256'), 'hex')
    and status = 'approved' and expires_at > now()
  for update;
  if not found then raise exception 'TV login not approved or expired'; end if;
  update public.tv_login_sessions set status = 'exchanged', exchanged_at = now()
  where code = row_data.code;
  return query select row_data.approved_user_id;
end;
$$;

create or replace function public.get_avatar_catalog()
returns table(
  id text,
  display_name text,
  storage_path text,
  category text,
  sort_order integer,
  bg_color text
)
language sql
stable
security definer
set search_path = public
as $$
  select ac.id, ac.display_name, ac.storage_path, ac.category, ac.sort_order, ac.bg_color
  from public.avatar_catalog ac
  where coalesce(ac.is_active, ac.enabled)
  order by ac.category, ac.sort_order, ac.display_name;
$$;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', true, 5242880,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets(id, name, public, file_size_limit)
values ('covers', 'covers', true, 5242880)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Public avatar read access" on storage.objects;
create policy "Public avatar read access"
on storage.objects for select to public
using (bucket_id = 'avatars');

insert into public.avatar_catalog(
  id, display_name, storage_path, category, sort_order, enabled, is_active, bg_color
)
values
  ('avatar_aang', 'Aang', 'avatar_aang_1772809370453.png', 'animation', 1, true, true, '#0060F8'),
  ('avatar_katara', 'Katara', 'avatar_katara_1772809386366.png', 'animation', 18, true, true, '#00A0A8'),
  ('avatar_ash', 'Ash', 'avatar_ash_1772809405294.png', 'anime', 3, true, true, '#E00808'),
  ('avatar_chihiro', 'Chihiro', 'avatar_chihiro_1772809422792.png', 'anime', 4, true, true, '#88E070'),
  ('avatar_eren', 'Eren', 'avatar_eren_1772808836514.png', 'anime', 8, true, true, '#900018'),
  ('avatar_gojo', 'Gojo', 'avatar_gojo_1772826847969.png', 'anime', 11, true, true, '#00F8F8'),
  ('avatar_goku', 'Goku', 'avatar_goku_1772786622108.png', 'anime', 12, true, true, '#F84000'),
  ('avatar_jinwoo', 'Jinwoo', 'avatar_jinwoo_1772808878532.png', 'anime', 15, true, true, '#0058F8'),
  ('avatar_killua', 'Killua', 'avatar_killua_1772826924033.png', 'anime', 19, true, true, '#0030F8'),
  ('avatar_levi', 'Levi', 'avatar_levi_1772826833149.png', 'anime', 23, true, true, '#484848'),
  ('avatar_mikasa', 'Mikasa', 'avatar_mikasa_1772808997012.png', 'anime', 24, true, true, '#007870'),
  ('avatar_naruto', 'Naruto', 'avatar_naruto_1772786640402.png', 'anime', 25, true, true, '#D8F800'),
  ('avatar_saitama', 'Saitama', 'avatar_saitama_1772826938248.png', 'anime', 29, true, true, '#F8D000'),
  ('avatar_arthur_morgan', 'Arthur Morgan', 'avatar_arthur_morgan_1772786328141.png', 'gaming', 2, true, true, '#B01028'),
  ('avatar_geralt', 'Geralt', 'avatar_geralt_1772826884310.png', 'gaming', 10, true, true, '#380070'),
  ('avatar_kratos', 'Kratos', 'avatar_kratos_1772826869090.png', 'gaming', 20, true, true, '#880000'),
  ('avatar_lara', 'Lara', 'avatar_lara_1772826963671.png', 'gaming', 22, true, true, '#008878'),
  ('avatar_v', 'V', 'avatar_v_1772827227584.png', 'gaming', 32, true, true, '#000830'),
  ('avatar_linear_woman_teal', 'Lin', 'avatar_linear_teal_v3.png', 'linear', 35, true, true, '#008080'),
  ('avatar_linear_man_purple', 'Max', 'avatar_linear_purple_v3.png', 'linear', 36, true, true, '#6B21A8'),
  ('avatar_linear_woman_red', 'Ava', 'avatar_linear_red_v3.png', 'linear', 37, true, true, '#E11D48'),
  ('avatar_linear_man_navy', 'Theo', 'avatar_linear_navy_v3.png', 'linear', 38, true, true, '#1E3A5F'),
  ('avatar_linear_woman_yellow', 'Zara', 'avatar_linear_yellow_v3.png', 'linear', 39, true, true, '#D97706'),
  ('avatar_linear_man_green', 'Kai', 'avatar_linear_green_v3.png', 'linear', 40, true, true, '#065F46'),
  ('avatar_linear_woman_pink', 'Nova', 'avatar_linear_pink_v3.png', 'linear', 41, true, true, '#BE185D'),
  ('avatar_furiosa', 'Furiosa', 'avatar_furiosa_1772827439561.png', 'movie', 9, true, true, '#D08848'),
  ('avatar_harry_potter', 'Harry Potter', 'avatar_harry_potter_1772786358133.png', 'movie', 13, true, true, '#F8B000'),
  ('avatar_jack_sparrow', 'Jack Sparrow', 'avatar_jack_sparrow_1772786396797.png', 'movie', 14, true, true, '#F8F8F8'),
  ('avatar_neo', 'Neo', 'avatar_neo_1772786377143.png', 'movie', 27, true, true, '#88F800'),
  ('avatar_daenerys', 'Daenerys', 'avatar_daenerys_1772786201651.png', 'tv', 5, true, true, '#00B8D8'),
  ('avatar_dexter', 'Dexter', 'avatar_dexter_1772808898372.png', 'tv', 6, true, true, '#A80808'),
  ('avatar_eleven', 'Eleven', 'avatar_eleven_1772785893766.png', 'tv', 7, true, true, '#8800F8'),
  ('avatar_joel', 'Joel', 'avatar_joel_1772827212455.png', 'tv', 16, true, true, '#102010'),
  ('avatar_jon_snow', 'Jon Snow', 'avatar_jon_snow_1772786050374.png', 'tv', 17, true, true, '#004090'),
  ('avatar_lalo', 'Lalo', 'avatar_lalo_1772808914536.png', 'tv', 21, true, true, '#E09018'),
  ('avatar_negan', 'Negan', 'avatar_negan_1772808934794.png', 'tv', 26, true, true, '#780078'),
  ('avatar_rick_grimes', 'Rick Grimes', 'avatar_rick_grimes_1772786275264.png', 'tv', 28, true, true, '#C85018'),
  ('avatar_saul_goodman', 'Saul Goodman', 'avatar_saul_goodman_1772786019049.png', 'tv', 30, true, true, '#F84000'),
  ('avatar_tommy_shelby', 'Tommy Shelby', 'avatar_tommy_shelby_1772786000275.png', 'tv', 31, true, true, '#F83040'),
  ('avatar_walter_white', 'Walter White', 'avatar_walter_white_1772785927308.png', 'tv', 33, true, true, '#F8C000'),
  ('avatar_wednesday', 'Wednesday', 'avatar_wednesday_1772786225606.png', 'tv', 34, true, true, '#500840')
on conflict (id) do update set
  display_name = excluded.display_name,
  storage_path = excluded.storage_path,
  category = excluded.category,
  sort_order = excluded.sort_order,
  enabled = excluded.enabled,
  is_active = excluded.is_active,
  bg_color = excluded.bg_color;

alter table public.profile_tracker_settings enable row level security;
alter table public.user_tracker_tokens enable row level security;
alter table public.library_item_events enable row level security;
alter table public.sync_push_audit_logs enable row level security;
alter table public.sync_invalidations enable row level security;
alter table public.tracker_tv_login_sessions enable row level security;
alter table public.user_activity_events enable row level security;
alter table public.user_session_devices enable row level security;

grant usage on schema public to anon, authenticated;
grant execute on all functions in schema public to authenticated;
grant execute on function public.get_avatar_catalog() to anon;
grant execute on function public.health_ping() to anon;
grant select on public.avatar_catalog to anon, authenticated;

-- These functions exist to support triggers or server-side maintenance only.
-- Do not expose helpers that accept arbitrary account IDs to client JWTs.
revoke execute on function public.cleanup_anonymous_users() from anon, authenticated;
revoke execute on function public.delete_profile_scoped_data(uuid, integer) from anon, authenticated;
revoke execute on function public.cleanup_profile_scoped_data_on_delete() from anon, authenticated;
revoke execute on function public.emit_sync_invalidation(uuid, integer, text, jsonb) from anon, authenticated;
revoke execute on function public.handle_new_profile_default_addons() from anon, authenticated;
revoke execute on function public.handle_new_user_default_addons() from anon, authenticated;
revoke execute on function public.nuvio_default_catalog_url() from anon, authenticated;
revoke execute on function public.fix_watch_progress_key() from anon, authenticated;
revoke execute on function public.record_library_item_delta_event() from anon, authenticated;
revoke execute on function public.record_watch_progress_delta_event() from anon, authenticated;
revoke execute on function public.set_updated_at() from anon, authenticated;
revoke execute on function public.sync_profile_identity_columns() from anon, authenticated;
revoke execute on function public.sync_profile_pin_columns() from anon, authenticated;

notify pgrst, 'reload schema';
