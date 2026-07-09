-- NuvioTV compatible Supabase backend.
-- This is a clean-room implementation derived from the Android client RPC/table contracts.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.linked_devices (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  device_user_id uuid not null references auth.users(id) on delete cascade,
  device_name text,
  linked_at timestamptz not null default now(),
  unique (owner_id, device_user_id)
);

create table if not exists public.profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_index integer not null check (profile_index between 1 and 20),
  name text not null default '',
  avatar_color_hex text not null default '#1E88E5',
  uses_primary_addons boolean not null default false,
  uses_primary_plugins boolean not null default false,
  avatar_id text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_index)
);

create table if not exists public.profile_pins (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_index integer not null,
  pin_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_index)
);

create table if not exists public.plugins (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  url text not null,
  name text,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  profile_id integer not null default 1,
  repo_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id, url)
);

create table if not exists public.addons (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  url text not null,
  name text,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  profile_id integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id, url)
);

create table if not exists public.library_items (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id, content_id, content_type)
);

create table if not exists public.watch_progress (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
  content_id text not null,
  content_type text not null,
  video_id text not null default '',
  season integer,
  episode integer,
  position bigint not null default 0,
  duration bigint not null default 0,
  last_watched bigint not null default 0,
  progress_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id, progress_key)
);

create table if not exists public.watch_progress_events (
  event_id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
  operation text not null check (operation in ('upsert', 'delete')),
  progress_key text not null,
  content_id text not null default '',
  content_type text not null default '',
  video_id text not null default '',
  season integer,
  episode integer,
  position bigint not null default 0,
  duration bigint not null default 0,
  last_watched bigint not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.watched_items (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
  content_id text not null,
  content_type text not null,
  title text not null default '',
  season integer,
  episode integer,
  season_key integer generated always as (coalesce(season, -1)) stored,
  episode_key integer generated always as (coalesce(episode, -1)) stored,
  watched_at bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id, content_id, content_type, season_key, episode_key)
);

create table if not exists public.watched_item_events (
  event_id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
  operation text not null check (operation in ('upsert', 'delete')),
  content_id text not null,
  content_type text not null default '',
  title text not null default '',
  season integer,
  episode integer,
  watched_at bigint not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.collections (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
  collections_json jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id)
);

create table if not exists public.home_catalog_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
  platform text not null default 'home_catalog_shared',
  settings_json jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id, platform)
);

create table if not exists public.profile_settings_blobs (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id integer not null default 1,
  platform text not null default 'tv',
  settings_json jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id, platform)
);

create table if not exists public.sync_codes (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  code text not null unique,
  pin_hash text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.avatar_catalog (
  id text primary key,
  display_name text not null,
  storage_path text not null,
  category text not null default 'default',
  sort_order integer not null default 0,
  bg_color text,
  enabled boolean not null default true
);

create table if not exists public.tv_login_sessions (
  code text primary key,
  requester_user_id uuid not null references auth.users(id) on delete cascade,
  device_nonce_hash text not null,
  device_name text,
  redirect_base_url text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'exchanged', 'expired')),
  approved_user_id uuid references auth.users(id) on delete cascade,
  approved_access_token text,
  approved_refresh_token text,
  token_type text,
  expires_in bigint,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  approved_at timestamptz,
  exchanged_at timestamptz
);

create index if not exists idx_linked_devices_device on public.linked_devices(device_user_id);
create index if not exists idx_plugins_user_profile on public.plugins(user_id, profile_id, sort_order);
create index if not exists idx_addons_user_profile on public.addons(user_id, profile_id, sort_order);
create index if not exists idx_library_user_profile on public.library_items(user_id, profile_id, added_at desc);
create index if not exists idx_watch_progress_user_profile on public.watch_progress(user_id, profile_id, last_watched desc);
create index if not exists idx_watch_progress_events_owner_cursor on public.watch_progress_events(user_id, profile_id, event_id);
create index if not exists idx_watched_items_user_profile on public.watched_items(user_id, profile_id, watched_at desc);
create index if not exists idx_watched_item_events_owner_cursor on public.watched_item_events(user_id, profile_id, event_id);
create index if not exists idx_tv_login_requester on public.tv_login_sessions(requester_user_id, code);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists profile_pins_set_updated_at on public.profile_pins;
create trigger profile_pins_set_updated_at before update on public.profile_pins
for each row execute function public.set_updated_at();

drop trigger if exists plugins_set_updated_at on public.plugins;
create trigger plugins_set_updated_at before update on public.plugins
for each row execute function public.set_updated_at();

drop trigger if exists addons_set_updated_at on public.addons;
create trigger addons_set_updated_at before update on public.addons
for each row execute function public.set_updated_at();

drop trigger if exists library_items_set_updated_at on public.library_items;
create trigger library_items_set_updated_at before update on public.library_items
for each row execute function public.set_updated_at();

drop trigger if exists watch_progress_set_updated_at on public.watch_progress;
create trigger watch_progress_set_updated_at before update on public.watch_progress
for each row execute function public.set_updated_at();

drop trigger if exists watched_items_set_updated_at on public.watched_items;
create trigger watched_items_set_updated_at before update on public.watched_items
for each row execute function public.set_updated_at();

create or replace function public.can_access_owner(p_owner uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select auth.uid() = p_owner
    or exists (
      select 1
      from public.linked_devices ld
      where ld.owner_id = p_owner
        and ld.device_user_id = auth.uid()
    );
$$;

create or replace function public.current_sync_owner()
returns uuid
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (
      select ld.owner_id
      from public.linked_devices ld
      where ld.device_user_id = auth.uid()
      order by ld.linked_at desc
      limit 1
    ),
    auth.uid()
  );
$$;

create or replace function public.require_sync_owner()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  v_owner := public.current_sync_owner();
  if v_owner is null then
    raise exception 'Not authenticated';
  end if;
  return v_owner;
end;
$$;

create or replace function public.random_digit_code()
returns text
language plpgsql
set search_path = public, extensions
as $$
begin
  return lpad(floor(random() * 1000000)::integer::text, 6, '0');
end;
$$;

create or replace function public.random_login_code()
returns text
language plpgsql
set search_path = public, extensions
as $$
begin
  return upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6));
end;
$$;

alter table public.linked_devices enable row level security;
alter table public.profiles enable row level security;
alter table public.profile_pins enable row level security;
alter table public.plugins enable row level security;
alter table public.addons enable row level security;
alter table public.library_items enable row level security;
alter table public.watch_progress enable row level security;
alter table public.watch_progress_events enable row level security;
alter table public.watched_items enable row level security;
alter table public.watched_item_events enable row level security;
alter table public.collections enable row level security;
alter table public.home_catalog_settings enable row level security;
alter table public.profile_settings_blobs enable row level security;
alter table public.sync_codes enable row level security;
alter table public.avatar_catalog enable row level security;
alter table public.tv_login_sessions enable row level security;

drop policy if exists linked_devices_select on public.linked_devices;
create policy linked_devices_select on public.linked_devices
for select using (public.can_access_owner(owner_id));

drop policy if exists owner_select_profiles on public.profiles;
create policy owner_select_profiles on public.profiles
for select using (public.can_access_owner(user_id));

drop policy if exists owner_select_plugins on public.plugins;
create policy owner_select_plugins on public.plugins
for select using (public.can_access_owner(user_id));

drop policy if exists owner_select_addons on public.addons;
create policy owner_select_addons on public.addons
for select using (public.can_access_owner(user_id));

drop policy if exists avatar_catalog_public_select on public.avatar_catalog;
create policy avatar_catalog_public_select on public.avatar_catalog
for select using (enabled);

create or replace function public.get_sync_owner()
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.require_sync_owner();
$$;

create or replace function public.generate_sync_code(p_pin text)
returns table(code text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner uuid := auth.uid();
  v_code text;
begin
  if v_owner is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce(length(trim(p_pin)), 0) < 4 then
    raise exception 'PIN must be at least 4 digits';
  end if;

  loop
    v_code := public.random_digit_code();
    exit when not exists (select 1 from public.sync_codes sc where sc.code = v_code);
  end loop;

  insert into public.sync_codes(owner_id, code, pin_hash, expires_at, created_at)
  values (v_owner, v_code, extensions.crypt(p_pin, extensions.gen_salt('bf')), now() + interval '15 minutes', now())
  on conflict (owner_id) do update
    set code = excluded.code,
        pin_hash = excluded.pin_hash,
        expires_at = excluded.expires_at,
        created_at = excluded.created_at;

  return query select v_code;
end;
$$;

create or replace function public.get_sync_code(p_pin text)
returns table(code text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner uuid := auth.uid();
  v_row public.sync_codes%rowtype;
begin
  if v_owner is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_row
  from public.sync_codes sc
  where sc.owner_id = v_owner
    and sc.expires_at > now();

  if not found or v_row.pin_hash <> extensions.crypt(p_pin, v_row.pin_hash) then
    return;
  end if;

  return query select v_row.code;
end;
$$;

create or replace function public.claim_sync_code(p_code text, p_pin text, p_device_name text default null)
returns table(result_owner_id uuid, success boolean, message text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_device uuid := auth.uid();
  v_row public.sync_codes%rowtype;
begin
  if v_device is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_row
  from public.sync_codes sc
  where sc.code = upper(trim(p_code))
     or sc.code = trim(p_code)
  order by sc.created_at desc
  limit 1;

  if not found or v_row.expires_at <= now() then
    return query select null::uuid, false, 'Sync code expired or not found';
    return;
  end if;

  if v_row.pin_hash <> extensions.crypt(p_pin, v_row.pin_hash) then
    return query select null::uuid, false, 'Invalid PIN';
    return;
  end if;

  insert into public.linked_devices(owner_id, device_user_id, device_name, linked_at)
  values (v_row.owner_id, v_device, nullif(trim(coalesce(p_device_name, '')), ''), now())
  on conflict (owner_id, device_user_id) do update
    set device_name = excluded.device_name,
        linked_at = excluded.linked_at;

  delete from public.sync_codes where owner_id = v_row.owner_id;

  return query select v_row.owner_id, true, 'Device linked';
end;
$$;

create or replace function public.unlink_device(p_device_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := auth.uid();
begin
  if v_owner is null then
    raise exception 'Not authenticated';
  end if;
  delete from public.linked_devices
  where owner_id = v_owner
    and device_user_id = p_device_user_id;
end;
$$;

create or replace function public.sync_push_plugins(p_plugins jsonb, p_profile_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  item jsonb;
begin
  delete from public.plugins where user_id = v_owner and profile_id = p_profile_id;

  for item in select * from jsonb_array_elements(coalesce(p_plugins, '[]'::jsonb)) loop
    insert into public.plugins(user_id, profile_id, url, name, enabled, sort_order, repo_type)
    values (
      v_owner,
      p_profile_id,
      item->>'url',
      nullif(item->>'name', ''),
      coalesce((item->>'enabled')::boolean, true),
      coalesce((item->>'sort_order')::integer, 0),
      nullif(item->>'repo_type', '')
    );
  end loop;
end;
$$;

create or replace function public.sync_push_addons(p_addons jsonb, p_profile_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  item jsonb;
begin
  delete from public.addons where user_id = v_owner and profile_id = p_profile_id;

  for item in select * from jsonb_array_elements(coalesce(p_addons, '[]'::jsonb)) loop
    insert into public.addons(user_id, profile_id, url, name, enabled, sort_order)
    values (
      v_owner,
      p_profile_id,
      item->>'url',
      nullif(item->>'name', ''),
      coalesce((item->>'enabled')::boolean, true),
      coalesce((item->>'sort_order')::integer, 0)
    );
  end loop;
end;
$$;

create or replace function public.sync_push_library(p_items jsonb, p_profile_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  item jsonb;
begin
  delete from public.library_items where user_id = v_owner and profile_id = p_profile_id;

  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    insert into public.library_items(
      user_id, profile_id, content_id, content_type, name, poster, poster_shape,
      background, description, release_info, imdb_rating, genres, addon_base_url, added_at
    )
    values (
      v_owner,
      p_profile_id,
      item->>'content_id',
      item->>'content_type',
      coalesce(item->>'name', ''),
      item->>'poster',
      coalesce(item->>'poster_shape', 'POSTER'),
      item->>'background',
      item->>'description',
      item->>'release_info',
      (item->>'imdb_rating')::real,
      array(select jsonb_array_elements_text(coalesce(item->'genres', '[]'::jsonb))),
      item->>'addon_base_url',
      coalesce((item->>'added_at')::bigint, 0)
    );
  end loop;
end;
$$;

create or replace function public.sync_pull_library(p_profile_id integer default 1, p_limit integer default 500, p_offset integer default 0)
returns table(
  id uuid,
  user_id uuid,
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
  added_at bigint,
  profile_id integer
)
language sql
security definer
set search_path = public
as $$
  select li.id, li.user_id, li.content_id, li.content_type, li.name, li.poster,
         li.poster_shape, li.background, li.description, li.release_info,
         li.imdb_rating, li.genres, li.addon_base_url, li.added_at, li.profile_id
  from public.library_items li
  where li.user_id = public.require_sync_owner()
    and li.profile_id = p_profile_id
  order by li.added_at desc, li.updated_at desc
  limit greatest(coalesce(p_limit, 500), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.sync_push_watch_progress(p_entries jsonb, p_profile_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  item jsonb;
begin
  for item in select * from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) loop
    insert into public.watch_progress(
      user_id, profile_id, content_id, content_type, video_id, season, episode,
      position, duration, last_watched, progress_key
    )
    values (
      v_owner,
      p_profile_id,
      item->>'content_id',
      item->>'content_type',
      coalesce(item->>'video_id', ''),
      (item->>'season')::integer,
      (item->>'episode')::integer,
      coalesce((item->>'position')::bigint, 0),
      coalesce((item->>'duration')::bigint, 0),
      coalesce((item->>'last_watched')::bigint, 0),
      item->>'progress_key'
    )
    on conflict (user_id, profile_id, progress_key) do update
      set content_id = excluded.content_id,
          content_type = excluded.content_type,
          video_id = excluded.video_id,
          season = excluded.season,
          episode = excluded.episode,
          position = excluded.position,
          duration = excluded.duration,
          last_watched = excluded.last_watched;

    insert into public.watch_progress_events(
      user_id, profile_id, operation, progress_key, content_id, content_type,
      video_id, season, episode, position, duration, last_watched
    )
    values (
      v_owner,
      p_profile_id,
      'upsert',
      item->>'progress_key',
      item->>'content_id',
      item->>'content_type',
      coalesce(item->>'video_id', ''),
      (item->>'season')::integer,
      (item->>'episode')::integer,
      coalesce((item->>'position')::bigint, 0),
      coalesce((item->>'duration')::bigint, 0),
      coalesce((item->>'last_watched')::bigint, 0)
    );
  end loop;
end;
$$;

create or replace function public.sync_pull_watch_progress(
  p_profile_id integer default 1,
  p_since_last_watched bigint default null,
  p_limit integer default null
)
returns table(
  id uuid,
  user_id uuid,
  content_id text,
  content_type text,
  video_id text,
  season integer,
  episode integer,
  "position" bigint,
  duration bigint,
  last_watched bigint,
  progress_key text,
  profile_id integer
)
language sql
security definer
set search_path = public
as $$
  select wp.id, wp.user_id, wp.content_id, wp.content_type, wp.video_id, wp.season,
         wp.episode, wp.position, wp.duration, wp.last_watched, wp.progress_key, wp.profile_id
  from public.watch_progress wp
  where wp.user_id = public.require_sync_owner()
    and wp.profile_id = p_profile_id
    and (p_since_last_watched is null or wp.last_watched > p_since_last_watched)
  order by wp.last_watched desc
  limit coalesce(p_limit, 2147483647);
$$;

create or replace function public.sync_delete_watch_progress(p_keys jsonb, p_profile_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  key_text text;
  old_row public.watch_progress%rowtype;
begin
  for key_text in select jsonb_array_elements_text(coalesce(p_keys, '[]'::jsonb)) loop
    for old_row in
      delete from public.watch_progress wp
      where wp.user_id = v_owner
        and wp.profile_id = p_profile_id
        and wp.progress_key = key_text
      returning *
    loop
      insert into public.watch_progress_events(
        user_id, profile_id, operation, progress_key, content_id, content_type,
        video_id, season, episode, position, duration, last_watched
      )
      values (
        v_owner,
        p_profile_id,
        'delete',
        key_text,
        old_row.content_id,
        old_row.content_type,
        old_row.video_id,
        old_row.season,
        old_row.episode,
        old_row.position,
        old_row.duration,
        old_row.last_watched
      );
    end loop;
  end loop;
end;
$$;

create or replace function public.sync_get_watch_progress_delta_cursor(p_profile_id integer default 1)
returns bigint
language sql
security definer
set search_path = public
as $$
  select coalesce(max(event_id), 0)
  from public.watch_progress_events
  where user_id = public.require_sync_owner()
    and profile_id = p_profile_id;
$$;

create or replace function public.sync_pull_watch_progress_delta(p_profile_id integer default 1, p_since_event_id bigint default 0, p_limit integer default 900)
returns table(
  event_id bigint,
  operation text,
  progress_key text,
  content_id text,
  content_type text,
  video_id text,
  season integer,
  episode integer,
  "position" bigint,
  duration bigint,
  last_watched bigint
)
language sql
security definer
set search_path = public
as $$
  select e.event_id, e.operation, e.progress_key, e.content_id, e.content_type,
         e.video_id, e.season, e.episode, e.position, e.duration, e.last_watched
  from public.watch_progress_events e
  where e.user_id = public.require_sync_owner()
    and e.profile_id = p_profile_id
    and e.event_id > coalesce(p_since_event_id, 0)
  order by e.event_id asc
  limit greatest(coalesce(p_limit, 900), 1);
$$;

create or replace function public.sync_push_watched_items(p_items jsonb, p_profile_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  item jsonb;
begin
  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    insert into public.watched_items(
      user_id, profile_id, content_id, content_type, title, season, episode, watched_at
    )
    values (
      v_owner,
      p_profile_id,
      item->>'content_id',
      item->>'content_type',
      coalesce(item->>'title', ''),
      (item->>'season')::integer,
      (item->>'episode')::integer,
      coalesce((item->>'watched_at')::bigint, 0)
    )
    on conflict (user_id, profile_id, content_id, content_type, season_key, episode_key) do update
      set title = excluded.title,
          watched_at = excluded.watched_at;

    insert into public.watched_item_events(
      user_id, profile_id, operation, content_id, content_type, title, season, episode, watched_at
    )
    values (
      v_owner,
      p_profile_id,
      'upsert',
      item->>'content_id',
      item->>'content_type',
      coalesce(item->>'title', ''),
      (item->>'season')::integer,
      (item->>'episode')::integer,
      coalesce((item->>'watched_at')::bigint, 0)
    );
  end loop;
end;
$$;

create or replace function public.sync_pull_watched_items(p_profile_id integer default 1, p_page integer default 1, p_page_size integer default 900)
returns table(
  id uuid,
  user_id uuid,
  content_id text,
  content_type text,
  title text,
  season integer,
  episode integer,
  watched_at bigint,
  profile_id integer
)
language sql
security definer
set search_path = public
as $$
  select wi.id, wi.user_id, wi.content_id, wi.content_type, wi.title,
         wi.season, wi.episode, wi.watched_at, wi.profile_id
  from public.watched_items wi
  where wi.user_id = public.require_sync_owner()
    and wi.profile_id = p_profile_id
  order by wi.watched_at desc
  limit greatest(coalesce(p_page_size, 900), 1)
  offset greatest(coalesce(p_page, 1) - 1, 0) * greatest(coalesce(p_page_size, 900), 1);
$$;

create or replace function public.sync_delete_watched_items(p_keys jsonb, p_profile_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.require_sync_owner();
  key jsonb;
  old_row public.watched_items%rowtype;
begin
  for key in select * from jsonb_array_elements(coalesce(p_keys, '[]'::jsonb)) loop
    for old_row in
      delete from public.watched_items wi
      where wi.user_id = v_owner
        and wi.profile_id = p_profile_id
        and wi.content_id = key->>'content_id'
        and coalesce(wi.season, -1) = coalesce((key->>'season')::integer, -1)
        and coalesce(wi.episode, -1) = coalesce((key->>'episode')::integer, -1)
      returning *
    loop
      insert into public.watched_item_events(
        user_id, profile_id, operation, content_id, content_type, title, season, episode, watched_at
      )
      values (
        v_owner,
        p_profile_id,
        'delete',
        old_row.content_id,
        old_row.content_type,
        old_row.title,
        old_row.season,
        old_row.episode,
        old_row.watched_at
      );
    end loop;
  end loop;
end;
$$;

create or replace function public.sync_get_watched_items_delta_cursor(p_profile_id integer default 1)
returns bigint
language sql
security definer
set search_path = public
as $$
  select coalesce(max(event_id), 0)
  from public.watched_item_events
  where user_id = public.require_sync_owner()
    and profile_id = p_profile_id;
$$;

create or replace function public.sync_pull_watched_items_delta(p_profile_id integer default 1, p_since_event_id bigint default 0, p_limit integer default 900)
returns table(
  event_id bigint,
  operation text,
  content_id text,
  content_type text,
  title text,
  season integer,
  episode integer,
  watched_at bigint
)
language sql
security definer
set search_path = public
as $$
  select e.event_id, e.operation, e.content_id, e.content_type, e.title,
         e.season, e.episode, e.watched_at
  from public.watched_item_events e
  where e.user_id = public.require_sync_owner()
    and e.profile_id = p_profile_id
    and e.event_id > coalesce(p_since_event_id, 0)
  order by e.event_id asc
  limit greatest(coalesce(p_limit, 900), 1);
$$;

create or replace function public.sync_push_profiles(p_profiles jsonb, p_client_max_profiles integer default 5)
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
begin
  for item in select * from jsonb_array_elements(coalesce(p_profiles, '[]'::jsonb)) loop
    idx := (item->>'profile_index')::integer;
    if idx is null or idx < 1 or idx > greatest(coalesce(p_client_max_profiles, 5), 1) then
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

  if array_length(keep_ids, 1) is not null then
    delete from public.profiles
    where user_id = v_owner
      and profile_index <> all(keep_ids);
  end if;
end;
$$;

create or replace function public.sync_pull_profiles()
returns table(
  id uuid,
  user_id uuid,
  profile_index integer,
  name text,
  avatar_color_hex text,
  uses_primary_addons boolean,
  uses_primary_plugins boolean,
  avatar_id text,
  avatar_url text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.user_id, p.profile_index, p.name, p.avatar_color_hex,
         p.uses_primary_addons, p.uses_primary_plugins, p.avatar_id,
         p.avatar_url, p.created_at, p.updated_at
  from public.profiles p
  where p.user_id = public.require_sync_owner()
  order by p.profile_index asc;
$$;

create or replace function public.sync_delete_profile_data(p_profile_id integer)
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
  delete from public.profile_pins where user_id = v_owner and profile_index = p_profile_id;
  delete from public.profiles where user_id = v_owner and profile_index = p_profile_id;
end;
$$;

create or replace function public.sync_pull_profile_locks()
returns table(profile_index integer, pin_enabled boolean, pin_locked_until timestamptz)
language sql
security definer
set search_path = public
as $$
  select p.profile_index, true as pin_enabled, pp.locked_until as pin_locked_until
  from public.profile_pins pp
  join public.profiles p
    on p.user_id = pp.user_id
   and p.profile_index = pp.profile_index
  where pp.user_id = public.require_sync_owner()
  order by pp.profile_index asc;
$$;

create or replace function public.set_profile_pin(p_profile_id integer, p_pin text, p_current_pin text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner uuid := public.require_sync_owner();
  v_existing text;
begin
  if coalesce(length(trim(p_pin)), 0) < 4 then
    raise exception 'PIN must be at least 4 digits';
  end if;

  select pin_hash into v_existing
  from public.profile_pins
  where user_id = v_owner and profile_index = p_profile_id;

  if v_existing is not null then
    if p_current_pin is null or v_existing <> extensions.crypt(p_current_pin, v_existing) then
      raise exception 'Current PIN is required';
    end if;
  end if;

  insert into public.profile_pins(user_id, profile_index, pin_hash, failed_attempts, locked_until)
  values (v_owner, p_profile_id, extensions.crypt(p_pin, extensions.gen_salt('bf')), 0, null)
  on conflict (user_id, profile_index) do update
    set pin_hash = excluded.pin_hash,
        failed_attempts = 0,
        locked_until = null;
end;
$$;

create or replace function public.clear_profile_pin(p_profile_id integer, p_current_pin text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner uuid := public.require_sync_owner();
  v_existing text;
begin
  select pin_hash into v_existing
  from public.profile_pins
  where user_id = v_owner and profile_index = p_profile_id;

  if v_existing is not null then
    if p_current_pin is null or v_existing <> extensions.crypt(p_current_pin, v_existing) then
      raise exception 'Current PIN is required';
    end if;
  end if;

  delete from public.profile_pins
  where user_id = v_owner and profile_index = p_profile_id;
end;
$$;

create or replace function public.verify_profile_pin(p_profile_id integer, p_pin text)
returns table(unlocked boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner uuid := public.require_sync_owner();
  v_row public.profile_pins%rowtype;
  v_retry integer;
begin
  select * into v_row
  from public.profile_pins
  where user_id = v_owner and profile_index = p_profile_id;

  if not found then
    return query select true, 0;
    return;
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    v_retry := greatest(ceil(extract(epoch from (v_row.locked_until - now())))::integer, 1);
    return query select false, v_retry;
    return;
  end if;

  if v_row.pin_hash = extensions.crypt(p_pin, v_row.pin_hash) then
    update public.profile_pins
    set failed_attempts = 0, locked_until = null
    where user_id = v_owner and profile_index = p_profile_id;
    return query select true, 0;
    return;
  end if;

  update public.profile_pins
  set failed_attempts = failed_attempts + 1,
      locked_until = case when failed_attempts + 1 >= 5 then now() + interval '5 minutes' else null end
  where user_id = v_owner and profile_index = p_profile_id
  returning case when locked_until is null then 0 else greatest(ceil(extract(epoch from (locked_until - now())))::integer, 1) end
  into v_retry;

  return query select false, coalesce(v_retry, 0);
end;
$$;

create or replace function public.sync_push_profile_settings_blob(p_profile_id integer, p_settings_json jsonb, p_platform text default 'tv')
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.profile_settings_blobs(user_id, profile_id, platform, settings_json, updated_at)
  values (public.require_sync_owner(), p_profile_id, coalesce(nullif(p_platform, ''), 'tv'), coalesce(p_settings_json, '{}'::jsonb), now())
  on conflict (user_id, profile_id, platform) do update
    set settings_json = excluded.settings_json,
        updated_at = excluded.updated_at;
$$;

create or replace function public.sync_pull_profile_settings_blob(p_profile_id integer, p_platform text default 'tv')
returns table(profile_id integer, settings_json jsonb, updated_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select ps.profile_id, ps.settings_json, ps.updated_at
  from public.profile_settings_blobs ps
  where ps.user_id = public.require_sync_owner()
    and ps.profile_id = p_profile_id
    and ps.platform = coalesce(nullif(p_platform, ''), 'tv')
  limit 1;
$$;

create or replace function public.sync_push_collections(p_profile_id integer, p_collections_json jsonb)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.collections(user_id, profile_id, collections_json, updated_at)
  values (public.require_sync_owner(), p_profile_id, coalesce(p_collections_json, '[]'::jsonb), now())
  on conflict (user_id, profile_id) do update
    set collections_json = excluded.collections_json,
        updated_at = excluded.updated_at;
$$;

create or replace function public.sync_pull_collections(p_profile_id integer)
returns table(profile_id integer, collections_json jsonb, updated_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select c.profile_id, c.collections_json, c.updated_at
  from public.collections c
  where c.user_id = public.require_sync_owner()
    and c.profile_id = p_profile_id
  limit 1;
$$;

create or replace function public.sync_push_home_catalog_settings(p_profile_id integer, p_settings_json jsonb, p_platform text default 'home_catalog_shared')
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.home_catalog_settings(user_id, profile_id, platform, settings_json, updated_at)
  values (public.require_sync_owner(), p_profile_id, coalesce(nullif(p_platform, ''), 'home_catalog_shared'), coalesce(p_settings_json, '{}'::jsonb), now())
  on conflict (user_id, profile_id, platform) do update
    set settings_json = excluded.settings_json,
        updated_at = excluded.updated_at;
$$;

create or replace function public.sync_pull_home_catalog_settings(p_profile_id integer, p_platform text default 'home_catalog_shared')
returns table(profile_id integer, settings_json jsonb, updated_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select h.profile_id, h.settings_json, h.updated_at
  from public.home_catalog_settings h
  where h.user_id = public.require_sync_owner()
    and h.profile_id = p_profile_id
    and h.platform = coalesce(nullif(p_platform, ''), 'home_catalog_shared')
  limit 1;
$$;

create or replace function public.get_avatar_catalog()
returns table(id text, display_name text, storage_path text, category text, sort_order integer, bg_color text)
language sql
security definer
set search_path = public
as $$
  select ac.id, ac.display_name, ac.storage_path, ac.category, ac.sort_order, ac.bg_color
  from public.avatar_catalog ac
  where ac.enabled
  order by ac.sort_order asc, ac.display_name asc;
$$;

create or replace function public.get_sync_overview()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'addons', coalesce((select jsonb_object_agg(profile_id::text, cnt) from (select profile_id, count(*) cnt from public.addons where user_id = public.require_sync_owner() group by profile_id) s), '{}'::jsonb),
    'plugins', coalesce((select jsonb_object_agg(profile_id::text, cnt) from (select profile_id, count(*) cnt from public.plugins where user_id = public.require_sync_owner() group by profile_id) s), '{}'::jsonb),
    'library_items', coalesce((select jsonb_object_agg(profile_id::text, cnt) from (select profile_id, count(*) cnt from public.library_items where user_id = public.require_sync_owner() group by profile_id) s), '{}'::jsonb),
    'watch_progress', coalesce((select jsonb_object_agg(profile_id::text, cnt) from (select profile_id, count(*) cnt from public.watch_progress where user_id = public.require_sync_owner() group by profile_id) s), '{}'::jsonb),
    'watched_items', coalesce((select jsonb_object_agg(profile_id::text, cnt) from (select profile_id, count(*) cnt from public.watched_items where user_id = public.require_sync_owner() group by profile_id) s), '{}'::jsonb),
    'profiles', coalesce((select jsonb_object_agg(profile_index::text, jsonb_build_object('name', name, 'color', avatar_color_hex)) from public.profiles where user_id = public.require_sync_owner()), '{}'::jsonb)
  );
$$;

create or replace function public.start_tv_login_session(p_device_nonce text, p_redirect_base_url text, p_device_name text default null)
returns table(code text, web_url text, expires_at timestamptz, poll_interval_seconds integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_requester uuid := auth.uid();
  v_code text;
  v_expires timestamptz := now() + interval '10 minutes';
  v_base text := trim(coalesce(p_redirect_base_url, ''));
begin
  if v_requester is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce(length(trim(p_device_nonce)), 0) < 16 then
    raise exception 'Invalid device nonce';
  end if;
  if v_base = '' then
    raise exception 'Missing redirect base URL';
  end if;

  loop
    v_code := public.random_login_code();
    exit when not exists (select 1 from public.tv_login_sessions s where s.code = v_code and s.expires_at > now());
  end loop;

  insert into public.tv_login_sessions(
    code, requester_user_id, device_nonce_hash, device_name, redirect_base_url, status, expires_at
  )
  values (
    v_code,
    v_requester,
    encode(extensions.digest(p_device_nonce, 'sha256'), 'hex'),
    nullif(trim(coalesce(p_device_name, '')), ''),
    v_base,
    'pending',
    v_expires
  );

  return query select
    v_code,
    v_base || case when position('?' in v_base) > 0 then '&' else '?' end || 'code=' || v_code,
    v_expires,
    3;
end;
$$;

create or replace function public.poll_tv_login_session(p_code text, p_device_nonce text)
returns table(status text, expires_at timestamptz, poll_interval_seconds integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_requester uuid := auth.uid();
  v_row public.tv_login_sessions%rowtype;
begin
  if v_requester is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_row
  from public.tv_login_sessions s
  where s.code = upper(trim(p_code))
    and s.requester_user_id = v_requester
    and s.device_nonce_hash = encode(extensions.digest(p_device_nonce, 'sha256'), 'hex')
  limit 1;

  if not found then
    return query select 'expired'::text, null::timestamptz, 3;
    return;
  end if;

  if v_row.expires_at <= now() and v_row.status = 'pending' then
    update public.tv_login_sessions set status = 'expired' where code = v_row.code;
    v_row.status := 'expired';
  end if;

  return query select v_row.status, v_row.expires_at, 3;
end;
$$;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists avatars_public_read on storage.objects;
create policy avatars_public_read on storage.objects
for select using (bucket_id = 'avatars');

grant usage on schema public to anon, authenticated;
grant select on public.avatar_catalog to anon, authenticated;
grant select on public.addons, public.plugins, public.linked_devices to authenticated;
grant execute on all functions in schema public to authenticated;
