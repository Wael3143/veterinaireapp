-- ============================================================================
-- VetPro consolidated schema migration
-- Run this once in Supabase SQL Editor (Project: smzmuqgbtsjgetxbmdgq).
-- It is idempotent (uses IF EXISTS / IF NOT EXISTS / drop-then-create policies).
-- After running, set the admin email by inserting/updating profiles.
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. PROFILES TABLE
--    Stores per-user role/admin flag/full name. Source of truth for
--    "is the current user the admin?" — replaces fragile localStorage checks.
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       text unique not null,
  full_name   text,
  role        text not null default 'user' check (role in ('user','admin')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists profiles_email_idx on public.profiles (lower(email));
create index if not exists profiles_role_idx  on public.profiles (role);

-- Helper function: is the current JWT an admin?
-- SECURITY DEFINER so RLS policies can call it without recursion lock-out.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.role = 'admin'
  );
$$;

grant execute on function public.is_admin() to anon, authenticated;

-- updated_at trigger helper
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

-- Auto-create a profile row when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email),
    case when lower(new.email) = 'waillacamora31@gmail.com' then 'admin' else 'user' end
  )
  on conflict (user_id) do update
    set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Backfill profiles for any existing users (safe: ON CONFLICT no-op).
insert into public.profiles (user_id, email, full_name, role)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data ->> 'full_name', u.email),
  case when lower(u.email) = 'waillacamora31@gmail.com' then 'admin' else 'user' end
from auth.users u
where u.email is not null
on conflict (user_id) do nothing;

-- ----------------------------------------------------------------------------
-- 2. ACCESS REQUESTS / APPROVAL SYSTEM (extends existing vetpro_access_requests)
--    Adds trial fields, expiry, audit columns. Existing rows are preserved.
-- ----------------------------------------------------------------------------
create table if not exists public.vetpro_access_requests (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users(id) on delete set null,
  email           text not null unique,
  full_name       text not null,
  phone           text,
  role            text not null default 'veterinaire' check (role in ('veterinaire','stagiaire')),
  order_number    text,
  student_proof   text,
  status          text not null default 'pending'
                   check (status in ('pending','approved','rejected','trial','expired')),
  requested_at    timestamptz not null default now(),
  reviewed_at     timestamptz,
  reviewed_by     text,
  notes           text
);

-- Add new columns idempotently.
alter table public.vetpro_access_requests
  add column if not exists approved_by         text,
  add column if not exists approved_at         timestamptz,
  add column if not exists trial_started_at    timestamptz,
  add column if not exists trial_ends_at       timestamptz,
  add column if not exists access_expires_at   timestamptz,
  add column if not exists created_at          timestamptz not null default now(),
  add column if not exists updated_at          timestamptz not null default now();

create index if not exists vetpro_access_requests_email_idx
  on public.vetpro_access_requests (lower(email));
create index if not exists vetpro_access_requests_status_idx
  on public.vetpro_access_requests (status);
create index if not exists vetpro_access_requests_expiry_idx
  on public.vetpro_access_requests (access_expires_at);

drop trigger if exists vetpro_access_requests_touch on public.vetpro_access_requests;
create trigger vetpro_access_requests_touch
before update on public.vetpro_access_requests
for each row execute function public.touch_updated_at();

-- Pre-approve the admin (matches the email used in handle_new_user trigger).
insert into public.vetpro_access_requests (
  email, full_name, role, status,
  approved_at, approved_by, reviewed_at, reviewed_by
) values (
  'waillacamora31@gmail.com', 'Kherbache Wail', 'veterinaire', 'approved',
  now(), 'system', now(), 'system'
)
on conflict (email) do update set
  status      = 'approved',
  approved_at = coalesce(public.vetpro_access_requests.approved_at, now()),
  approved_by = coalesce(public.vetpro_access_requests.approved_by, 'system');

-- ----------------------------------------------------------------------------
-- 3. CONTACT MESSAGES (unchanged — kept here for completeness)
-- ----------------------------------------------------------------------------
create table if not exists public.vetpro_contact_messages (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  email       text not null,
  subject     text,
  message     text not null,
  created_at  timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 4. PER-USER STATE (the JSON blob containing every clinic module's data)
--    Already exists; we keep the schema and tighten policies.
-- ----------------------------------------------------------------------------
create table if not exists public.vetpro_user_state (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  email       text not null unique,
  state       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

create index if not exists vetpro_user_state_user_id_idx on public.vetpro_user_state (user_id);
create index if not exists vetpro_user_state_email_idx   on public.vetpro_user_state (lower(email));

drop trigger if exists vetpro_user_state_touch on public.vetpro_user_state;
create trigger vetpro_user_state_touch
before update on public.vetpro_user_state
for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 5. PER-USER SETTINGS (language, theme, clinic info, notification prefs)
--    Separate from vetpro_user_state so settings can be loaded BEFORE the
--    main app state, and so language/theme survive a "Reset to 0".
-- ----------------------------------------------------------------------------
create table if not exists public.vetpro_user_settings (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       text unique not null,
  language    text not null default 'fr' check (language in ('fr','ar','en')),
  theme       text not null default 'forest',
  clinic      jsonb not null default '{}'::jsonb,
  notifications jsonb not null default '{}'::jsonb,
  ui          jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

create index if not exists vetpro_user_settings_email_idx on public.vetpro_user_settings (lower(email));

drop trigger if exists vetpro_user_settings_touch on public.vetpro_user_settings;
create trigger vetpro_user_settings_touch
before update on public.vetpro_user_settings
for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.profiles                enable row level security;
alter table public.vetpro_access_requests  enable row level security;
alter table public.vetpro_contact_messages enable row level security;
alter table public.vetpro_user_state       enable row level security;
alter table public.vetpro_user_settings    enable row level security;

-- ── profiles ──
drop policy if exists "profiles self read"   on public.profiles;
create policy "profiles self read"
on public.profiles for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self update"
on public.profiles for update to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (
  -- Non-admins cannot escalate themselves to admin.
  (user_id = auth.uid() and role = 'user') or public.is_admin()
);

drop policy if exists "profiles admin all" on public.profiles;
create policy "profiles admin all"
on public.profiles for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- ── vetpro_access_requests ──
drop policy if exists "vetpro access insert"             on public.vetpro_access_requests;
create policy "vetpro access insert"
on public.vetpro_access_requests for insert to anon, authenticated
with check (status in ('pending','trial') or public.is_admin());

drop policy if exists "vetpro access self select"        on public.vetpro_access_requests;
create policy "vetpro access self select"
on public.vetpro_access_requests for select to authenticated
using (
  lower(email) = lower(coalesce(auth.jwt() ->> 'email','')) or public.is_admin()
);

drop policy if exists "vetpro access self update pending" on public.vetpro_access_requests;
create policy "vetpro access self update pending"
on public.vetpro_access_requests for update to authenticated
using (
  lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  and status in ('pending','rejected')
)
with check (
  lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  and status = 'pending'
);

drop policy if exists "vetpro access admin update" on public.vetpro_access_requests;
create policy "vetpro access admin update"
on public.vetpro_access_requests for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "vetpro access admin delete" on public.vetpro_access_requests;
create policy "vetpro access admin delete"
on public.vetpro_access_requests for delete to authenticated
using (public.is_admin());

-- ── vetpro_contact_messages ──
drop policy if exists "vetpro contact insert"     on public.vetpro_contact_messages;
create policy "vetpro contact insert"
on public.vetpro_contact_messages for insert to anon, authenticated
with check (true);

drop policy if exists "vetpro contact admin read" on public.vetpro_contact_messages;
create policy "vetpro contact admin read"
on public.vetpro_contact_messages for select to authenticated
using (public.is_admin());

-- ── vetpro_user_state ──
drop policy if exists "vetpro state self select" on public.vetpro_user_state;
create policy "vetpro state self select"
on public.vetpro_user_state for select to authenticated
using (
  user_id = auth.uid()
  or lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  or public.is_admin()
);

drop policy if exists "vetpro state self insert" on public.vetpro_user_state;
create policy "vetpro state self insert"
on public.vetpro_user_state for insert to authenticated
with check (
  (user_id = auth.uid() or user_id is null)
  and lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
);

drop policy if exists "vetpro state self update" on public.vetpro_user_state;
create policy "vetpro state self update"
on public.vetpro_user_state for update to authenticated
using (
  user_id = auth.uid()
  or lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  or public.is_admin()
)
with check (
  user_id = auth.uid()
  or lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  or public.is_admin()
);

drop policy if exists "vetpro state self delete" on public.vetpro_user_state;
create policy "vetpro state self delete"
on public.vetpro_user_state for delete to authenticated
using (user_id = auth.uid() or public.is_admin());

-- ── vetpro_user_settings ──
drop policy if exists "vetpro settings self read"   on public.vetpro_user_settings;
create policy "vetpro settings self read"
on public.vetpro_user_settings for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "vetpro settings self insert" on public.vetpro_user_settings;
create policy "vetpro settings self insert"
on public.vetpro_user_settings for insert to authenticated
with check (
  user_id = auth.uid()
  and lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
);

drop policy if exists "vetpro settings self update" on public.vetpro_user_settings;
create policy "vetpro settings self update"
on public.vetpro_user_settings for update to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "vetpro settings self delete" on public.vetpro_user_settings;
create policy "vetpro settings self delete"
on public.vetpro_user_settings for delete to authenticated
using (user_id = auth.uid() or public.is_admin());

-- ----------------------------------------------------------------------------
-- 7. RPC: reset_user_data
--    Wipes the calling user's clinic data (vetpro_user_state.state -> {}).
--    By default keeps language/theme (vetpro_user_settings) untouched so the
--    user keeps their UI prefs after reset.
--    Pass include_settings=true to also reset settings.
-- ----------------------------------------------------------------------------
create or replace function public.reset_user_data(include_settings boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid   uuid := auth.uid();
  mail  text := lower(coalesce(auth.jwt() ->> 'email',''));
  rows  int;
begin
  if uid is null then
    raise exception 'reset_user_data: not authenticated';
  end if;

  update public.vetpro_user_state
    set state = '{}'::jsonb,
        updated_at = now()
  where user_id = uid or lower(email) = mail;
  get diagnostics rows = row_count;

  if include_settings then
    update public.vetpro_user_settings
      set language='fr', theme='forest',
          clinic='{}'::jsonb, notifications='{}'::jsonb, ui='{}'::jsonb,
          updated_at=now()
    where user_id = uid;
  end if;

  return jsonb_build_object(
    'ok', true,
    'cleared_state_rows', rows,
    'reset_settings', include_settings,
    'at', now()
  );
end;
$$;

revoke all on function public.reset_user_data(boolean) from public;
grant execute on function public.reset_user_data(boolean) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. RPC: approve_user — admin-only helper for clean approval transitions.
--    Modes: 'permanent' | 'until' (date) | 'days' (N) | 'trial' (15d) | 'reject'
-- ----------------------------------------------------------------------------
create or replace function public.approve_user(
  target_email   text,
  mode           text,
  duration_days  int default null,
  until_date     timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  acting_email text := lower(coalesce(auth.jwt() ->> 'email',''));
  new_status   text;
  new_expiry   timestamptz;
  trial_end    timestamptz;
begin
  if not public.is_admin() then
    raise exception 'approve_user: admin only';
  end if;

  if target_email is null or length(trim(target_email)) = 0 then
    raise exception 'approve_user: target_email required';
  end if;

  if mode = 'permanent' then
    new_status := 'approved';
    new_expiry := null;
    trial_end  := null;
  elsif mode = 'until' then
    if until_date is null then raise exception 'until_date required'; end if;
    new_status := 'approved';
    new_expiry := until_date;
    trial_end  := null;
  elsif mode = 'days' then
    if duration_days is null or duration_days <= 0 then raise exception 'duration_days required'; end if;
    new_status := 'approved';
    new_expiry := now() + make_interval(days => duration_days);
    trial_end  := null;
  elsif mode = 'trial' then
    new_status := 'trial';
    trial_end  := now() + interval '15 days';
    new_expiry := trial_end;
  elsif mode = 'reject' then
    new_status := 'rejected';
    new_expiry := null;
    trial_end  := null;
  else
    raise exception 'approve_user: unknown mode %', mode;
  end if;

  update public.vetpro_access_requests
    set status            = new_status,
        approved_by       = acting_email,
        approved_at       = case when mode <> 'reject' then now() else approved_at end,
        reviewed_by       = acting_email,
        reviewed_at       = now(),
        access_expires_at = new_expiry,
        trial_started_at  = case when mode = 'trial' then now() else trial_started_at end,
        trial_ends_at     = case when mode = 'trial' then trial_end else trial_ends_at end,
        updated_at        = now()
  where lower(email) = lower(target_email);

  if not found then
    raise exception 'approve_user: target email not found';
  end if;

  return jsonb_build_object(
    'ok', true,
    'email', target_email,
    'status', new_status,
    'access_expires_at', new_expiry,
    'trial_ends_at', trial_end
  );
end;
$$;

revoke all on function public.approve_user(text, text, int, timestamptz) from public;
grant execute on function public.approve_user(text, text, int, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. VIEW: my_access_status — convenience view for the frontend
--    Returns the current user's effective access (after expiry checks).
-- ----------------------------------------------------------------------------
create or replace view public.my_access_status
with (security_invoker = on)
as
select
  r.email,
  r.full_name,
  r.status as raw_status,
  case
    when public.is_admin() then 'admin'
    when r.status = 'approved' and r.access_expires_at is not null
         and r.access_expires_at < now() then 'expired'
    when r.status = 'trial' and r.trial_ends_at is not null
         and r.trial_ends_at < now() then 'expired'
    else r.status
  end as effective_status,
  r.trial_started_at,
  r.trial_ends_at,
  r.access_expires_at,
  r.approved_at,
  r.approved_by
from public.vetpro_access_requests r
where lower(r.email) = lower(coalesce(auth.jwt() ->> 'email',''))
   or public.is_admin();

grant select on public.my_access_status to authenticated;
