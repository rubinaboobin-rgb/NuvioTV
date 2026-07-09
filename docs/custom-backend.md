# Custom NuvioTV Backend

This repo includes a clean-room Supabase backend implementation for the sync and login surface used by the Android app.

It covers:

- Supabase email/password auth
- anonymous auth for QR login bootstrapping
- sync-code device linking
- profile sync and profile PINs
- addon/plugin sync
- library sync
- Continue Watching watch-progress sync, including delta events
- watched-items sync, including delta events
- collections sync
- home catalog settings sync
- profile settings blob sync
- avatar catalog lookup
- TV QR login token exchange

## Files

- `supabase/migrations/20260709000000_nuvio_compatible_backend.sql`
- `supabase/functions/tv-logins-exchange/index.ts`
- `supabase/functions/tv-logins-approve/index.ts`
- `supabase/web/tv-login.html`

## Supabase Setup

1. Create a Supabase project.
2. In Auth settings, enable email/password sign-in.
3. Enable anonymous sign-ins. The TV QR flow starts as an anonymous Supabase session.
4. Apply the migration:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

5. Deploy the Edge Functions:

```bash
supabase functions deploy tv-logins-exchange
supabase functions deploy tv-logins-approve
```

6. Confirm these function secrets exist in the Supabase project:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
```

Supabase normally provides these automatically to hosted Edge Functions. If you run locally, set them yourself.

For current Supabase projects, use a Publishable key (`sb_publishable_...`) in client apps. Secret keys (`sb_secret_...`) and legacy `service_role` keys are backend-only and must never be bundled into the Android app.

## TV Login Page

`supabase/web/tv-login.html` is a minimal phone/browser login page. Before hosting it, replace:

```text
__SUPABASE_URL__
__SUPABASE_ANON_KEY__
```

with your project URL and Publishable key.

Host the file anywhere HTTPS-accessible, for example:

```text
https://your-domain.example/tv-login
```

Then set `TV_LOGIN_WEB_BASE_URL` to that URL in the app build config.

Important: this implementation approves TV login by handing the browser's current Supabase session tokens to the TV. That is enough for a private/self-hosted backend, but it may rotate or invalidate the browser session later. Direct email/password login in the app does not have that tradeoff.

## Point The App At Your Backend

For local builds, create `local.properties`:

```properties
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
AVATAR_PUBLIC_BASE_URL=https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/public/avatars
SYNC_BACKEND_MANIFEST_URL=
TV_LOGIN_WEB_BASE_URL=https://your-domain.example/tv-login
```

For GitHub Actions, put the same properties into `LOCAL_PROPERTIES_BASE64`:

```bash
base64 -w 0 local.properties
```

The app's default selected backend is `hosted`, and `hosted` maps to `SUPABASE_URL` / `SUPABASE_ANON_KEY`. Leaving `SYNC_BACKEND_MANIFEST_URL` blank prevents a remote manifest from switching the app back to another built-in backend.

The property is still named `SUPABASE_ANON_KEY` because that is what the Android code already reads. For new Supabase projects, put the current `sb_publishable_...` key there.

## Optional Nuvio Backend Slot

The app also has a second built-in backend ID named `nuvio`. If you want debug builds to switch between two custom projects, set:

```properties
NUVIO_SUPABASE_URL=https://SECOND_PROJECT.supabase.co
NUVIO_SUPABASE_ANON_KEY=SECOND_PROJECT_PUBLISHABLE_KEY
NUVIO_AVATAR_PUBLIC_BASE_URL=https://SECOND_PROJECT.supabase.co/storage/v1/object/public/avatars
```

Release builds normally use the `hosted` slot unless the sync backend manifest changes the selected backend.

## Avatar Catalog

The migration creates a public `avatars` storage bucket and an `avatar_catalog` table. Upload images into the bucket, then insert catalog rows:

```sql
insert into public.avatar_catalog (id, display_name, storage_path, category, sort_order, bg_color)
values
  ('default-blue', 'Blue', 'default-blue.png', 'default', 10, '#1E88E5');
```

`storage_path` is appended to `AVATAR_PUBLIC_BASE_URL`.

## Backend Contract Notes

The Android app calls Supabase directly. There is no separate REST server for sync. Most writes go through `security definer` Postgres RPCs so linked devices can write to the owner's data while RLS still blocks arbitrary reads.

Continue Watching uses:

- `watch_progress` for the current snapshot
- `watch_progress_events` for delta sync
- `sync_push_watch_progress`
- `sync_pull_watch_progress`
- `sync_pull_watch_progress_delta`
- `sync_get_watch_progress_delta_cursor`
- `sync_delete_watch_progress`

Watched completion badges use the equivalent `watched_items` and `watched_item_events` tables/functions.
