-- Resolve production Performance Advisor warnings without weakening RLS.
-- 1. Remove duplicate permissive policies left by the original schema plus
--    later idempotent migrations.
-- 2. Cache auth helper results once per statement instead of once per row.
-- 3. Index ownership and foreign-key columns used by sync and cascade checks.

begin;

-- Duplicate policies with equivalent ownership checks.
drop policy if exists "Users can manage exercises in their own plans"
    on public.plan_exercises;
drop policy if exists "Users can manage their own plans"
    on public.workout_plans;
drop policy if exists "profiles_select_own"
    on public.profiles;
drop policy if exists "profiles_update_own"
    on public.profiles;

-- Convert raw auth.uid()/auth.role() calls in every remaining public policy to
-- scalar subqueries. PostgreSQL can evaluate these once as init plans rather
-- than recalculating them for every candidate row.
do $$
declare
    policy_row record;
    statement text;
    optimized_using text;
    optimized_check text;
begin
    for policy_row in
        select schemaname, tablename, policyname, qual, with_check
        from pg_policies
        where schemaname = 'public'
          and (
              coalesce(qual, '') like '%auth.uid()%'
              or coalesce(qual, '') like '%auth.role()%'
              or coalesce(with_check, '') like '%auth.uid()%'
              or coalesce(with_check, '') like '%auth.role()%'
          )
    loop
        optimized_using := replace(
            replace(policy_row.qual, 'auth.uid()', '(select auth.uid())'),
            'auth.role()', '(select auth.role())'
        );
        optimized_check := replace(
            replace(policy_row.with_check, 'auth.uid()', '(select auth.uid())'),
            'auth.role()', '(select auth.role())'
        );

        statement := format(
            'alter policy %I on %I.%I',
            policy_row.policyname,
            policy_row.schemaname,
            policy_row.tablename
        );

        if optimized_using is not null then
            statement := statement || ' using (' || optimized_using || ')';
        end if;
        if optimized_check is not null then
            statement := statement || ' with check (' || optimized_check || ')';
        end if;

        execute statement;
    end loop;
end;
$$;

create index if not exists idx_exercises_created_by
    on public.exercises (created_by);
create index if not exists idx_workout_plans_user_id
    on public.workout_plans (user_id);
create index if not exists idx_plan_exercises_exercise_id
    on public.plan_exercises (exercise_id);
create index if not exists idx_workout_sessions_plan_id
    on public.workout_sessions (plan_id);
create index if not exists idx_session_sets_exercise_id
    on public.session_sets (exercise_id);
create index if not exists idx_exercise_goals_user_id
    on public.exercise_goals (user_id);
create index if not exists idx_exercise_goals_exercise_id
    on public.exercise_goals (exercise_id);

commit;
