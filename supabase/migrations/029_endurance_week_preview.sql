-- One saved generated week per account. The receipt survives plan deletion and reinstall.
begin;
create table public.endurance_week_previews (
 user_id uuid primary key references auth.users(id) on delete cascade,
 program_id uuid not null,
 session_ids uuid[] not null check (cardinality(session_ids) between 1 and 7),
 created_at timestamptz not null default now()
);
alter table public.endurance_week_previews enable row level security;
revoke all on public.endurance_week_previews from public, anon, authenticated;
grant select on public.endurance_week_previews to authenticated;
create policy "read own endurance preview" on public.endurance_week_previews for select to authenticated
 using ((select auth.uid()) = user_id);

create function public.save_endurance_week_preview(p_program_id uuid, p_sessions jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 owner_id uuid := auth.uid();
 receipt public.endurance_week_previews;
 item jsonb;
 ids uuid[] := '{}';
 first_time timestamptz;
 last_time timestamptz;
begin
 if owner_id is null then raise exception 'Sign in to save a free week' using errcode = '42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('shift.endurance.preview.' || owner_id::text, 0));
 select * into receipt from public.endurance_week_previews where user_id = owner_id;
 if receipt.user_id is null then
  if p_program_id is null or jsonb_typeof(p_sessions) is distinct from 'array'
    or jsonb_array_length(p_sessions) not between 1 and 7 then
   raise exception 'Choose one to seven valid sessions' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(p_sessions) loop
   if jsonb_typeof(item) is distinct from 'object' or not (item ?& array['id','userId','programID','scheduledAt','kind','sport','status','title','targetSeconds'])
     or item->>'userId' is distinct from owner_id::text or item->>'programID' is distinct from p_program_id::text
     or item->>'kind' is distinct from 'endurance' or item->>'status' is distinct from 'scheduled'
     or item->>'sport' not in ('run','walk','cycle') or length(trim(item->>'title')) = 0
     or jsonb_typeof(item->'targetSeconds') is distinct from 'number'
     or (item->>'targetSeconds')::numeric not between 300 and 10800
     or (item->>'scheduledAt')::timestamptz <= now() then
    raise exception 'Invalid preview session' using errcode = '22023';
   end if;
   if (item->>'id')::uuid = any(ids) then raise exception 'Duplicate preview session' using errcode = '22023'; end if;
   ids := array_append(ids, (item->>'id')::uuid);
   first_time := least(first_time, (item->>'scheduledAt')::timestamptz);
   last_time := greatest(last_time, (item->>'scheduledAt')::timestamptz);
  end loop;
  if last_time - first_time >= interval '7 days' then raise exception 'Preview must cover one week' using errcode = '22023'; end if;
  -- Plain inserts: a colliding ID fails the entire transaction, including the receipt.
  insert into public.training_sessions(id,user_id,details)
   select (value->>'id')::uuid,owner_id,value from jsonb_array_elements(p_sessions);
  insert into public.endurance_week_previews(user_id,program_id,session_ids)
   values (owner_id,p_program_id,ids) returning * into receipt;
 end if;
 -- Retries return current rows, not an old snapshot that could resurrect deletions/edits.
 return jsonb_build_object('receipt',to_jsonb(receipt),'sessions',coalesce((
  select jsonb_agg(s.details order by s.details->>'scheduledAt') from public.training_sessions s
  where s.user_id = owner_id and s.id = any(receipt.session_ids)
 ),'[]'::jsonb));
end;
$$;
revoke all on function public.save_endurance_week_preview(uuid,jsonb) from public, anon;
grant execute on function public.save_endurance_week_preview(uuid,jsonb) to authenticated;
commit;
