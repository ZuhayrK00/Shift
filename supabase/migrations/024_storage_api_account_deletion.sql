-- Supabase Storage objects must be removed through the Storage API. Direct
-- DELETE statements against storage.objects are rejected by the platform.
-- The authenticated client removes its private files before calling this RPC;
-- this function then removes relational data and the Auth account atomically.

begin;

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

    -- Fail closed for older app versions that call this RPC without first
    -- removing files through the Storage API. Selecting storage metadata is
    -- supported; only direct mutation of storage.objects is forbidden.
    if exists (
        select 1
        from storage.objects
        where bucket_id in ('progress-photos', 'avatars')
          and (storage.foldername(name))[1] = request_user_id::text
    ) then
        raise exception 'Owned files must be deleted through the Storage API before deleting the account';
    end if;

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
