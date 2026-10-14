-- Run once in the Supabase SQL Editor after rate_limits.sql (safe to re-run).
-- Lets a report link to where it was seen: a Facebook post (e.g. Mopays.com), a reel, or a news article.
-- Media stays on the original site; the app only links to it (and embeds Facebook video on tap).
-- Only https links on known hosts are accepted, so the field cannot be used to post arbitrary or phishing links.

create or replace function public.is_allowed_source_url(p_url text)
returns boolean
language sql
immutable
as $$
  select p_url is not null
    and char_length(p_url) <= 500
    and p_url !~ '\s'
    and p_url ~* ('^https://([a-z0-9-]+\.)*('
      || 'facebook\.com|fb\.watch|fb\.com|instagram\.com|youtube\.com|youtu\.be|tiktok\.com|x\.com|twitter\.com'
      || '|mopays\.com|defimedia\.info|lexpress\.mu|lemauricien\.com|topnews\.mu|ionnews\.mu|inside\.news|zinfos974\.com'
      || ')(/|$)');
$$;

alter table public.incidents add column if not exists source_url text;

alter table public.incidents drop constraint if exists incidents_source_url_allowed;
alter table public.incidents add constraint incidents_source_url_allowed
  check (source_url is null or public.is_allowed_source_url(source_url));

-- get_incidents gains source_url, which changes its return type, so it is dropped first.
drop function if exists public.get_incidents(int, text[], double precision, double precision, double precision, double precision);

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
  author_name text,
  source_url text
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
    p.full_name as author_name,
    i.source_url
  from public.incidents i
  left join public.profiles p on p.id = i.user_id
  where i.created_at >= now() - make_interval(hours => least(greatest(coalesce(hours_back, 168), 1), 2160))
    and i.hidden = false
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

-- create_incident gains p_source_url. Older signatures are dropped so PostgREST resolves one function.
drop function if exists public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean);
drop function if exists public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean, text);

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
  p_client_key text default null,
  p_source_url text default null
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
  v_source text := nullif(trim(coalesce(p_source_url, '')), '');
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
  if v_source is not null and not public.is_allowed_source_url(v_source) then
    raise exception 'source_url_not_allowed' using errcode = '22023';
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
    v_source := null;
  else
    if v_title is null then
      raise exception 'title is required' using errcode = '22023';
    end if;
    v_category := p_category::public.incident_category;
    v_severity := p_severity::public.incident_severity;
  end if;

  insert into public.incidents (
    user_id, title, description, category, severity, location,
    address_hint, media_urls, is_sos, source_url
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
    coalesce(p_is_sos, false),
    v_source
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean, text, text) from public;
grant execute on function public.create_incident(text, text, text, text, double precision, double precision, text, text[], boolean, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
