-- Organization-managed master lists used by employee, leave, and payroll forms.
create table if not exists public.hr_master_list_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category text not null check (category in ('employment_type','pay_frequency','rate_type','department','position','contract_term','leave_type')),
  code text not null,
  label text not null,
  description text,
  numeric_value numeric(12,2),
  metadata jsonb not null default '{}'::jsonb,
  is_default boolean not null default false,
  is_active boolean not null default true,
  is_system boolean not null default false,
  sort_order integer not null default 100,
  effective_from date not null default current_date,
  effective_to date,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, category, code)
);

alter table public.hr_master_list_items enable row level security;
create policy "hr manages master lists" on public.hr_master_list_items for all to authenticated
using (organization_id = public.current_organization_id() and public.is_hr_staff())
with check (organization_id = public.current_organization_id() and public.is_hr_staff());
create index if not exists hr_master_list_lookup_idx on public.hr_master_list_items(organization_id, category, is_active, sort_order);

-- Custom organization values are allowed; legal behavior is driven by metadata rather than a hard-coded database enum.
alter table public.employees drop constraint if exists employees_employment_type_check;
alter table public.employees drop constraint if exists employees_pay_frequency_check;
alter table public.employees drop constraint if exists employees_rate_type_check;

insert into public.hr_master_list_items (organization_id,category,code,label,numeric_value,metadata,is_default,is_system,sort_order)
select o.id, seed.category, seed.code, seed.label, seed.numeric_value, seed.metadata, seed.is_default, true, seed.sort_order
from public.organizations o cross join (values
  ('employment_type','probationary','Probationary',null::numeric,'{"requires_probation":true}'::jsonb,true,10),
  ('employment_type','regular','Regular',null,'{"regular":true}'::jsonb,false,20),
  ('employment_type','fixed_term','Fixed-term contract',null,'{"requires_contract_end":true}'::jsonb,false,30),
  ('pay_frequency','weekly','Weekly',null,'{}'::jsonb,false,10),
  ('pay_frequency','semi_monthly','Semi-monthly',null,'{}'::jsonb,true,20),
  ('pay_frequency','monthly','Monthly',null,'{}'::jsonb,false,30),
  ('rate_type','hourly','Hourly',null,'{}'::jsonb,false,10),
  ('rate_type','daily','Daily',null,'{}'::jsonb,false,20),
  ('rate_type','weekly','Weekly',null,'{}'::jsonb,false,30),
  ('rate_type','monthly','Monthly',null,'{}'::jsonb,true,40),
  ('contract_term','3_months','3 months',3,'{}'::jsonb,false,10),
  ('contract_term','6_months','6 months',6,'{}'::jsonb,false,20),
  ('contract_term','12_months','12 months',12,'{}'::jsonb,true,30),
  ('leave_type','VL','Vacation leave',5,'{"entitlement_kind":"annual_credit"}'::jsonb,false,10),
  ('leave_type','SL','Sick leave',5,'{"entitlement_kind":"annual_credit"}'::jsonb,false,20),
  ('leave_type','BL','Birthday leave',1,'{"entitlement_kind":"annual_credit"}'::jsonb,false,30),
  ('leave_type','MAT','Maternity leave',null,'{"entitlement_kind":"statutory_event"}'::jsonb,false,40),
  ('leave_type','PAT','Paternity leave',null,'{"entitlement_kind":"statutory_event"}'::jsonb,false,50)
) as seed(category,code,label,numeric_value,metadata,is_default,sort_order)
on conflict (organization_id,category,code) do nothing;

create or replace function public.hr_set_master_default(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare target public.hr_master_list_items;
begin
  if not public.is_hr_staff() then raise exception 'HR access required'; end if;
  select * into target from public.hr_master_list_items where id=p_item_id and organization_id=public.current_organization_id();
  if target.id is null then raise exception 'Master-list item not found'; end if;
  update public.hr_master_list_items set is_default=false,updated_at=now() where organization_id=target.organization_id and category=target.category;
  update public.hr_master_list_items set is_default=true,is_active=true,updated_at=now() where id=target.id;
end $$;
revoke all on function public.hr_set_master_default(uuid) from public;
grant execute on function public.hr_set_master_default(uuid) to authenticated;
