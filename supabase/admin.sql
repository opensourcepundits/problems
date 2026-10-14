-- Run once in the Supabase SQL Editor.
-- Lets /admin hide a report. Hidden reports stay in the database and
-- disappear from the public map, including zone counts.

alter table public.incidents add column if not exists hidden boolean not null default false;
create index if not exists incidents_hidden_idx on public.incidents (hidden) where hidden;

drop policy if exists incidents_select_public on public.incidents;
create policy incidents_select_public on public.incidents
  for select to anon, authenticated
  using (hidden = false and (status <> 'debunked' or user_id = auth.uid()));

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

notify pgrst, 'reload schema';
