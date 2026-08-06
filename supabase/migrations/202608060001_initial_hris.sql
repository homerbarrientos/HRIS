create extension if not exists pgcrypto;

create type public.employee_role as enum ('employee', 'manager', 'hr', 'payroll', 'admin');
create type public.attendance_event_type as enum ('clock_in', 'clock_out', 'break_start', 'break_end');
create type public.request_status as enum ('pending', 'approved', 'rejected', 'cancelled');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  timezone text not null default 'Asia/Manila',
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_number text not null,
  full_name text not null,
  role public.employee_role not null default 'employee',
  active boolean not null default true,
  pay_schedule text not null default 'semi_monthly' check (pay_schedule in ('weekly', 'semi_monthly', 'monthly')),
  remote_clock_in boolean not null default false,
  meal_break_enabled boolean not null default true,
  meal_break_minutes integer not null default 60 check (meal_break_minutes between 0 and 240),
  grace_period_enabled boolean not null default true,
  grace_period_minutes integer not null default 10 check (grace_period_minutes between 0 and 120),
  created_at timestamptz not null default now(),
  unique (organization_id, employee_number)
);

create table public.work_locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  radius_meters integer not null default 150 check (radius_meters > 0),
  allow_and_flag_outside boolean not null default true,
  active boolean not null default true
);

create table public.attendance_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.profiles(id) on delete cascade,
  event_type public.attendance_event_type not null,
  occurred_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  work_location_id uuid references public.work_locations(id),
  outside_geofence boolean not null default false,
  selfie_path text,
  device_fingerprint text,
  notes text,
  created_at timestamptz not null default now()
);

create table public.leave_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  days_per_year numeric(6,2),
  statutory boolean not null default false,
  active boolean not null default true,
  unique (organization_id, name)
);

create table public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.profiles(id) on delete cascade,
  leave_type_id uuid not null references public.leave_types(id),
  starts_on date not null,
  ends_on date not null,
  requested_days numeric(6,2) not null check (requested_days > 0),
  reason text,
  status public.request_status not null default 'pending',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create index attendance_events_employee_time_idx on public.attendance_events(employee_id, occurred_at desc);
create index leave_requests_employee_idx on public.leave_requests(employee_id, created_at desc);

create or replace function public.current_organization_id()
returns uuid language sql stable security definer set search_path = public
as $$ select organization_id from public.profiles where id = auth.uid() $$;

create or replace function public.is_hr_staff()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select role in ('manager', 'hr', 'payroll', 'admin') from public.profiles where id = auth.uid()), false) $$;

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.work_locations enable row level security;
alter table public.attendance_events enable row level security;
alter table public.leave_types enable row level security;
alter table public.leave_requests enable row level security;

create policy "members view organization" on public.organizations for select to authenticated
using (id = public.current_organization_id());
create policy "members view profiles" on public.profiles for select to authenticated
using (organization_id = public.current_organization_id());
create policy "employees update own profile" on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid() and organization_id = public.current_organization_id());
create policy "members view locations" on public.work_locations for select to authenticated
using (organization_id = public.current_organization_id());
create policy "employees view own attendance" on public.attendance_events for select to authenticated
using (employee_id = auth.uid() or (organization_id = public.current_organization_id() and public.is_hr_staff()));
create policy "employees record own attendance" on public.attendance_events for insert to authenticated
with check (employee_id = auth.uid() and organization_id = public.current_organization_id());
create policy "members view leave types" on public.leave_types for select to authenticated
using (organization_id = public.current_organization_id());
create policy "employees view leave requests" on public.leave_requests for select to authenticated
using (employee_id = auth.uid() or (organization_id = public.current_organization_id() and public.is_hr_staff()));
create policy "employees request leave" on public.leave_requests for insert to authenticated
with check (employee_id = auth.uid() and organization_id = public.current_organization_id());
create policy "employees cancel pending leave" on public.leave_requests for update to authenticated
using (employee_id = auth.uid() and status = 'pending')
with check (employee_id = auth.uid() and status = 'cancelled');
create policy "hr reviews leave" on public.leave_requests for update to authenticated
using (organization_id = public.current_organization_id() and public.is_hr_staff())
with check (organization_id = public.current_organization_id() and public.is_hr_staff());

comment on column public.attendance_events.selfie_path is 'Private storage path; delete the object after 30 days.';
