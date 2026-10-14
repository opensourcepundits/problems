-- Run once in the Supabase SQL Editor.
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
      and hidden = false
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
