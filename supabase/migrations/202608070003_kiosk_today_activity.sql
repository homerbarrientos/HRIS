create or replace function public.kiosk_today_activity(p_kiosk_token text)
returns table (employee_name text, event_type public.attendance_event_type, occurred_at timestamptz, location_flagged boolean)
language plpgsql security definer set search_path = public, extensions
as $$
declare device public.kiosk_devices;
begin
  select * into device from public.kiosk_devices
  where active and token_hash = crypt(p_kiosk_token, token_hash) limit 1;
  if device.id is null then raise exception 'Kiosk is not authorized'; end if;
  return query
    select split_part(e.full_name, ' ', 1) || ' ' || left(split_part(e.full_name, ' ', -1), 1) || '.',
           a.event_type, a.occurred_at, a.location_unavailable
    from public.kiosk_attendance_events a
    join public.employees e on e.id = a.employee_id
    where a.organization_id = device.organization_id
      and (a.occurred_at at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date
    order by a.occurred_at desc
    limit 250;
end;
$$;

revoke all on function public.kiosk_today_activity(text) from public;
grant execute on function public.kiosk_today_activity(text) to anon, authenticated;
