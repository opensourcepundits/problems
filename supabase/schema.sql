-- Crisis Incident Reporting Platform
-- Run this entire script once in the Supabase SQL Editor.
-- Re-running refreshes functions, triggers, and policies without dropping data.
--
-- PostGIS on Supabase lives in the `extensions` schema. Every definer/invoker
-- function below includes that schema on its search_path so geometry calls resolve.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. Extensions
-- ---------------------------------------------------------------------------

create extension if not exists postgis;
create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- 2. Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.incident_category as enum (
    'fire', 'looting', 'casualty', 'accident', 'roadblock', 'sos', 'other'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.incident_severity as enum ('low', 'medium', 'high', 'critical');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.incident_status as enum ('unverified', 'verified', 'resolved', 'debunked');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.vote_type as enum ('confirm', 'deny');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone_number text,
  created_at timestamptz not null default now(),
  constraint profiles_full_name_len check (full_name is null or char_length(full_name) <= 120),
  constraint profiles_phone_len check (phone_number is null or char_length(phone_number) <= 32)
);

create table if not exists public.incidents (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles (id) on delete restrict,
  title text not null,
  description text,
  category public.incident_category not null,
  severity public.incident_severity not null default 'medium',
  location geometry(Point, 4326) not null,
  address_hint text,
  media_urls text[] not null default '{}',
  status public.incident_status not null default 'unverified',
  is_sos boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint incidents_title_len check (char_length(title) between 1 and 160),
  constraint incidents_description_len check (description is null or char_length(description) <= 4000),
  constraint incidents_address_len check (address_hint is null or char_length(address_hint) <= 240),
  constraint incidents_media_count check (coalesce(cardinality(media_urls), 0) <= 6),
  constraint incidents_lat check (ST_Y(location) between -90 and 90),
  constraint incidents_lng check (ST_X(location) between -180 and 180)
);

create table if not exists public.incident_comments (
  id uuid primary key default uuid_generate_v4(),
  incident_id uuid not null references public.incidents (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete restrict,
  comment text not null,
  media_url text,
  created_at timestamptz not null default now(),
  constraint incident_comments_len check (char_length(comment) between 1 and 2000)
);

create table if not exists public.incident_confirmations (
  id uuid primary key default uuid_generate_v4(),
  incident_id uuid not null references public.incidents (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete restrict,
  voter_key text,
  vote_type public.vote_type not null,
  created_at timestamptz not null default now()
);

alter table public.incidents alter column user_id drop not null;
alter table public.incident_comments alter column user_id drop not null;
alter table public.incident_confirmations alter column user_id drop not null;
alter table public.incident_confirmations add column if not exists voter_key text;
alter table public.incident_confirmations drop constraint if exists incident_confirmations_one_vote;
create unique index if not exists incident_confirmations_one_voter
  on public.incident_confirmations (incident_id, voter_key);

-- Append-only audit trail. created_at is stamped by trigger and cannot be updated.
create table if not exists public.action_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users (id) on delete set null,
  action_type text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint action_logs_action_len check (char_length(action_type) between 1 and 64),
  constraint action_logs_entity_len check (char_length(entity_type) between 1 and 64)
);

comment on table public.action_logs is
  'Immutable audit trail. INSERT only. UPDATE and DELETE are rejected for every role, including the table owner.';
comment on column public.action_logs.created_at is
  'Server timestamp set on insert. Clients cannot choose or change it.';

-- ---------------------------------------------------------------------------
-- 4. Indexes
-- ---------------------------------------------------------------------------

create index if not exists incidents_location_gix on public.incidents using gist (location);
create index if not exists incidents_geom_3857_gix on public.incidents using gist (ST_Transform(location, 3857));
create index if not exists incidents_created_at_idx on public.incidents (created_at desc);
create index if not exists incidents_category_idx on public.incidents (category);
create index if not exists incidents_status_idx on public.incidents (status);
create index if not exists incidents_user_idx on public.incidents (user_id);
create index if not exists incidents_sos_idx on public.incidents (created_at desc) where is_sos;
create index if not exists incident_comments_incident_idx on public.incident_comments (incident_id, created_at);
create index if not exists incident_comments_user_idx on public.incident_comments (user_id);
create index if not exists incident_confirmations_incident_idx on public.incident_confirmations (incident_id);
create index if not exists action_logs_created_idx on public.action_logs (created_at desc);
create index if not exists action_logs_user_idx on public.action_logs (user_id, created_at desc);
create index if not exists action_logs_entity_idx on public.action_logs (entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- 5. Identity, stamps, and audit helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.profiles (id, full_name, phone_number)
  values (
    new.id,
    nullif(left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120), ''),
    nullif(left(coalesce(new.raw_user_meta_data ->> 'phone_number', ''), 32), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.before_incident_write()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.user_id := auth.uid();
    end if;
    if new.user_id is not null then
      insert into public.profiles (id)
      values (new.user_id)
      on conflict (id) do nothing;
    end if;
    new.created_at := now();
    new.updated_at := now();
    if new.is_sos then
      new.category := 'sos';
      new.severity := 'critical';
    end if;
    return new;
  end if;

  new.id := old.id;
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  new.is_sos := old.is_sos;
  new.updated_at := now();
  if old.is_sos then
    new.category := 'sos';
    new.severity := 'critical';
    new.location := old.location;
  end if;
  return new;
end;
$$;

create or replace function public.before_owned_insert()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if auth.uid() is not null then
    new.user_id := auth.uid();
  end if;
  if new.user_id is not null then
    insert into public.profiles (id)
    values (new.user_id)
    on conflict (id) do nothing;
  end if;
  new.created_at := now();
  return new;
end;
$$;

-- Reject any attempt to rewrite history, including by the table owner and service role.
create or replace function public.reject_action_log_mutation()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  raise exception 'action_logs is append-only'
    using errcode = '55000';
end;
$$;

create or replace function public.stamp_action_log()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if auth.uid() is not null then
    new.user_id := auth.uid();
  end if;
  new.created_at := now();
  if new.id is null then
    new.id := uuid_generate_v4();
  end if;
  return new;
end;
$$;

create or replace function public.incident_audit_payload(rec public.incidents)
returns jsonb
language sql
stable
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'id', rec.id,
    'user_id', rec.user_id,
    'title', rec.title,
    'description', rec.description,
    'category', rec.category,
    'severity', rec.severity,
    'status', rec.status,
    'is_sos', rec.is_sos,
    'address_hint', rec.address_hint,
    'media_urls', to_jsonb(rec.media_urls),
    'lat', ST_Y(rec.location),
    'lng', ST_X(rec.location),
    'created_at', rec.created_at,
    'updated_at', rec.updated_at
  );
$$;

create or replace function public.jsonb_diff(old_row jsonb, new_row jsonb)
returns jsonb
language sql
immutable
set search_path = public, extensions
as $$
  select coalesce(
    jsonb_object_agg(n.key, n.value),
    '{}'::jsonb
  )
  from jsonb_each(coalesce(new_row, '{}'::jsonb)) as n(key, value)
  left join jsonb_each(coalesce(old_row, '{}'::jsonb)) as o(key, value)
    on o.key = n.key
  where n.value is distinct from o.value;
$$;

-- Fires after a successful insert, update, or delete. A failure here rolls the
-- original statement back, so an incident, comment, or vote cannot be stored
-- without an audit row. auth.uid() is read from the request JWT, not from the
-- client payload. SOS inserts are labeled TRIGGER_SOS and carry lat/lng.
create or replace function public.log_entity_action()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_action text;
  v_entity text;
  v_entity_id uuid;
  v_actor uuid;
  v_new jsonb;
  v_old jsonb;
  v_metadata jsonb;
begin
  v_actor := auth.uid();

  if tg_table_name = 'incidents' then
    v_entity := 'incident';
    if tg_op = 'DELETE' then
      v_entity_id := old.id;
      v_actor := coalesce(v_actor, old.user_id);
      v_old := public.incident_audit_payload(old);
      v_action := 'DELETE_INCIDENT';
    elsif tg_op = 'UPDATE' then
      v_entity_id := new.id;
      v_actor := coalesce(v_actor, new.user_id);
      v_new := public.incident_audit_payload(new);
      v_old := public.incident_audit_payload(old);
      if new.status = 'resolved' and old.status is distinct from 'resolved' then
        v_action := 'RESOLVE_INCIDENT';
      else
        v_action := 'UPDATE_INCIDENT';
      end if;
    else
      v_entity_id := new.id;
      v_actor := coalesce(v_actor, new.user_id);
      v_new := public.incident_audit_payload(new);
      if new.is_sos then
        v_action := 'TRIGGER_SOS';
      else
        v_action := 'CREATE_INCIDENT';
      end if;
    end if;
  elsif tg_table_name = 'incident_comments' then
    v_entity := 'comment';
    if tg_op = 'DELETE' then
      v_entity_id := old.id;
      v_actor := coalesce(v_actor, old.user_id);
      v_old := to_jsonb(old);
      v_action := 'DELETE_COMMENT';
    elsif tg_op = 'UPDATE' then
      v_entity_id := new.id;
      v_actor := coalesce(v_actor, new.user_id);
      v_new := to_jsonb(new);
      v_old := to_jsonb(old);
      v_action := 'UPDATE_COMMENT';
    else
      v_entity_id := new.id;
      v_actor := coalesce(v_actor, new.user_id);
      v_new := to_jsonb(new);
      v_action := 'ADD_COMMENT';
    end if;
  elsif tg_table_name = 'incident_confirmations' then
    v_entity := 'confirmation';
    if tg_op = 'DELETE' then
      v_entity_id := old.id;
      v_actor := coalesce(v_actor, old.user_id);
      v_old := to_jsonb(old);
      v_action := 'DELETE_CONFIRMATION';
    else
      v_entity_id := new.id;
      v_actor := coalesce(v_actor, new.user_id);
      v_new := to_jsonb(new);
      if tg_op = 'UPDATE' then
        v_old := to_jsonb(old);
      end if;
      v_action := 'VOTE_CONFIRMATION';
    end if;
  else
    raise exception 'log_entity_action is not registered for %', tg_table_name;
  end if;

  v_metadata := jsonb_build_object(
    'op', tg_op,
    'table', tg_table_name,
    'actor_id', v_actor
  );

  if tg_op = 'INSERT' then
    v_metadata := v_metadata || jsonb_build_object('record', v_new);
  elsif tg_op = 'DELETE' then
    v_metadata := v_metadata || jsonb_build_object('record', v_old);
  else
    v_metadata := v_metadata || jsonb_build_object(
      'record', v_new,
      'changed', public.jsonb_diff(v_old, v_new)
    );
  end if;

  insert into public.action_logs (user_id, action_type, entity_type, entity_id, metadata, created_at)
  values (v_actor, v_action, v_entity, v_entity_id, v_metadata, now());

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- Trigger functions must stay executable by the session that writes the row.
-- Calling this directly is rejected by Postgres: it only runs as a trigger.
revoke all on function public.log_entity_action() from public;
grant execute on function public.log_entity_action() to anon, authenticated;

drop trigger if exists incidents_before_write on public.incidents;
create trigger incidents_before_write
  before insert or update on public.incidents
  for each row execute function public.before_incident_write();

drop trigger if exists incidents_audit on public.incidents;
create trigger incidents_audit
  after insert or update or delete on public.incidents
  for each row execute function public.log_entity_action();

drop trigger if exists incident_comments_before_insert on public.incident_comments;
create trigger incident_comments_before_insert
  before insert on public.incident_comments
  for each row execute function public.before_owned_insert();

drop trigger if exists incident_comments_audit on public.incident_comments;
create trigger incident_comments_audit
  after insert or update or delete on public.incident_comments
  for each row execute function public.log_entity_action();

drop trigger if exists incident_confirmations_before_insert on public.incident_confirmations;
create trigger incident_confirmations_before_insert
  before insert on public.incident_confirmations
  for each row execute function public.before_owned_insert();

drop trigger if exists incident_confirmations_audit on public.incident_confirmations;
create trigger incident_confirmations_audit
  after insert or update or delete on public.incident_confirmations
  for each row execute function public.log_entity_action();

drop trigger if exists action_logs_stamp on public.action_logs;
create trigger action_logs_stamp
  before insert on public.action_logs
  for each row execute function public.stamp_action_log();

drop trigger if exists action_logs_reject_mutation on public.action_logs;
create trigger action_logs_reject_mutation
  before update or delete on public.action_logs
  for each row execute function public.reject_action_log_mutation();

-- ---------------------------------------------------------------------------
-- 6. Incident writes and map reads
-- ---------------------------------------------------------------------------

create or replace function public.create_incident(
  p_title text,
  p_description text,
  p_category text,
  p_severity text,
  p_lng double precision,
  p_lat double precision,
  p_address_hint text default null,
  p_media_urls text[] default '{}',
  p_is_sos boolean default false
)
returns uuid
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_title text;
  v_category public.incident_category;
  v_severity public.incident_severity;
begin
  if p_lat is null or p_lng is null or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;
  if p_category not in ('fire', 'looting', 'casualty', 'accident', 'roadblock', 'sos', 'other') then
    raise exception 'invalid category' using errcode = '22023';
  end if;
  if p_severity not in ('low', 'medium', 'high', 'critical') then
    raise exception 'invalid severity' using errcode = '22023';
  end if;

  v_title := nullif(trim(coalesce(p_title, '')), '');
  if coalesce(p_is_sos, false) then
    v_title := coalesce(v_title, 'Emergency SOS');
    v_category := 'sos';
    v_severity := 'critical';
  else
    if v_title is null then
      raise exception 'title is required' using errcode = '22023';
    end if;
    v_category := p_category::public.incident_category;
    v_severity := p_severity::public.incident_severity;
  end if;

  insert into public.incidents (
    user_id, title, description, category, severity, location,
    address_hint, media_urls, is_sos
  )
  values (
    auth.uid(),
    left(v_title, 160),
    nullif(trim(coalesce(p_description, '')), ''),
    v_category,
    v_severity,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326),
    nullif(trim(coalesce(p_address_hint, '')), ''),
    coalesce(p_media_urls, '{}'),
    coalesce(p_is_sos, false)
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean) from public;
grant execute on function public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean) to anon, authenticated;

create or replace function public.cast_vote(
  p_incident_id uuid,
  p_voter_key text,
  p_vote_type text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_voter_key is null or char_length(p_voter_key) < 8 or char_length(p_voter_key) > 80 then
    raise exception 'invalid voter key' using errcode = '22023';
  end if;
  if p_vote_type is null or btrim(p_vote_type) in ('', 'clear') then
    delete from public.incident_confirmations
    where incident_id = p_incident_id and voter_key = p_voter_key;
    return;
  end if;
  if p_vote_type not in ('confirm', 'deny') then
    raise exception 'invalid vote' using errcode = '22023';
  end if;
  if not exists (select 1 from public.incidents where id = p_incident_id) then
    raise exception 'incident not found' using errcode = 'P0002';
  end if;

  insert into public.incident_confirmations (incident_id, user_id, voter_key, vote_type)
  values (p_incident_id, auth.uid(), p_voter_key, p_vote_type::public.vote_type)
  on conflict (incident_id, voter_key) do update
  set vote_type = excluded.vote_type;
end;
$$;

revoke all on function public.cast_vote(uuid, text, text) from public;
grant execute on function public.cast_vote(uuid, text, text) to anon, authenticated;

create or replace function public.set_incident_resolved(
  p_incident_id uuid,
  p_resolved boolean
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.incidents
  set status = case
    when coalesce(p_resolved, false) then 'resolved'::public.incident_status
    else 'unverified'::public.incident_status
  end
  where id = p_incident_id;

  if not found then
    raise exception 'incident not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.set_incident_resolved(uuid, boolean) from public;
grant execute on function public.set_incident_resolved(uuid, boolean) to anon, authenticated;

drop function if exists public.get_incidents(int, text, double precision, double precision, double precision, double precision);

create or replace function public.get_incidents(
  hours_back int default 168,
  categories text[] default null,
  min_lng double precision default null,
  min_lat double precision default null,
  max_lng double precision default null,
  max_lat double precision default null
)
returns table (
  id uuid,
  user_id uuid,
  title text,
  description text,
  category text,
  severity text,
  lng double precision,
  lat double precision,
  address_hint text,
  media_urls text[],
  status text,
  is_sos boolean,
  created_at timestamptz,
  updated_at timestamptz,
  confirm_count bigint,
  deny_count bigint,
  comment_count bigint,
  author_name text
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    i.id,
    i.user_id,
    i.title,
    i.description,
    i.category::text,
    i.severity::text,
    ST_X(i.location) as lng,
    ST_Y(i.location) as lat,
    i.address_hint,
    i.media_urls,
    i.status::text,
    i.is_sos,
    i.created_at,
    i.updated_at,
    (select count(*) from public.incident_confirmations c where c.incident_id = i.id and c.vote_type = 'confirm') as confirm_count,
    (select count(*) from public.incident_confirmations c where c.incident_id = i.id and c.vote_type = 'deny') as deny_count,
    (select count(*) from public.incident_comments m where m.incident_id = i.id) as comment_count,
    p.full_name as author_name
  from public.incidents i
  left join public.profiles p on p.id = i.user_id
  where i.created_at >= now() - make_interval(hours => least(greatest(coalesce(hours_back, 168), 1), 2160))
    and (i.status <> 'debunked' or i.user_id = auth.uid())
    and (
      categories is null
      or cardinality(categories) = 0
      or i.category::text = any(categories)
    )
    and (
      min_lng is null or min_lat is null or max_lng is null or max_lat is null
      or ST_Intersects(i.location, ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326))
    )
  order by (i.severity = 'critical') desc, i.is_sos desc, i.created_at desc
  limit 2000;
$$;

revoke all on function public.get_incidents(int, text[], double precision, double precision, double precision, double precision) from public;
grant execute on function public.get_incidents(int, text[], double precision, double precision, double precision, double precision) to anon, authenticated;

-- Squares covering the main island of Mauritius, including the coast.
-- cell_km is the side length, from 1 to 10. Empty cells stay in the result.
-- Debunked reports are excluded.

drop function if exists public.get_5km_grid(int, text);
drop function if exists public.get_zone_grid(int, text[], int);

create or replace function public.get_zone_grid(
  hours_back int default 24,
  categories text[] default null,
  cell_km int default 5
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  result jsonb;
  v_km int := least(greatest(coalesce(cell_km, 5), 1), 10);
  v_size double precision := v_km * 1000.0;
  v_bounds geometry := ST_Expand(
    ST_Transform(ST_MakeEnvelope(57.29, -20.55, 57.83, -19.94, 4326), 3857),
    v_size
  );
begin
  with cells as (
    select g.geom as cell, g.i as cell_i, g.j as cell_j
    from ST_SquareGrid(v_size, v_bounds) as g
  ),
  pts as (
    select
      category::text as category,
      severity::text as severity,
      ST_Transform(location, 3857) as geom
    from public.incidents
    where created_at >= now() - make_interval(hours => least(greatest(coalesce(hours_back, 24), 1), 720))
      and status <> 'debunked'
      and (
        categories is null
        or cardinality(categories) = 0
        or category::text = any(categories)
      )
  ),
  assigned as (
    select p.category, p.severity, hit.cell_i, hit.cell_j
    from pts p
    join lateral (
      select c.cell_i, c.cell_j
      from cells c
      where ST_Intersects(c.cell, p.geom)
      order by c.cell_i, c.cell_j
      limit 1
    ) hit on true
  ),
  agg as (
    select
      c.cell,
      count(a.category)::int as total_count,
      count(a.category) filter (where a.severity = 'critical')::int as critical_count,
      mode() within group (order by a.category) as top_category
    from cells c
    left join assigned a on a.cell_i = c.cell_i and a.cell_j = c.cell_j
    group by c.cell_i, c.cell_j, c.cell
  )
  select jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'type', 'Feature',
          'geometry', ST_AsGeoJSON(ST_Transform(cell, 4326), 5)::jsonb,
          'properties', jsonb_build_object(
            'total_count', total_count,
            'critical_count', critical_count,
            'top_category', top_category
          )
        )
      ),
      '[]'::jsonb
    )
  )
  into result
  from agg;

  return coalesce(
    result,
    jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_zone_grid(int, text[], int) from public;
grant execute on function public.get_zone_grid(int, text[], int) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.incidents enable row level security;
alter table public.incident_comments enable row level security;
alter table public.incident_confirmations enable row level security;
alter table public.action_logs enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to anon, authenticated
  using (true);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists incidents_select_public on public.incidents;
create policy incidents_select_public on public.incidents
  for select to anon, authenticated
  using (status <> 'debunked' or user_id = auth.uid());

drop policy if exists incidents_insert_own on public.incidents;
create policy incidents_insert_own on public.incidents
  for insert to anon, authenticated
  with check (user_id is not distinct from auth.uid());

drop policy if exists incidents_update_own on public.incidents;
create policy incidents_update_own on public.incidents
  for update to authenticated
  using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

drop policy if exists comments_select_public on public.incident_comments;
create policy comments_select_public on public.incident_comments
  for select to anon, authenticated
  using (true);

drop policy if exists comments_insert_own on public.incident_comments;
create policy comments_insert_own on public.incident_comments
  for insert to anon, authenticated
  with check (user_id is not distinct from auth.uid());

drop policy if exists comments_delete_own on public.incident_comments;
create policy comments_delete_own on public.incident_comments
  for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists confirmations_select_public on public.incident_confirmations;
create policy confirmations_select_public on public.incident_confirmations
  for select to anon, authenticated
  using (true);

drop policy if exists confirmations_insert_own on public.incident_confirmations;
create policy confirmations_insert_own on public.incident_confirmations
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists confirmations_update_own on public.incident_confirmations;
create policy confirmations_update_own on public.incident_confirmations
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists confirmations_delete_own on public.incident_confirmations;
create policy confirmations_delete_own on public.incident_confirmations
  for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- Creators can read their own rows. Admins (app_metadata.role = admin) can read all.
-- There is intentionally no UPDATE or DELETE policy.
drop policy if exists action_logs_select_own on public.action_logs;
create policy action_logs_select_own on public.action_logs
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists action_logs_insert_own on public.action_logs;
create policy action_logs_insert_own on public.action_logs
  for insert to authenticated
  with check (user_id = auth.uid());

revoke update, delete, truncate on public.action_logs from public, anon, authenticated;

grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.incidents, public.incident_comments, public.incident_confirmations to anon, authenticated;
grant insert, update on public.profiles to authenticated;
grant insert, update on public.incidents to anon, authenticated;
grant insert, delete on public.incident_comments to anon, authenticated;
grant insert, update, delete on public.incident_confirmations to authenticated;
grant select, insert on public.action_logs to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Storage bucket: public read, authenticated insert, 25MB
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'incident-media',
  'incident-media',
  true,
  26214400,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/webm', 'video/quicktime']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists incident_media_public_read on storage.objects;
create policy incident_media_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'incident-media');

drop policy if exists incident_media_authenticated_insert on storage.objects;
drop policy if exists incident_media_public_insert on storage.objects;
create policy incident_media_public_insert on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'incident-media'
    and (storage.foldername(name))[1] = 'public'
  );

drop policy if exists incident_media_owner_delete on storage.objects;
create policy incident_media_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'incident-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 9. Realtime
-- ---------------------------------------------------------------------------

do $$ begin
  alter publication supabase_realtime add table public.incidents;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.incident_comments;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.incident_confirmations;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';

-- Promote an operator in the SQL editor (users cannot set app_metadata themselves):
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
-- where id = '00000000-0000-0000-0000-000000000000';
