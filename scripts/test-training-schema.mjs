// Disposable, in-memory PostgreSQL verification only. Never connects to a server.
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
const db = new PGlite();
try {
  await db.exec(`
    create role anon nologin; create role authenticated nologin;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated;
    insert into auth.users values ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
  `);
  await db.exec(await readFile(new URL('../supabase/migrations/028_endurance_training.sql', import.meta.url), 'utf8'));
  await db.exec(`
    insert into public.training_sessions
    select id, owner, jsonb_build_object('id',id,'userId',owner,'title','Easy run','kind','endurance','sport','run','status','scheduled','scheduledAt','2026-10-30T09:00:00Z')
    from (values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,'11111111-1111-4111-8111-111111111111'::uuid),
                 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,'22222222-2222-4222-8222-222222222222'::uuid)) as t(id,owner);
    insert into public.endurance_routes
    select id, owner, jsonb_build_object('id',id,'userId',owner,'title','Loop','sport','walk','distanceMeters',1000,
      'sourceActivityID',id,'createdAt','2026-10-24T12:00:00Z','points','[{"latitude":51.5,"longitude":0},{"latitude":51.51,"longitude":0}]'::jsonb)
    from (values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid,'11111111-1111-4111-8111-111111111111'::uuid),
                 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid,'22222222-2222-4222-8222-222222222222'::uuid)) as t(id,owner);
    set role authenticated; set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
    do $$ declare affected integer; begin
      if (select count(*) from public.training_sessions) != 1 or (select count(*) from public.endurance_routes) != 1 then raise exception 'Cross-account reads permitted'; end if;
      update public.training_sessions set details = details || '{"title":"Other account"}' where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      get diagnostics affected = row_count; if affected != 0 then raise exception 'Cross-account update permitted'; end if;
      delete from public.endurance_routes where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
      get diagnostics affected = row_count; if affected != 0 then raise exception 'Cross-account route deletion permitted'; end if;
      begin
        insert into public.training_sessions select 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid, '22222222-2222-4222-8222-222222222222'::uuid,
          jsonb_build_object('id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','userId','22222222-2222-4222-8222-222222222222','title','Spoof','kind','strength','status','scheduled','scheduledAt','2026-10-30T09:00:00Z');
        raise exception 'Cross-account insert permitted';
      exception when insufficient_privilege then null; end;
      begin
        update public.training_sessions set details = details || '{"targetSeconds":-1}' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        raise exception 'Negative target permitted';
      exception when check_violation then null; end;
      begin
        update public.training_sessions set details = details || '{"kind":null}' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        raise exception 'Null training kind permitted';
      exception when check_violation then null; end;
      begin
        update public.endurance_routes set details = details || '{"points":[]}' where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
        raise exception 'Empty saved route permitted';
      exception when check_violation then null; end;
    end $$;
    reset role;
    do $$ begin
      if has_table_privilege('anon','public.training_sessions','SELECT') or has_table_privilege('anon','public.endurance_routes','SELECT') then raise exception 'Anonymous data exposed'; end if;
    end $$;
    delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
    do $$ begin
      if (select count(*) from public.training_sessions) != 1 or (select count(*) from public.endurance_routes) != 1 then raise exception 'Account cascade or isolation failed'; end if;
    end $$;
  `);
  console.log('Training calendar and saved routes: schema, owner RLS, validation, anonymous denial and account deletion passed.');
} finally { await db.close(); }
