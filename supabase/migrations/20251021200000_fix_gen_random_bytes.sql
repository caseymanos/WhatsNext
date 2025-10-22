-- Fix gen_random_bytes function call to include schema prefix
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, username, created_at, status)
  values (new.id, new.email, coalesce(split_part(new.email, '@', 1), encode(extensions.gen_random_bytes(6),'hex')), now(), 'online')
  on conflict (id) do nothing;
  return new;
end;
$$;
