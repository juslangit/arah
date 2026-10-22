-- Arah community reports. Phones sign in anonymously (one session per
-- device); every write goes through the functions below, which enforce the
-- rules. There are deliberately no insert/update/delete policies: a phone
-- holding the published anon key cannot write rows directly.

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('polis','kemalangan','kesesakan','bahaya','banjir','ditutup')),
  sub         text not null default '',
  lat         double precision not null check (lat between 0.5 and 7.8),
  lon         double precision not null check (lon between 99.0 and 120.0),
  heading     real not null default 0,
  device      uuid not null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  yes         int not null default 0,
  no          int not null default 0
);
create index reports_live on public.reports (expires_at, lat, lon);

create table public.report_votes (
  report_id uuid not null references public.reports(id) on delete cascade,
  device    uuid not null,
  still_there boolean not null,
  created_at timestamptz not null default now(),
  primary key (report_id, device)
);

alter table public.reports enable row level security;
alter table public.report_votes enable row level security;
-- No policies at all: reads go through reports_near(), which never returns
-- the reporting phone's id (only whether the report is the caller's own).

-- Lifetimes, extensions and caps per kind (mirrors lib/reports/reports.dart).
create or replace function public.report_rule(p_kind text, p_sub text,
  out life interval, out extend interval, out cap interval, out no_to_remove int)
language sql immutable as $$
  select case
    when p_kind = 'polis'      then row('60 min'::interval, '30 min'::interval, '2 h'::interval, 2)
    when p_kind = 'kemalangan' then row('60 min', '30 min', '3 h', 2)
    when p_kind = 'kesesakan'  then row('30 min', '15 min', '2 h', 2)
    when p_kind = 'banjir'     then row('3 h', '1 h', '12 h', 2)
    when p_kind = 'ditutup'    then row('2 h', '1 h', '24 h', 3)
    when p_sub = 'bahu'        then row('30 min', '15 min', '2 h', 1)
    when p_sub = 'lubang'      then row('7 days', '7 days', '30 days', 3)
    when p_sub = 'lampu'       then row('4 h', '2 h', '12 h', 2)
    when p_sub = 'kerja'       then row('24 h', '24 h', '14 days', 3)
    else row('60 min'::interval, '30 min'::interval, '3 h'::interval, 2)
  end.*
$$;

create or replace function public.create_report(p_kind text, p_sub text, p_lat double precision,
  p_lon double precision, p_heading real)
returns public.reports
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  r public.reports;
  rule record;
begin
  if me is null then raise exception 'sign in first'; end if;
  -- At most 10 reports an hour per phone.
  if (select count(*) from reports where device = me and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too many reports';
  end if;
  select * into rule from report_rule(p_kind, p_sub);
  insert into reports (kind, sub, lat, lon, heading, device, expires_at)
  values (p_kind, coalesce(p_sub, ''), p_lat, p_lon, coalesce(p_heading, 0), me, now() + rule.life)
  returning * into r;
  r.device := null; -- never hand phone ids back
  return r;
end $$;

create or replace function public.vote_report(p_id uuid, p_still_there boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  r public.reports;
  rule record;
begin
  if me is null then raise exception 'sign in first'; end if;
  select * into r from reports where id = p_id and expires_at > now() for update;
  if not found then return; end if;
  -- One vote per phone per report.
  insert into report_votes (report_id, device, still_there) values (p_id, me, p_still_there)
  on conflict do nothing;
  if not found then return; end if;
  select * into rule from report_rule(r.kind, r.sub);
  if p_still_there then
    update reports set yes = yes + 1,
      expires_at = least(expires_at + rule.extend, created_at + rule.cap)
    where id = p_id;
  elsif r.device = me or r.no + 1 >= rule.no_to_remove then
    update reports set no = no + 1, expires_at = now() where id = p_id;
  elsif r.kind = 'kesesakan' then
    update reports set no = no + 1, expires_at = expires_at - interval '15 min' where id = p_id;
  else
    update reports set no = no + 1 where id = p_id;
  end if;
end $$;

create or replace function public.reports_near(p_lat double precision, p_lon double precision, p_km double precision)
returns table (id uuid, kind text, sub text, lat double precision, lon double precision, heading real,
               created_at timestamptz, expires_at timestamptz, yes int, no int, mine boolean)
language sql stable security definer set search_path = public as $$
  select r.id, r.kind, r.sub, r.lat, r.lon, r.heading, r.created_at, r.expires_at, r.yes, r.no,
         r.device = auth.uid()
  from reports r
  where auth.uid() is not null
    and r.expires_at > now()
    and r.lat between p_lat - p_km / 111.0 and p_lat + p_km / 111.0
    and r.lon between p_lon - p_km / 111.0 and p_lon + p_km / 111.0
  order by r.created_at desc
  limit 500
$$;

revoke all on function public.create_report, public.vote_report, public.reports_near from public, anon;
grant execute on function public.create_report, public.vote_report, public.reports_near to authenticated;
