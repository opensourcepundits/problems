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

-- Squares clipped to the main island of Mauritius. cell_km is the
-- side length, from 1 to 10. The outline is the OpenStreetMap coastline.
-- Empty land cells stay in the result. Debunked reports are excluded.
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
  island geometry := ST_Transform(
    ST_SetSRID(ST_GeomFromText('MULTIPOLYGON(((57.80509 -20.26503,57.80376 -20.26369,57.80159 -20.26542,57.80269 -20.26786,57.80041 -20.26662,57.79894 -20.27231,57.8011 -20.27232,57.80032 -20.27431,57.80324 -20.27694,57.79967 -20.2749,57.80052 -20.27655,57.79766 -20.27792,57.79817 -20.28008,57.80454 -20.27836,57.80561 -20.27642,57.81006 -20.27481,57.80725 -20.2738,57.80817 -20.27136,57.80616 -20.2705,57.80509 -20.26503)),((57.61816 -19.98469,57.61074 -19.98207,57.60636 -19.9858,57.60012 -19.98473,57.5921 -19.98986,57.58926 -19.98817,57.59144 -19.98995,57.59113 -19.99366,57.58658 -19.9961,57.58344 -19.99439,57.58234 -19.99559,57.58426 -19.99658,57.58394 -19.99878,57.58061 -20.0011,57.57748 -20.00771,57.58425 -20.01175,57.58321 -20.01462,57.58132 -20.01412,57.57872 -20.016,57.57419 -20.01412,57.56821 -20.01441,57.56747 -20.00943,57.57153 -20.0052,57.57003 -20.00311,57.55999 -20.00349,57.55184 -20.00011,57.55164 -20.00503,57.55469 -20.00769,57.55696 -20.01323,57.55643 -20.01801,57.54679 -20.02705,57.54158 -20.04098,57.52719 -20.0469,57.52452 -20.04652,57.52205 -20.05289,57.52246 -20.05789,57.51915 -20.05918,57.51989 -20.06239,57.51812 -20.06791,57.51159 -20.07702,57.51238 -20.08311,57.51535 -20.08414,57.51633 -20.08599,57.51339 -20.08935,57.50876 -20.09053,57.50866 -20.09528,57.51418 -20.10239,57.51698 -20.10359,57.51725 -20.10689,57.51345 -20.10713,57.50213 -20.11311,57.49578 -20.12678,57.49851 -20.13766,57.49877 -20.13666,57.50029 -20.1385,57.50285 -20.13754,57.50568 -20.14111,57.49732 -20.13852,57.4859 -20.14557,57.49658 -20.15402,57.49908 -20.15282,57.49961 -20.15419,57.49707 -20.15526,57.49849 -20.15834,57.50063 -20.15654,57.50421 -20.15629,57.50459 -20.15735,57.50148 -20.15767,57.50016 -20.16106,57.49628 -20.1593,57.49694 -20.16113,57.49913 -20.16173,57.49452 -20.16316,57.49602 -20.16232,57.49526 -20.15766,57.48877 -20.15352,57.48279 -20.15323,57.47936 -20.16098,57.47549 -20.16321,57.47763 -20.16864,57.47321 -20.17065,57.47484 -20.17344,57.47333 -20.17126,57.4717 -20.17511,57.47088 -20.17262,57.4731 -20.168,57.46743 -20.16413,57.46309 -20.16439,57.43922 -20.17403,57.43148 -20.17409,57.42444 -20.18098,57.42369 -20.18398,57.41334 -20.18941,57.40358 -20.19846,57.40213 -20.20087,57.40477 -20.20571,57.4018 -20.21587,57.40058 -20.2171,57.3932 -20.21666,57.38679 -20.22633,57.38386 -20.23866,57.38086 -20.24225,57.38412 -20.24982,57.38032 -20.25473,57.37897 -20.26117,57.37597 -20.26246,57.37502 -20.26684,57.37076 -20.27154,57.37086 -20.27402,57.36832 -20.27463,57.36523 -20.28016,57.36311 -20.28853,57.3628 -20.29673,57.36699 -20.31465,57.37305 -20.31777,57.37449 -20.31997,57.37752 -20.32046,57.37903 -20.32294,57.37624 -20.32741,57.36549 -20.33382,57.36039 -20.35501,57.36505 -20.35928,57.3704 -20.36121,57.37161 -20.36657,57.37584 -20.36464,57.37614 -20.3629,57.37777 -20.3648,57.37459 -20.36585,57.37859 -20.36754,57.38025 -20.36656,57.37912 -20.36781,57.37527 -20.36692,57.37247 -20.36929,57.3702 -20.36877,57.37116 -20.36751,57.35966 -20.37138,57.35903 -20.37922,57.36137 -20.38275,57.36185 -20.38108,57.3644 -20.38208,57.36335 -20.3835,57.37067 -20.38298,57.37518 -20.38659,57.37836 -20.38678,57.37556 -20.39015,57.37608 -20.39123,57.37953 -20.39069,57.38085 -20.39201,57.37922 -20.39085,57.37605 -20.39179,57.37735 -20.39187,57.37625 -20.39378,57.36905 -20.39457,57.36732 -20.39646,57.3704 -20.40079,57.36846 -20.40518,57.36935 -20.41027,57.36609 -20.41168,57.36788 -20.41469,57.36401 -20.4171,57.36432 -20.41958,57.35981 -20.42497,57.36006 -20.42673,57.35387 -20.43209,57.35271 -20.43611,57.34723 -20.44042,57.34421 -20.44536,57.33699 -20.44304,57.32212 -20.44227,57.32329 -20.43683,57.32592 -20.43552,57.32244 -20.43248,57.31695 -20.44296,57.31816 -20.44391,57.32106 -20.4417,57.32192 -20.44234,57.31829 -20.44405,57.31679 -20.4432,57.31612 -20.44439,57.30898 -20.46019,57.30865 -20.46704,57.31479 -20.46833,57.3214 -20.45971,57.33574 -20.46067,57.33442 -20.46028,57.33854 -20.45847,57.33974 -20.45969,57.33605 -20.46041,57.33876 -20.46065,57.34129 -20.46393,57.33508 -20.46218,57.34201 -20.46602,57.34869 -20.47804,57.35386 -20.4814,57.35445 -20.48675,57.36065 -20.48876,57.36795 -20.4879,57.37049 -20.48523,57.3723 -20.48523,57.37167 -20.4815,57.37347 -20.47971,57.37118 -20.49076,57.37324 -20.49038,57.38936 -20.49951,57.39663 -20.49994,57.39832 -20.50453,57.40883 -20.50605,57.41657 -20.51208,57.42896 -20.51174,57.44061 -20.50853,57.44514 -20.50379,57.4448 -20.50191,57.44763 -20.50133,57.44817 -20.50471,57.45463 -20.50316,57.45738 -20.50725,57.4656 -20.50946,57.46985 -20.51233,57.46934 -20.51529,57.4721 -20.51652,57.48507 -20.5195,57.50183 -20.5178,57.50753 -20.51958,57.51153 -20.5229,57.51678 -20.52242,57.51942 -20.51869,57.51823 -20.51782,57.51905 -20.51672,57.52135 -20.51879,57.52203 -20.52196,57.5273 -20.52521,57.53019 -20.52536,57.53677 -20.52433,57.53741 -20.52265,57.54094 -20.52118,57.55286 -20.51955,57.5533 -20.51638,57.55804 -20.5173,57.55936 -20.51604,57.56274 -20.51627,57.56466 -20.51757,57.56828 -20.51698,57.57283 -20.51395,57.58582 -20.51304,57.60028 -20.50311,57.60095 -20.50098,57.60704 -20.50257,57.61793 -20.49761,57.62213 -20.49748,57.62316 -20.49694,57.62232 -20.49501,57.6263 -20.4938,57.62865 -20.49568,57.63301 -20.49515,57.6464 -20.48966,57.64784 -20.49049,57.65197 -20.48916,57.66105 -20.48337,57.66348 -20.48342,57.66584 -20.48128,57.66985 -20.48066,57.68345 -20.47402,57.68064 -20.47503,57.67688 -20.47165,57.68504 -20.4688,57.69068 -20.463,57.69235 -20.45806,57.70077 -20.45666,57.6992 -20.45537,57.70002 -20.45319,57.70874 -20.44855,57.70629 -20.44776,57.70458 -20.44404,57.70351 -20.44531,57.69906 -20.44415,57.69917 -20.44065,57.70415 -20.44271,57.70246 -20.43917,57.71054 -20.44381,57.71535 -20.44245,57.71758 -20.44565,57.7267 -20.43656,57.72796 -20.42669,57.72298 -20.42455,57.72135 -20.42291,57.72318 -20.42214,57.72089 -20.42002,57.72146 -20.42261,57.71996 -20.42239,57.71854 -20.41644,57.71466 -20.41819,57.71729 -20.42004,57.71686 -20.42147,57.71416 -20.41899,57.71309 -20.42001,57.7182 -20.4232,57.71883 -20.42687,57.71162 -20.41911,57.71059 -20.41346,57.7121 -20.40974,57.70952 -20.40673,57.71004 -20.40419,57.70779 -20.40408,57.70901 -20.40237,57.70273 -20.40154,57.70508 -20.40572,57.70371 -20.40795,57.70303 -20.40276,57.69968 -20.4019,57.69977 -20.39823,57.69271 -20.3952,57.70133 -20.39489,57.70005 -20.39133,57.70321 -20.38639,57.70322 -20.37488,57.70472 -20.37483,57.70113 -20.3713,57.70252 -20.37064,57.70167 -20.36988,57.70306 -20.36857,57.7081 -20.3698,57.70986 -20.3677,57.70852 -20.37026,57.71022 -20.36984,57.71364 -20.37343,57.71408 -20.37871,57.71769 -20.37867,57.7244 -20.37486,57.72899 -20.37574,57.73027 -20.37331,57.73454 -20.37184,57.73843 -20.36647,57.74023 -20.36594,57.745 -20.35818,57.74546 -20.35337,57.74862 -20.35167,57.74954 -20.3528,57.75213 -20.35176,57.75976 -20.35292,57.76568 -20.34875,57.76666 -20.34031,57.7648 -20.34017,57.76461 -20.33735,57.76649 -20.33898,57.77275 -20.33928,57.7792 -20.33795,57.77776 -20.33376,57.76944 -20.3326,57.76866 -20.33141,57.77195 -20.32802,57.77017 -20.3194,57.77356 -20.31682,57.77945 -20.31528,57.78103 -20.3125,57.78058 -20.30299,57.773 -20.29825,57.77411 -20.29477,57.78031 -20.29028,57.77457 -20.28041,57.78315 -20.29215,57.7896 -20.29471,57.78895 -20.29296,57.79318 -20.28918,57.79148 -20.28864,57.7915 -20.28449,57.78881 -20.2787,57.79427 -20.27552,57.79388 -20.27387,57.79045 -20.27262,57.79457 -20.27151,57.79406 -20.26996,57.79779 -20.26713,57.79672 -20.26523,57.79792 -20.26247,57.79218 -20.25859,57.79502 -20.25771,57.79848 -20.2529,57.79245 -20.24882,57.79351 -20.24678,57.79201 -20.24715,57.79151 -20.24381,57.78831 -20.24522,57.78676 -20.24313,57.78854 -20.23948,57.80217 -20.23672,57.80377 -20.23806,57.80373 -20.23461,57.80917 -20.23085,57.8061 -20.23044,57.80546 -20.2243,57.80404 -20.22506,57.80143 -20.22278,57.79784 -20.21585,57.79402 -20.2153,57.79015 -20.20481,57.78634 -20.20425,57.78357 -20.19831,57.78164 -20.19838,57.77659 -20.1942,57.77411 -20.18866,57.77574 -20.1838,57.77134 -20.1743,57.77236 -20.16802,57.77016 -20.16656,57.76881 -20.16787,57.76701 -20.16704,57.76315 -20.1607,57.75452 -20.15892,57.753 -20.16017,57.75758 -20.16262,57.75912 -20.1655,57.75697 -20.16597,57.75907 -20.16618,57.75741 -20.16687,57.75885 -20.1686,57.758 -20.16943,57.75586 -20.16684,57.75367 -20.16898,57.75525 -20.16721,57.75125 -20.16176,57.74921 -20.16267,57.75139 -20.16616,57.7486 -20.16697,57.74599 -20.16492,57.74724 -20.16084,57.74412 -20.16189,57.74412 -20.15982,57.74173 -20.159,57.74081 -20.15558,57.74616 -20.15695,57.74688 -20.15489,57.74899 -20.15549,57.74742 -20.15162,57.74869 -20.14816,57.74389 -20.14846,57.74455 -20.14655,57.74076 -20.14502,57.74123 -20.14376,57.73971 -20.14307,57.74253 -20.14335,57.74679 -20.14082,57.7492 -20.14252,57.75074 -20.14173,57.75454 -20.13762,57.75313 -20.1344,57.75415 -20.12959,57.757 -20.12848,57.75761 -20.12996,57.7585 -20.1281,57.74741 -20.10791,57.73893 -20.10692,57.73563 -20.10449,57.7318 -20.10456,57.72928 -20.10198,57.72444 -20.10553,57.72292 -20.10305,57.7175 -20.10345,57.7165 -20.09868,57.71019 -20.09989,57.70886 -20.09586,57.71065 -20.09497,57.70908 -20.09278,57.70432 -20.0918,57.70764 -20.09069,57.71156 -20.08654,57.70499 -20.08685,57.70372 -20.08314,57.70237 -20.08328,57.70121 -20.07977,57.70012 -20.08016,57.70006 -20.07748,57.69084 -20.07426,57.69289 -20.07243,57.69019 -20.07007,57.68998 -20.06797,57.69257 -20.06832,57.69117 -20.06644,57.68937 -20.06745,57.68985 -20.06619,57.68687 -20.06647,57.6893 -20.06372,57.68756 -20.06379,57.68562 -20.06127,57.68675 -20.05953,57.68917 -20.05993,57.68995 -20.05892,57.68773 -20.05939,57.68785 -20.05747,57.68601 -20.05804,57.68138 -20.05587,57.68381 -20.05158,57.68037 -20.04927,57.68056 -20.04683,57.68453 -20.04966,57.6845 -20.04603,57.68177 -20.04525,57.68588 -20.04355,57.68409 -20.04251,57.68581 -20.03795,57.68498 -20.03407,57.68214 -20.03466,57.6793 -20.03191,57.68035 -20.03019,57.68283 -20.02989,57.68264 -20.02303,57.68138 -20.0205,57.67789 -20.0209,57.67502 -20.01771,57.68178 -20.01863,57.68303 -20.01773,57.6819 -20.01544,57.68377 -20.01331,57.68153 -20.01301,57.68094 -20.01107,57.68387 -20.01055,57.68376 -20.00939,57.6723 -20.00725,57.6706 -20.00855,57.66853 -20.00622,57.66296 -20.00523,57.66172 -20.00195,57.66391 -20.00102,57.66223 -19.99926,57.66207 -20.00112,57.66108 -20.0002,57.65997 -20.00192,57.65634 -19.99994,57.65574 -19.99748,57.65333 -19.99692,57.65302 -20.00044,57.64987 -20.00377,57.64844 -20.0023,57.64877 -19.99982,57.64732 -20.00238,57.64324 -20.00101,57.6413 -19.99788,57.6372 -19.99558,57.63649 -19.99223,57.63284 -19.99312,57.63218 -19.99093,57.63479 -19.98758,57.63205 -19.98813,57.6331 -19.98727,57.63048 -19.98701,57.62944 -19.98483,57.62186 -19.98651,57.61816 -19.98469)))'), 4326),
    3857
  );
begin
  with cells as (
    select
      ST_CollectionExtract(ST_MakeValid(ST_Intersection(g.geom, island)), 3) as cell
    from ST_SquareGrid(v_size, ST_Expand(island, v_size)) as g
    where ST_Intersects(g.geom, island)
  ),
  land as (
    select cell
    from cells
    where cell is not null and not ST_IsEmpty(cell)
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
  agg as (
    select
      c.cell,
      coalesce(s.total_count, 0) as total_count,
      coalesce(s.critical_count, 0) as critical_count,
      s.top_category
    from land c
    left join lateral (
      select
        count(*)::int as total_count,
        count(*) filter (where p.severity = 'critical')::int as critical_count,
        mode() within group (order by p.category) as top_category
      from pts p
      where ST_Intersects(p.geom, c.cell)
    ) s on true
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
