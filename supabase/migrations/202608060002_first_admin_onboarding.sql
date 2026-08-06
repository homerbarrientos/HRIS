create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_organization_id uuid;
begin
  insert into public.organizations (name)
  values (coalesce(nullif(new.raw_user_meta_data->>'company_name', ''), 'My Company'))
  returning id into new_organization_id;

  insert into public.profiles (id, organization_id, employee_number, full_name, role)
  values (
    new.id,
    new_organization_id,
    'ADMIN-001',
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(new.email, '@', 1)),
    'admin'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
