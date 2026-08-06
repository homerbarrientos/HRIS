create table public.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_number text not null,
  full_name text not null,
  pin_hash text not null,
  active boolean not null default true,
  kiosk_enabled boolean not null default true,
  personal_clock_enabled boolean not null default false,
  selfie_required boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, employee_number)
);

create table public.kiosk_devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  token_hash text not null,
  active boolean not null default true,
  last_used_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.kiosk_attendance_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  kiosk_device_id uuid not null references public.kiosk_devices(id),
  event_type public.attendance_event_type not null check (event_type in ('clock_in', 'clock_out')),
  occurred_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  location_unavailable boolean not null default false,
  selfie_data text not null,
  selfie_delete_after timestamptz not null default (now() + interval '30 days'),
  created_at timestamptz not null default now()
);

create index kiosk_events_employee_time_idx on public.kiosk_attendance_events(employee_id, occurred_at desc);
create index kiosk_events_org_time_idx on public.kiosk_attendance_events(organization_id, occurred_at desc);

alter table public.employees enable row level security;
alter table public.kiosk_devices enable row level security;
alter table public.kiosk_attendance_events enable row level security;

create policy "hr manages employees" on public.employees for all to authenticated
using (organization_id = public.current_organization_id() and public.is_hr_staff())
with check (organization_id = public.current_organization_id() and public.is_hr_staff());
create policy "hr manages kiosks" on public.kiosk_devices for all to authenticated
using (organization_id = public.current_organization_id() and public.is_hr_staff())
with check (organization_id = public.current_organization_id() and public.is_hr_staff());
create policy "hr views kiosk attendance" on public.kiosk_attendance_events for select to authenticated
using (organization_id = public.current_organization_id() and public.is_hr_staff());

create or replace function public.admin_create_employee(
  p_employee_number text,
  p_full_name text,
  p_pin text,
  p_kiosk_enabled boolean default true,
  p_personal_enabled boolean default false,
  p_selfie_required boolean default true
) returns public.employees
language plpgsql security definer set search_path = public, extensions
as $$
declare result public.employees;
begin
  if not public.is_hr_staff() then raise exception 'Not authorized'; end if;
  if length(trim(p_employee_number)) < 2 then raise exception 'Employee ID is required'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN must contain 4 to 8 digits'; end if;
  insert into public.employees (organization_id, employee_number, full_name, pin_hash, kiosk_enabled, personal_clock_enabled, selfie_required)
  values (public.current_organization_id(), upper(trim(p_employee_number)), trim(p_full_name), crypt(p_pin, gen_salt('bf')), p_kiosk_enabled, p_personal_enabled, p_selfie_required)
  returning * into result;
  return result;
end;
$$;

create or replace function public.admin_create_kiosk(p_name text)
returns text
language plpgsql security definer set search_path = public, extensions
as $$
declare raw_token text;
begin
  if not public.is_hr_staff() then raise exception 'Not authorized'; end if;
  raw_token := encode(gen_random_bytes(24), 'hex');
  insert into public.kiosk_devices (organization_id, name, token_hash, created_by)
  values (public.current_organization_id(), trim(p_name), crypt(raw_token, gen_salt('bf')), auth.uid());
  return raw_token;
end;
$$;

create or replace function public.kiosk_clock(
  p_kiosk_token text,
  p_employee_number text,
  p_pin text,
  p_selfie_data text,
  p_latitude double precision default null,
  p_longitude double precision default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare device public.kiosk_devices;
declare employee public.employees;
declare last_event public.kiosk_attendance_events;
declare next_type public.attendance_event_type;
declare saved_event public.kiosk_attendance_events;
begin
  select * into device from public.kiosk_devices
  where active and token_hash = crypt(p_kiosk_token, token_hash) limit 1;
  if device.id is null then raise exception 'Kiosk is not authorized'; end if;

  select * into employee from public.employees
  where organization_id = device.organization_id and employee_number = upper(trim(p_employee_number))
    and active and kiosk_enabled and pin_hash = crypt(p_pin, pin_hash) limit 1;
  if employee.id is null then raise exception 'Employee ID or PIN is incorrect'; end if;
  if employee.selfie_required and coalesce(length(p_selfie_data), 0) < 100 then raise exception 'Selfie is required'; end if;

  select * into last_event from public.kiosk_attendance_events
  where employee_id = employee.id order by occurred_at desc limit 1;
  if last_event.occurred_at > now() - interval '30 seconds' then raise exception 'Please wait before recording another attendance event'; end if;
  next_type := case when last_event.event_type = 'clock_in' then 'clock_out'::public.attendance_event_type else 'clock_in'::public.attendance_event_type end;

  insert into public.kiosk_attendance_events (organization_id, employee_id, kiosk_device_id, event_type, latitude, longitude, location_unavailable, selfie_data)
  values (device.organization_id, employee.id, device.id, next_type, p_latitude, p_longitude, p_latitude is null or p_longitude is null, p_selfie_data)
  returning * into saved_event;
  update public.kiosk_devices set last_used_at = now() where id = device.id;
  return jsonb_build_object('employee_name', employee.full_name, 'event_type', saved_event.event_type, 'occurred_at', saved_event.occurred_at, 'location_flagged', saved_event.location_unavailable);
end;
$$;

revoke all on function public.admin_create_employee(text,text,text,boolean,boolean,boolean) from public;
revoke all on function public.admin_create_kiosk(text) from public;
grant execute on function public.admin_create_employee(text,text,text,boolean,boolean,boolean) to authenticated;
grant execute on function public.admin_create_kiosk(text) to authenticated;
revoke all on function public.kiosk_clock(text,text,text,text,double precision,double precision) from public;
grant execute on function public.kiosk_clock(text,text,text,text,double precision,double precision) to anon, authenticated;

create or replace function public.purge_expired_attendance_selfies()
returns void language sql security definer set search_path = public
as $$ update public.kiosk_attendance_events set selfie_data = '' where selfie_delete_after <= now() and selfie_data <> '' $$;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'purge-hris-attendance-selfies';
  perform cron.schedule('purge-hris-attendance-selfies', '15 2 * * *', 'select public.purge_expired_attendance_selfies()');
exception when others then
  raise notice 'pg_cron was not scheduled; call purge_expired_attendance_selfies daily';
end $$;
