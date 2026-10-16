-- Run once in the Supabase SQL Editor (safe to re-run).
-- Adds one public map notice. /admin edits the message and severity color.
-- The map shows the message, then it collapses to a warning sign.
-- The message is free text, so the same notice can later say something other than a curfew.

create table if not exists public.site_alerts (
  id smallint primary key default 1 check (id = 1),
  active boolean not null default false,
  message text not null default 'Curfew in progress',
  severity public.incident_severity not null default 'high',
  updated_at timestamptz not null default now(),
  constraint site_alerts_message_len check (char_length(message) between 1 and 120)
);

insert into public.site_alerts (id)
values (1)
on conflict (id) do nothing;

alter table public.site_alerts enable row level security;

drop policy if exists site_alerts_select_public on public.site_alerts;
create policy site_alerts_select_public on public.site_alerts
  for select to anon, authenticated
  using (true);

grant select on public.site_alerts to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.site_alerts;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
