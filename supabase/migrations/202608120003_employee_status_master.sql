-- Make employee lifecycle status organization-managed and add retired status.
alter table public.hr_master_list_items drop constraint if exists hr_master_list_items_category_check;
alter table public.hr_master_list_items add constraint hr_master_list_items_category_check
  check (category in ('employment_type','employee_status','pay_frequency','rate_type','department','position','contract_term','leave_type'));
alter table public.employees drop constraint if exists employees_employment_status_check;

insert into public.hr_master_list_items (organization_id,category,code,label,metadata,is_default,is_system,sort_order)
select o.id,'employee_status',seed.code,seed.label,seed.metadata,seed.is_default,true,seed.sort_order
from public.organizations o cross join (values
  ('active','Active','{"attendance_allowed":true}'::jsonb,true,10),
  ('on_leave','On leave','{"attendance_allowed":false}'::jsonb,false,20),
  ('inactive','Inactive','{"attendance_allowed":false}'::jsonb,false,30),
  ('retired','Retired','{"attendance_allowed":false}'::jsonb,false,40),
  ('separated','Separated','{"attendance_allowed":false}'::jsonb,false,50)
) as seed(code,label,metadata,is_default,sort_order)
on conflict (organization_id,category,code) do nothing;
