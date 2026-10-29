-- Endurance v1. Apply before distributing the new client. Routes are private.
begin;

create table public.endurance_activities (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    details jsonb not null,
    constraint endurance_activity_shape check (
        jsonb_typeof(details) = 'object'
        and details ?& array['id', 'userId', 'sport', 'source', 'title', 'startedAt', 'endedAt', 'activeSeconds', 'distanceMeters', 'route']
        and details->>'id' = id::text
        and details->>'userId' = user_id::text
        and details->>'sport' in ('run', 'walk', 'cycle')
        and details->>'source' in ('shift', 'healthkit')
        and jsonb_typeof(details->'route') = 'array'
        and jsonb_typeof(details->'activeSeconds') = 'number'
        and jsonb_typeof(details->'distanceMeters') = 'number'
        and (details->>'activeSeconds')::numeric > 0
        and (details->>'distanceMeters')::numeric >= 0
    )
);
create index endurance_activities_owner on public.endurance_activities(user_id);
create unique index endurance_healthkit_unique
    on public.endurance_activities(user_id, (details->>'healthKitID'))
    where details->>'healthKitID' is not null;

create table public.endurance_goals (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    details jsonb not null,
    constraint endurance_goal_shape check (
        jsonb_typeof(details) = 'object'
        and details ?& array['id', 'userId', 'metric', 'period', 'target', 'createdAt']
        and details->>'id' = id::text
        and details->>'userId' = user_id::text
        and details->>'metric' in ('distance', 'duration', 'activities')
        and details->>'period' in ('week', 'month', 'deadline')
        and (details->>'target')::numeric > 0
        and jsonb_typeof(details->'target') = 'number'
    )
);
create index endurance_goals_owner on public.endurance_goals(user_id);

alter table public.endurance_activities enable row level security;
alter table public.endurance_goals enable row level security;
revoke all on public.endurance_activities, public.endurance_goals from public, anon;
grant select, insert, update, delete on public.endurance_activities, public.endurance_goals to authenticated;
create policy "endurance activities owner" on public.endurance_activities
    for all to authenticated using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
create policy "endurance goals owner" on public.endurance_goals
    for all to authenticated using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

commit;
