-- Local integration test only. Never point this at a Supabase project.
\set ON_ERROR_STOP on
do $$ begin
    if current_database() not like 'shift_endurance_test_%' then
        raise exception 'Run only in a disposable shift_endurance_test_* database';
    end if;
end $$;

create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated;

\ir ../supabase/migrations/027_endurance.sql

insert into auth.users values
    ('11111111-1111-4111-8111-111111111111'),
    ('22222222-2222-4222-8222-222222222222');
insert into public.endurance_activities (id, user_id, details)
select activity_id, owner_id,
    jsonb_build_object('id', activity_id, 'userId', owner_id, 'sport', 'run', 'source', 'shift',
        'title', 'Test run', 'startedAt', '2026-10-24T10:00:00Z', 'endedAt', '2026-10-24T10:30:00Z',
        'activeSeconds', 1800, 'distanceMeters', 5000, 'route', '[]'::jsonb)
from (values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, '11111111-1111-4111-8111-111111111111'::uuid),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid, '22222222-2222-4222-8222-222222222222'::uuid)
) as test_data(activity_id, owner_id);
insert into public.endurance_goals values (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', '22222222-2222-4222-8222-222222222222',
    jsonb_build_object('id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'userId','22222222-2222-4222-8222-222222222222',
        'metric','distance','period','week','target',10000,'createdAt','2026-10-24T10:00:00Z')
);

set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
do $$
declare affected integer;
begin
    if (select count(*) from public.endurance_activities) != 1 then
        raise exception 'RLS exposed another account';
    end if;
    if (select count(*) from public.endurance_goals) != 0 then
        raise exception 'Goal RLS exposed another account';
    end if;
    update public.endurance_goals set details = details || '{"target":1}'
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    get diagnostics affected = row_count;
    if affected != 0 then raise exception 'Cross-account goal update succeeded'; end if;
    update public.endurance_activities set details = details || '{"title":"Wrong account"}'
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    get diagnostics affected = row_count;
    if affected != 0 then raise exception 'Cross-account update succeeded'; end if;
    delete from public.endurance_activities where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    get diagnostics affected = row_count;
    if affected != 0 then raise exception 'Cross-account delete succeeded'; end if;

    begin
        insert into public.endurance_activities
        select 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', '22222222-2222-4222-8222-222222222222',
            details || '{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","userId":"22222222-2222-4222-8222-222222222222"}'
        from public.endurance_activities limit 1;
        raise exception 'Cross-account insert succeeded';
    exception when insufficient_privilege then null;
    end;

    begin
        insert into public.endurance_activities
        select 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', auth.uid(),
            (details - 'sport') || '{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}'
        from public.endurance_activities limit 1;
        raise exception 'Malformed route record accepted';
    exception when check_violation then null;
    end;

    update public.endurance_activities
        set details = details || '{"healthKitID":"ffffffff-ffff-4fff-8fff-ffffffffffff"}';
    begin
        insert into public.endurance_activities
        select 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', auth.uid(),
            details || '{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}'
        from public.endurance_activities limit 1;
        raise exception 'Duplicate HealthKit workout accepted';
    exception when unique_violation then null;
    end;

    begin
        insert into public.endurance_goals values (
            'dddddddd-dddd-4ddd-8ddd-dddddddddddd', auth.uid(),
            jsonb_build_object('id','dddddddd-dddd-4ddd-8ddd-dddddddddddd','userId',auth.uid(),
                'metric','distance','period','week','target',0,'createdAt','2026-10-24T10:00:00Z')
        );
        raise exception 'Invalid goal target accepted';
    exception when check_violation then null;
    end;

    insert into public.endurance_goals values (
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd', auth.uid(),
        jsonb_build_object('id','dddddddd-dddd-4ddd-8ddd-dddddddddddd','userId',auth.uid(),
            'metric','distance','period','week','target',20000,'createdAt','2026-10-24T10:00:00Z')
    );
end $$;
reset role;

do $$ begin
    if has_table_privilege('anon', 'public.endurance_activities', 'SELECT')
        or has_table_privilege('anon', 'public.endurance_goals', 'SELECT') then
        raise exception 'Anonymous route or goal access is permitted';
    end if;
end $$;

delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
do $$ begin
    if (select count(*) from public.endurance_activities) != 1
        or (select count(*) from public.endurance_goals) != 1 then
        raise exception 'Account deletion did not cascade safely';
    end if;
end $$;
select 'Endurance schema, RLS, validation and deletion tests passed' as result;
