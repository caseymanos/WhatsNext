-- Fix RLS recursion and enable user search

-- 1) Helper function to check membership without RLS recursion
create or replace function public.is_conversation_member(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id = p_user_id
  );
$$;

revoke all on function public.is_conversation_member(uuid, uuid) from public;
grant execute on function public.is_conversation_member(uuid, uuid) to authenticated, service_role, anon;

-- 2) Rewrite conversation_participants policies
drop policy if exists conv_part_select_member on public.conversation_participants;
create policy conv_part_select_member on public.conversation_participants
  for select using (
    public.is_conversation_member(conversation_participants.conversation_id, auth.uid())
  );

drop policy if exists conv_part_insert_by_member on public.conversation_participants;
create policy conv_part_insert_by_member on public.conversation_participants
  for insert with check (
    public.is_conversation_member(conversation_participants.conversation_id, auth.uid())
    or auth.uid() = user_id
  );

drop policy if exists conv_part_update_member on public.conversation_participants;
create policy conv_part_update_member on public.conversation_participants
  for update using (
    public.is_conversation_member(conversation_participants.conversation_id, auth.uid())
  );

drop policy if exists conv_part_delete_member on public.conversation_participants;
create policy conv_part_delete_member on public.conversation_participants
  for delete using (
    public.is_conversation_member(conversation_participants.conversation_id, auth.uid())
  );

-- 3) Update conversations and messages policies to use helper
drop policy if exists conv_select_member on public.conversations;
create policy conv_select_member on public.conversations
  for select using (
    public.is_conversation_member(id, auth.uid())
  );

drop policy if exists msg_select_member on public.messages;
create policy msg_select_member on public.messages
  for select using (
    public.is_conversation_member(conversation_id, auth.uid())
  );

drop policy if exists msg_insert_member_sender on public.messages;
create policy msg_insert_member_sender on public.messages
  for insert with check (
    public.is_conversation_member(conversation_id, auth.uid())
    and sender_id = auth.uid()
  );

-- 4) Ensure user profiles exist (auto-create on new auth.user)
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, username, created_at, status)
  values (
    new.id,
    new.email,
    coalesce(
      split_part(new.email, '@', 1) || '_' || substring(encode(extensions.gen_random_bytes(3),'hex'), 1, 6),
      encode(extensions.gen_random_bytes(6),'hex')
    ),
    now(),
    'online'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- 5) Indexes to accelerate case-insensitive user search
create index if not exists idx_users_username_ci on public.users (lower(username));
create index if not exists idx_users_display_name_ci on public.users (lower(display_name));
create index if not exists idx_users_email_ci on public.users (lower(email));


