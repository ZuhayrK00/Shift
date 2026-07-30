-- Resolve the actionable production Security Advisor warnings while preserving
-- the intentionally authenticated account-deletion RPC.

begin;

-- Trigger helpers should never resolve objects through a caller-controlled
-- search path.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id)
    values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

-- The trigger invokes this function internally; clients must not be able to
-- call the SECURITY DEFINER function through the exposed API.
revoke all on function public.handle_new_user() from public;
revoke all on function public.handle_new_user() from anon;
revoke all on function public.handle_new_user() from authenticated;
grant execute on function public.handle_new_user() to postgres;
grant execute on function public.handle_new_user() to supabase_auth_admin;

-- Avatar files contain personal information. Persist private object paths and
-- allow each authenticated account to access only its own folder.
update storage.buckets
set public = false
where id = 'avatars';

drop policy if exists "avatars_public_read" on storage.objects;
drop policy if exists "avatars_user_read" on storage.objects;
create policy "avatars_user_read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "avatars_user_write" on storage.objects;
create policy "avatars_user_write"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "avatars_user_update" on storage.objects;
create policy "avatars_user_update"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "avatars_user_delete" on storage.objects;
create policy "avatars_user_delete"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

-- Convert existing database values without moving the underlying files. New
-- clients generate a short-lived signed URL only when displaying an avatar.
update public.profiles
set profile_picture_url = split_part(
    regexp_replace(
        profile_picture_url,
        '^https?://[^/]+/storage/v1/object/(public|sign)/avatars/',
        ''
    ),
    '?',
    1
)
where profile_picture_url ~ '^https?://[^/]+/storage/v1/object/(public|sign)/avatars/';

commit;
