-- Run this whole script once in the Supabase SQL Editor.
-- Replaces the map functions, lets a vote be cleared, and adds resolved.

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

notify pgrst, 'reload schema';
