create extension if not exists pgcrypto;

create table if not exists public.vetpro_access_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  email text not null unique,
  full_name text not null,
  phone text,
  role text not null check (role in ('veterinaire', 'stagiaire')),
  order_number text,
  student_proof text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text,
  notes text
);

create table if not exists public.vetpro_contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  subject text,
  message text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.vetpro_user_state (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  email text not null unique,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.vetpro_access_requests enable row level security;
alter table public.vetpro_contact_messages enable row level security;
alter table public.vetpro_user_state enable row level security;

drop policy if exists "vetpro access insert" on public.vetpro_access_requests;
create policy "vetpro access insert"
on public.vetpro_access_requests
for insert
to anon, authenticated
with check (status = 'pending' or lower(email) = lower('__ADMIN_EMAIL__'));

drop policy if exists "vetpro access self select" on public.vetpro_access_requests;
create policy "vetpro access self select"
on public.vetpro_access_requests
for select
to authenticated
using (
  lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or lower(coalesce(auth.jwt() ->> 'email', '')) = lower('__ADMIN_EMAIL__')
);

drop policy if exists "vetpro access admin update" on public.vetpro_access_requests;
create policy "vetpro access admin update"
on public.vetpro_access_requests
for update
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = lower('__ADMIN_EMAIL__'))
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = lower('__ADMIN_EMAIL__'));

drop policy if exists "vetpro contact insert" on public.vetpro_contact_messages;
create policy "vetpro contact insert"
on public.vetpro_contact_messages
for insert
to anon, authenticated
with check (true);

drop policy if exists "vetpro contact admin read" on public.vetpro_contact_messages;
create policy "vetpro contact admin read"
on public.vetpro_contact_messages
for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = lower('__ADMIN_EMAIL__'));

drop policy if exists "vetpro state self select" on public.vetpro_user_state;
create policy "vetpro state self select"
on public.vetpro_user_state
for select
to authenticated
using (
  lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or lower(coalesce(auth.jwt() ->> 'email', '')) = lower('__ADMIN_EMAIL__')
);

drop policy if exists "vetpro state self upsert" on public.vetpro_user_state;
create policy "vetpro state self upsert"
on public.vetpro_user_state
for insert
to authenticated
with check (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

drop policy if exists "vetpro state self update" on public.vetpro_user_state;
create policy "vetpro state self update"
on public.vetpro_user_state
for update
to authenticated
using (
  lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or lower(coalesce(auth.jwt() ->> 'email', '')) = lower('__ADMIN_EMAIL__')
)
with check (
  lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  or lower(coalesce(auth.jwt() ->> 'email', '')) = lower('__ADMIN_EMAIL__')
);

insert into public.vetpro_access_requests (
  email,
  full_name,
  role,
  status,
  reviewed_at,
  reviewed_by
)
values (
  '__ADMIN_EMAIL__',
  'Kherbache Wail',
  'veterinaire',
  'approved',
  now(),
  'system'
)
on conflict (email) do update
set
  full_name = excluded.full_name,
  role = excluded.role,
  status = 'approved',
  reviewed_at = now(),
  reviewed_by = 'system';
