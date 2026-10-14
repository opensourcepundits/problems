-- Run once in the Supabase SQL Editor after the main schema (safe to re-run).
-- Rate limits for SOS and reports. Every visitor is anonymous, so limits are keyed on:
--   * the device key the app keeps in localStorage (passed to create_incident as p_client_key), and
--   * the caller's IP as a looser flood guard. Mobile carriers put many people behind one IP (CGNAT),
--     so the IP cap is deliberately high: it stops floods, not a crowd reporting the same riot.
-- Inserts that skip the RPC have no device key and fall back to the strict per-device limit on their IP.
-- Raw IPs and device keys are never stored, only SHA-256 hashes, and rows expire after a day.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.rate_limit_hits (
  id bigint generated always as identity primary key,
  bucket text not null,
  subject text not null,
  created_at timestamptz not null default now()
);

create index if not exists rate_limit_hits_lookup
  on public.rate_limit_hits (bucket, subject, created_at desc);
create index if not exists rate_limit_hits_expiry
  on public.rate_limit_hits (created_at);

-- No policies: only the security definer function below can read or write it.
alter table public.rate_limit_hits enable row level security;
revoke all on public.rate_limit_hits from anon, authenticated;

-- Tune limits here. Windows are in seconds.
create or replace function public.rate_limit_rules(p_kind text)
returns table (scope text, max_hits int, window_seconds int)
language sql
immutable
as $$
  select rules.scope, rules.max_hits, rules.window_seconds from (values
    ('sos',    'device',   3,  600),   -- 3 SOS per device per 10 min
    ('sos',    'ip',      30,  600),   -- 30 SOS per IP per 10 min
    ('report', 'device',   5,  600),   -- 5 reports per device per 10 min
    ('report', 'device',  20, 3600),   -- 20 reports per device per hour
    ('report', 'ip',      60,  600)    -- 60 reports per IP per 10 min
  ) as rules (kind, scope, max_hits, window_seconds)
  where rules.kind = p_kind;
$$;

create or replace function public.request_ip()
returns text
language sql
stable
as $$
  -- cf-connecting-ip is set by Supabase's edge and cannot be spoofed by the client.
  select nullif(trim(coalesce(
    current_setting('request.headers', true)::json->>'cf-connecting-ip',
    current_setting('request.headers', true)::json->>'x-real-ip',
    split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
    ''
  )), '');
$$;

create or replace function public.enforce_incident_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_kind text := case when new.is_sos then 'sos' else 'report' end;
  v_ip text := public.request_ip();
  v_device text := nullif(current_setting('crisis.client_key', true), '');
  v_subject text;
  v_rule record;
  v_count int;
  v_oldest timestamptz;
  v_retry int;
begin
  -- The service role (admin tools, SQL editor) is never limited.
  if coalesce(auth.role(), '') = 'service_role' or v_ip is null then
    return new;
  end if;

  for v_rule in select * from public.rate_limit_rules(v_kind) loop
    v_subject := encode(digest(
      'crisis-rate-limit:' || case
        when v_rule.scope = 'ip' then 'ip:' || v_ip
        when v_device is not null then 'device:' || v_device
        else 'ip-device:' || v_ip
      end, 'sha256'), 'hex');

    select count(*), min(created_at) into v_count, v_oldest
    from public.rate_limit_hits
    where bucket = v_kind || ':' || v_rule.scope
      and subject = v_subject
      and created_at > now() - make_interval(secs => v_rule.window_seconds);

    if v_count >= v_rule.max_hits then
      v_retry := greatest(1, ceil(extract(epoch from (v_oldest + make_interval(secs => v_rule.window_seconds) - now())))::int);
      raise exception 'rate_limited:%:%', v_kind, v_retry
        using errcode = 'P0001', hint = 'Too many requests. Retry after ' || v_retry || ' seconds.';
    end if;
  end loop;

  -- Record one hit per scope (device and ip), then drop this subject's expired rows.
  insert into public.rate_limit_hits (bucket, subject)
  select distinct v_kind || ':' || r.scope, encode(digest(
    'crisis-rate-limit:' || case
      when r.scope = 'ip' then 'ip:' || v_ip
      when v_device is not null then 'device:' || v_device
      else 'ip-device:' || v_ip
    end, 'sha256'), 'hex')
  from public.rate_limit_rules(v_kind) r;

  delete from public.rate_limit_hits where created_at < now() - interval '1 day';
  return new;
end;
$$;

revoke all on function public.enforce_incident_rate_limit() from public;

drop trigger if exists incidents_rate_limit on public.incidents;
create trigger incidents_rate_limit
  before insert on public.incidents
  for each row execute function public.enforce_incident_rate_limit();

-- create_incident gains p_client_key (the device key). The old 9-argument version is dropped
-- so PostgREST resolves a single function.
drop function if exists public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean);

create or replace function public.create_incident(
  p_title text,
  p_description text,
  p_category text,
  p_severity text,
  p_lng double precision,
  p_lat double precision,
  p_address_hint text default null,
  p_media_urls text[] default '{}',
  p_is_sos boolean default false,
  p_client_key text default null
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

  -- Read by the rate-limit trigger for this transaction only.
  if p_client_key is not null and char_length(p_client_key) between 8 and 80 then
    perform set_config('crisis.client_key', p_client_key, true);
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

revoke all on function public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean, text) from public;
grant execute on function public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean, text) to anon, authenticated;

notify pgrst, 'reload schema';
