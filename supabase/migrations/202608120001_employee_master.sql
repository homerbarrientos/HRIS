alter table public.employees
  add column if not exists email text, add column if not exists mobile_number text,
  add column if not exists birth_date date, add column if not exists address text,
  add column if not exists department text, add column if not exists position_title text,
  add column if not exists hire_date date, add column if not exists employment_type text not null default 'probationary',
  add column if not exists employment_status text not null default 'active', add column if not exists probation_months integer,
  add column if not exists regularization_due_date date, add column if not exists contract_start_date date,
  add column if not exists contract_end_date date, add column if not exists contract_term_months integer,
  add column if not exists pay_frequency text not null default 'semi_monthly', add column if not exists rate_type text not null default 'monthly',
  add column if not exists basic_rate numeric(14,2), add column if not exists sss_number text,
  add column if not exists philhealth_number text, add column if not exists pagibig_number text,
  add column if not exists tin_number text, add column if not exists thirteenth_month_enabled boolean not null default true,
  add column if not exists sss_enabled boolean not null default true, add column if not exists philhealth_enabled boolean not null default true,
  add column if not exists pagibig_enabled boolean not null default true, add column if not exists updated_at timestamptz not null default now();

do $$ begin alter table public.employees add constraint employees_employment_type_check check (employment_type in ('probationary','regular','fixed_term')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.employees add constraint employees_employment_status_check check (employment_status in ('active','on_leave','inactive','separated')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.employees add constraint employees_pay_frequency_check check (pay_frequency in ('weekly','semi_monthly','monthly')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.employees add constraint employees_rate_type_check check (rate_type in ('hourly','daily','weekly','monthly')); exception when duplicate_object then null; end $$;

create table if not exists public.employment_policy_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  probation_months integer not null default 6 check (probation_months between 1 and 6),
  probation_alert_days integer[] not null default array[60,30,7], contract_term_options integer[] not null default array[3,6,12],
  contract_alert_days integer[] not null default array[60,30,7], default_pay_frequency text not null default 'semi_monthly' check (default_pay_frequency in ('weekly','semi_monthly','monthly')),
  updated_by uuid references public.profiles(id), updated_at timestamptz not null default now()
);
create table if not exists public.employee_leave_entitlements (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade, leave_code text not null, leave_name text not null,
  annual_days numeric(8,2), entitlement_kind text not null default 'annual_credit' check (entitlement_kind in ('annual_credit','statutory_event')),
  enabled boolean not null default true, effective_from date not null default current_date, effective_to date, created_at timestamptz not null default now(),
  unique(employee_id, leave_code, effective_from)
);
alter table public.employment_policy_settings enable row level security;
alter table public.employee_leave_entitlements enable row level security;
create policy "hr manages employment settings" on public.employment_policy_settings for all to authenticated using (organization_id = public.current_organization_id() and public.is_hr_staff()) with check (organization_id = public.current_organization_id() and public.is_hr_staff());
create policy "hr manages employee leave entitlements" on public.employee_leave_entitlements for all to authenticated using (organization_id = public.current_organization_id() and public.is_hr_staff()) with check (organization_id = public.current_organization_id() and public.is_hr_staff());

create or replace view public.employee_employment_alerts with (security_invoker = true) as
select e.organization_id, e.id employee_id, e.employee_number, e.full_name,
  case when e.employment_type = 'probationary' then 'regularization' else 'contract_renewal' end alert_type,
  case when e.employment_type = 'probationary' then e.regularization_due_date else e.contract_end_date end due_date,
  (case when e.employment_type = 'probationary' then e.regularization_due_date else e.contract_end_date end - current_date) days_remaining
from public.employees e where e.active and e.employment_status = 'active'
and ((e.employment_type = 'probationary' and e.regularization_due_date is not null) or (e.employment_type = 'fixed_term' and e.contract_end_date is not null));
create index if not exists employees_org_employment_idx on public.employees(organization_id, employment_type, employment_status);
create index if not exists leave_entitlements_employee_idx on public.employee_leave_entitlements(employee_id, enabled);
