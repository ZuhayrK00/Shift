-- Private progress photos and a reproducible, server-side account deletion path.
-- This migration is intentionally idempotent so it can also repair a project
-- whose dashboard was changed manually before the migration was added.

begin;

update storage.buckets
set public = false
where id = 'progress-photos';

drop policy if exists "progress_photos_public_read" on storage.objects;
drop policy if exists "progress_photos_user_read" on storage.objects;
create policy "progress_photos_user_read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'progress-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "progress_photos_user_write" on storage.objects;
create policy "progress_photos_user_write"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'progress-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "progress_photos_user_update" on storage.objects;
create policy "progress_photos_user_update"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'progress-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    with check (
        bucket_id = 'progress-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "progress_photos_user_delete" on storage.objects;
create policy "progress_photos_user_delete"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'progress-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

-- New clients persist an object path instead of a permanent URL. Convert old
-- public and signed URL records without changing the storage object itself.
update public.progress_photos
set image_url = split_part(
    regexp_replace(
        image_url,
        '^https?://[^/]+/storage/v1/object/(public|sign)/progress-photos/',
        ''
    ),
    '?',
    1
)
where image_url ~ '^https?://[^/]+/storage/v1/object/(public|sign)/progress-photos/';

-- Enforce the published minimum age for all new or changed profile rows while
-- preserving any legacy row for support review instead of deleting it.
alter table public.profiles
drop constraint if exists profiles_age_check;
alter table public.profiles
drop constraint if exists profiles_age_eligible_check;
alter table public.profiles
add constraint profiles_age_eligible_check
check (age is null or age between 13 and 120);

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    request_user_id uuid := auth.uid();
begin
    if request_user_id is null then
        raise exception 'Authentication required';
    end if;

    -- Storage does not reference auth.users, so remove owned objects explicitly.
    delete from storage.objects
    where bucket_id in ('progress-photos', 'avatars')
      and (storage.foldername(name))[1] = request_user_id::text;

    -- Remove dependent content in a deterministic order. Most of these rows
    -- also cascade from auth.users; explicit deletion keeps custom exercises
    -- removable before their created_by foreign key would be set to null.
    delete from public.session_sets
    where session_id in (
        select id from public.workout_sessions where user_id = request_user_id
    );
    delete from public.workout_sessions where user_id = request_user_id;

    delete from public.plan_exercises
    where plan_id in (
        select id from public.workout_plans where user_id = request_user_id
    );
    delete from public.workout_plans where user_id = request_user_id;

    delete from public.exercise_goals where user_id = request_user_id;
    delete from public.weight_entries where user_id = request_user_id;
    delete from public.body_measurements where user_id = request_user_id;
    delete from public.progress_photos where user_id = request_user_id;
    delete from public.exercises where created_by = request_user_id;
    delete from public.profiles where id = request_user_id;
    delete from auth.users where id = request_user_id;
end;
$$;

revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;

commit;
