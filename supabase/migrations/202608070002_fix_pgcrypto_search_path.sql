-- Supabase installs pgcrypto helpers in the extensions schema.
-- Add that schema to the three kiosk functions that call crypt/gen_salt.
alter function public.admin_create_employee(text, text, text, boolean, boolean, boolean)
  set search_path = public, extensions;

alter function public.admin_create_kiosk(text)
  set search_path = public, extensions;

alter function public.kiosk_clock(text, text, text, text, double precision, double precision)
  set search_path = public, extensions;
