-- Run once in the Supabase SQL Editor after the main schema.
-- Lets visitors report, comment, vote, and upload without an account.

alter table public.incidents alter column user_id drop not null;
alter table public.incident_comments alter column user_id drop not null;
alter table public.incident_confirmations alter column user_id drop not null;
alter table public.incident_confirmations add column if not exists voter_key text;
alter table public.incident_confirmations drop constraint if exists incident_confirmations_one_vote;
create unique index if not exists incident_confirmations_one_voter
  on public.incident_confirmations (incident_id, voter_key);

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

drop policy if exists incidents_insert_own on public.incidents;
create policy incidents_insert_own on public.incidents
  for insert to anon, authenticated
  with check (user_id is not distinct from auth.uid());

drop policy if exists comments_insert_own on public.incident_comments;
create policy comments_insert_own on public.incident_comments
  for insert to anon, authenticated
  with check (user_id is not distinct from auth.uid());

grant insert, update on public.incidents to anon, authenticated;
grant insert, delete on public.incident_comments to anon, authenticated;

drop policy if exists incident_media_authenticated_insert on storage.objects;
drop policy if exists incident_media_public_insert on storage.objects;
create policy incident_media_public_insert on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'incident-media'
    and (storage.foldername(name))[1] = 'public'
  );

notify pgrst, 'reload schema';
