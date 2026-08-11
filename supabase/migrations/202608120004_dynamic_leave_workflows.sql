-- Dynamic leave requests, credit balances, and rank-based approval workflows.
alter table public.hr_master_list_items drop constraint if exists hr_master_list_items_category_check;
alter table public.hr_master_list_items add constraint hr_master_list_items_category_check check (category in ('employment_type','employee_status','pay_frequency','rate_type','department','position','contract_term','leave_type','job_level','approval_role'));
alter table public.employees add column if not exists job_level text default 'rank_and_file';
update public.employees set job_level='rank_and_file' where job_level is null;

insert into public.hr_master_list_items(organization_id,category,code,label,is_default,is_system,sort_order)
select o.id,seed.category,seed.code,seed.label,seed.is_default,true,seed.sort_order from public.organizations o cross join (values
('job_level','rank_and_file','Rank-and-file',true,10),('job_level','supervisor','Supervisor',false,20),('job_level','manager','Manager',false,30),('job_level','department_head','Department head',false,40),
('approval_role','supervisor','Supervisor',false,10),('approval_role','manager','Manager',false,20),('approval_role','department_head','Department head',false,30),('approval_role','hr','HR',true,40),('approval_role','executive','Executive approver',false,50)
) seed(category,code,label,is_default,sort_order) on conflict(organization_id,category,code) do nothing;

create table public.leave_approval_workflows(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null, job_level_code text, leave_code text, min_days numeric(6,2) not null default 0.5,
 max_days numeric(6,2), priority integer not null default 100, active boolean not null default true,
 created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.leave_approval_workflow_steps(
 id uuid primary key default gen_random_uuid(), workflow_id uuid not null references public.leave_approval_workflows(id) on delete cascade,
 step_order integer not null check(step_order>0), approver_role_code text not null, specific_employee_id uuid references public.employees(id),
 required boolean not null default true, unique(workflow_id,step_order)
);
create table public.employee_leave_requests(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete cascade, leave_code text not null, starts_on date not null,
 ends_on date not null, requested_days numeric(6,2) not null check(requested_days>0), reason text,
 workflow_id uuid references public.leave_approval_workflows(id), current_step integer not null default 1,
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),
 submitted_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check(ends_on>=starts_on)
);
create table public.employee_leave_approvals(
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.employee_leave_requests(id) on delete cascade,
 step_order integer not null, approver_role_code text not null, specific_employee_id uuid references public.employees(id),
 status text not null default 'waiting' check(status in('waiting','pending','approved','rejected','skipped')),
 acted_by uuid references public.profiles(id), acted_at timestamptz, remarks text, unique(request_id,step_order)
);
create table public.employee_leave_ledger(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete cascade, leave_code text not null,
 amount numeric(8,2) not null, entry_type text not null check(entry_type in('opening','adjustment','approved_leave','reversal')),
 request_id uuid references public.employee_leave_requests(id), notes text, created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);

alter table public.leave_approval_workflows enable row level security;alter table public.leave_approval_workflow_steps enable row level security;alter table public.employee_leave_requests enable row level security;alter table public.employee_leave_approvals enable row level security;alter table public.employee_leave_ledger enable row level security;
create policy "hr manages leave workflows" on public.leave_approval_workflows for all to authenticated using(organization_id=public.current_organization_id() and public.is_hr_staff()) with check(organization_id=public.current_organization_id() and public.is_hr_staff());
create policy "hr manages workflow steps" on public.leave_approval_workflow_steps for all to authenticated using(exists(select 1 from public.leave_approval_workflows w where w.id=workflow_id and w.organization_id=public.current_organization_id()) and public.is_hr_staff()) with check(exists(select 1 from public.leave_approval_workflows w where w.id=workflow_id and w.organization_id=public.current_organization_id()) and public.is_hr_staff());
create policy "hr manages employee leave" on public.employee_leave_requests for all to authenticated using(organization_id=public.current_organization_id() and public.is_hr_staff()) with check(organization_id=public.current_organization_id() and public.is_hr_staff());
create policy "hr manages leave approvals" on public.employee_leave_approvals for all to authenticated using(exists(select 1 from public.employee_leave_requests r where r.id=request_id and r.organization_id=public.current_organization_id()) and public.is_hr_staff()) with check(exists(select 1 from public.employee_leave_requests r where r.id=request_id and r.organization_id=public.current_organization_id()) and public.is_hr_staff());
create policy "hr manages leave ledger" on public.employee_leave_ledger for all to authenticated using(organization_id=public.current_organization_id() and public.is_hr_staff()) with check(organization_id=public.current_organization_id() and public.is_hr_staff());

create or replace view public.employee_leave_balances with(security_invoker=true) as
select e.organization_id,e.id employee_id,e.employee_number,e.full_name,x.leave_code,x.leave_name,x.entitlement_kind,x.enabled,
 case when x.entitlement_kind='statutory_event' then 999::numeric else coalesce(x.annual_days,0)+coalesce(sum(l.amount),0) end balance_days
from public.employees e join public.employee_leave_entitlements x on x.employee_id=e.id
left join public.employee_leave_ledger l on l.employee_id=e.id and l.leave_code=x.leave_code
where x.effective_to is null or x.effective_to>=current_date group by e.organization_id,e.id,e.employee_number,e.full_name,x.leave_code,x.leave_name,x.entitlement_kind,x.enabled,x.annual_days;

create or replace function public.hr_submit_leave_request(p_employee_id uuid,p_leave_code text,p_starts_on date,p_ends_on date,p_requested_days numeric,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare emp public.employees; flow public.leave_approval_workflows; req_id uuid; bal numeric; first_step integer;
begin
 if not public.is_hr_staff() then raise exception 'HR access required'; end if;
 select * into emp from public.employees where id=p_employee_id and organization_id=public.current_organization_id();if emp.id is null then raise exception 'Employee not found';end if;
 select balance_days into bal from public.employee_leave_balances where employee_id=p_employee_id and leave_code=p_leave_code and enabled;
 if bal is null then raise exception 'Leave type is not enabled for this employee';end if;if bal<p_requested_days then raise exception 'Insufficient leave credits. Available: % days',bal;end if;
 select * into flow from public.leave_approval_workflows w where w.organization_id=emp.organization_id and w.active and (w.job_level_code is null or w.job_level_code=emp.job_level) and (w.leave_code is null or w.leave_code=p_leave_code) and p_requested_days>=w.min_days and (w.max_days is null or p_requested_days<=w.max_days) order by (w.job_level_code is not null)::int+(w.leave_code is not null)::int desc,w.priority asc limit 1;
 if flow.id is null then raise exception 'No approval workflow matches this employee and leave request';end if;
 insert into public.employee_leave_requests(organization_id,employee_id,leave_code,starts_on,ends_on,requested_days,reason,workflow_id,submitted_by) values(emp.organization_id,p_employee_id,p_leave_code,p_starts_on,p_ends_on,p_requested_days,p_reason,flow.id,auth.uid()) returning id into req_id;
 insert into public.employee_leave_approvals(request_id,step_order,approver_role_code,specific_employee_id,status) select req_id,step_order,approver_role_code,specific_employee_id,case when step_order=(select min(step_order) from public.leave_approval_workflow_steps where workflow_id=flow.id) then 'pending' else 'waiting' end from public.leave_approval_workflow_steps where workflow_id=flow.id order by step_order;
 select min(step_order) into first_step from public.leave_approval_workflow_steps where workflow_id=flow.id;update public.employee_leave_requests set current_step=first_step where id=req_id;return req_id;
end $$;

create or replace function public.hr_decide_leave_request(p_request_id uuid,p_decision text,p_remarks text default null)
returns void language plpgsql security definer set search_path=public as $$
declare req public.employee_leave_requests; current_approval public.employee_leave_approvals; next_step integer;
begin
 if not public.is_hr_staff() or p_decision not in('approved','rejected') then raise exception 'Invalid leave decision';end if;
 select * into req from public.employee_leave_requests where id=p_request_id and organization_id=public.current_organization_id() and status='pending';if req.id is null then raise exception 'Pending request not found';end if;
 select * into current_approval from public.employee_leave_approvals where request_id=req.id and step_order=req.current_step and status='pending';if current_approval.id is null then raise exception 'Current approval step not found';end if;
 update public.employee_leave_approvals set status=p_decision,acted_by=auth.uid(),acted_at=now(),remarks=p_remarks where id=current_approval.id;
 if p_decision='rejected' then update public.employee_leave_requests set status='rejected',updated_at=now() where id=req.id;return;end if;
 select min(step_order) into next_step from public.employee_leave_approvals where request_id=req.id and step_order>req.current_step and status='waiting';
 if next_step is null then update public.employee_leave_requests set status='approved',updated_at=now() where id=req.id;insert into public.employee_leave_ledger(organization_id,employee_id,leave_code,amount,entry_type,request_id,notes,created_by) values(req.organization_id,req.employee_id,req.leave_code,-req.requested_days,'approved_leave',req.id,'Approved leave request',auth.uid());
 else update public.employee_leave_approvals set status='pending' where request_id=req.id and step_order=next_step;update public.employee_leave_requests set current_step=next_step,updated_at=now() where id=req.id;end if;
end $$;
revoke all on function public.hr_submit_leave_request(uuid,text,date,date,numeric,text) from public;grant execute on function public.hr_submit_leave_request(uuid,text,date,date,numeric,text) to authenticated;
revoke all on function public.hr_decide_leave_request(uuid,text,text) from public;grant execute on function public.hr_decide_leave_request(uuid,text,text) to authenticated;
