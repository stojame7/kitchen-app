-- =====================================================================
-- MenuWeave: Supabase setup
-- Run this once in your Supabase project: SQL Editor -> New query -> paste -> Run
-- =====================================================================

-- 1. Profiles: one row per registered user (this is your user list)
create table if not exists public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  email           text,
  full_name       text,
  country         text,
  updates_opt_in  boolean not null default false,  -- true = agreed to receive update emails
  app_version     text,                            -- last app version they opened
  created_at      timestamptz not null default now(),
  last_seen_at    timestamptz
);

alter table public.profiles enable row level security;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- Create a profile automatically whenever someone signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, country, updates_opt_in)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'country',
    coalesce((new.raw_user_meta_data ->> 'updates_opt_in')::boolean, false)
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. Saved timetables: each user's settings, own dishes and current plan
create table if not exists public.user_data (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table public.user_data enable row level security;

drop policy if exists "Users read own data" on public.user_data;
create policy "Users read own data" on public.user_data
  for select using (auth.uid() = user_id);

drop policy if exists "Users insert own data" on public.user_data;
create policy "Users insert own data" on public.user_data
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users update own data" on public.user_data;
create policy "Users update own data" on public.user_data
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- =====================================================================
-- Handy queries for you (run in the SQL Editor; they are not part of setup)
-- =====================================================================
-- All users, newest first:
--   select full_name, email, country, created_at, last_seen_at from public.profiles order by created_at desc;
-- People who agreed to update emails (export this list for your newsletter tool):
--   select full_name, email, country from public.profiles where updates_opt_in order by created_at desc;
-- Sign-ups per day:
--   select date(created_at) as day, count(*) from public.profiles group by 1 order by 1 desc;
-- Active in the last 7 days:
--   select count(*) from public.profiles where last_seen_at > now() - interval '7 days';
