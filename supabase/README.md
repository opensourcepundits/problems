# Supabase setup

Run these files in the Supabase dashboard: **SQL Editor → New query → paste the file → Run**.
Every file is safe to run more than once.

## ⏳ Pending: run these when you have time

The app is already deployed and works without them. These scripts switch on rate limits, source links, and the map notice.

| Order | File | What it does |
|---|---|---|
| 1 | [`rate_limits.sql`](rate_limits.sql) | Limits how often one device can send SOS and reports |
| 2 | [`source_links.sql`](source_links.sql) | Lets a report link to where it was seen (e.g. a Mopays Facebook video) |
| 3 | [`site_alert.sql`](site_alert.sql) | Lets /admin put a collapsible notice on the map (message + severity color) |

Run 1 then 2: `source_links.sql` builds on the version of `create_incident` from `rate_limits.sql`. `site_alert.sql` can run any time.

When all three are done, delete this "Pending" section.

### Rate limits (`rate_limits.sql`)

| | Per device | Per IP (flood guard) |
|---|---|---|
| SOS | 3 per 10 min | 30 per 10 min |
| Reports | 5 per 10 min, 20 per hour | 60 per 10 min |

- Every visitor is anonymous, so the app sends a random device key. The per-IP cap is deliberately loose because
  Mauritian mobile carriers put many people behind one shared IP.
- Only hashes of IPs and device keys are stored, and rows are deleted after a day.
- People who hit the limit see "try again in N min". SOS also tells them to call 999.
- The service role (dashboard, SQL editor, admin tools) is never limited.
- Tune the numbers in `public.rate_limit_rules`.

### Source links (`source_links.sql`)

- Adds `incidents.source_url`. The video stays on the original site; the app links to it, and Facebook videos
  play inside the incident card only after a tap.
- Only `https` links from Facebook, Instagram, YouTube, TikTok, X, mopays.com and the main Mauritian news sites
  are accepted. The database enforces this with a check constraint.
- To allow another site, add it to `public.is_allowed_source_url` here **and** to `src/lib/sources.ts`.

### Is it safe?

- Nothing is deleted. It adds one table (`rate_limit_hits`) and one column (`source_url`).
- `create_incident` and `get_incidents` are replaced with versions that accept extra optional inputs, so older
  versions of the app keep working.
- If you changed `create_incident` or `get_incidents` directly in Supabase (not in this repo), those changes
  will be overwritten. Copy them first.

### Check it worked

```sql
select column_name from information_schema.columns
where table_name = 'incidents' and column_name = 'source_url';          -- 1 row

select tgname from pg_trigger where tgname = 'incidents_rate_limit';  -- 1 row
```

Optional: give an existing report a link to see the source card in the app.

```sql
update public.incidents
set source_url = 'https://www.facebook.com/mopays/videos/1496003622368850'
where id = '<report id>';
```

### Undo

```sql
drop trigger if exists incidents_rate_limit on public.incidents;
drop table if exists public.rate_limit_hits;
alter table public.incidents drop constraint if exists incidents_source_url_allowed;
alter table public.incidents drop column if exists source_url;
```

Then re-run the `create_incident` and `get_incidents` definitions from `schema.sql` to restore the originals.
The app keeps working in between: it falls back to the older versions automatically.

## Full setup from scratch

For a new Supabase project, run in this order:

1. `schema.sql`
2. `anonymous.sql`
3. `admin.sql`
4. `squares.sql`
5. `zones.sql`
6. `rate_limits.sql`
7. `source_links.sql`
8. `site_alert.sql`
