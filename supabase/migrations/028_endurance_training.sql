-- Private cross-device calendar and saved routes. Apply before client build 20.
begin;
create table public.training_sessions (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 details jsonb not null,
 constraint training_session_shape check (
  jsonb_typeof(details) = 'object' and details ?& array['id','userId','title','scheduledAt','kind','status']
  and details->>'id' = id::text and details->>'userId' = user_id::text
  and jsonb_typeof(details->'id') = 'string' and jsonb_typeof(details->'userId') = 'string'
  and jsonb_typeof(details->'title') = 'string' and jsonb_typeof(details->'kind') = 'string' and jsonb_typeof(details->'status') = 'string'
  and jsonb_typeof(details->'scheduledAt') = 'string' and (details->>'scheduledAt')::timestamptz is not null
  and details->>'kind' in ('strength','endurance') and details->>'status' in ('scheduled','skipped')
  and length(trim(details->>'title')) > 0
  and (details->>'kind' = 'strength' or details->>'sport' in ('run','walk','cycle'))
  and (not(details ? 'targetMeters') or (jsonb_typeof(details->'targetMeters') = 'number' and (details->>'targetMeters')::numeric > 0))
  and (not(details ? 'targetSeconds') or (jsonb_typeof(details->'targetSeconds') = 'number' and (details->>'targetSeconds')::numeric > 0))
 )
);
create table public.endurance_routes (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 details jsonb not null,
 constraint endurance_route_shape check (
  jsonb_typeof(details) = 'object' and details ?& array['id','userId','title','sport','points','distanceMeters','sourceActivityID','createdAt']
  and details->>'id' = id::text and details->>'userId' = user_id::text
  and jsonb_typeof(details->'id') = 'string' and jsonb_typeof(details->'userId') = 'string'
  and jsonb_typeof(details->'title') = 'string' and jsonb_typeof(details->'sport') = 'string'
  and jsonb_typeof(details->'createdAt') = 'string' and (details->>'createdAt')::timestamptz is not null
  and jsonb_typeof(details->'distanceMeters') = 'number'
  and details->>'sport' in ('run','walk','cycle') and length(trim(details->>'title')) > 0
  and jsonb_typeof(details->'points') = 'array' and jsonb_array_length(details->'points') >= 2
  and (details->>'distanceMeters')::numeric > 0
 )
);
create index training_sessions_owner on public.training_sessions(user_id);
create index endurance_routes_owner on public.endurance_routes(user_id);
alter table public.training_sessions enable row level security;
alter table public.endurance_routes enable row level security;
revoke all on public.training_sessions, public.endurance_routes from public, anon;
grant select, insert, update, delete on public.training_sessions, public.endurance_routes to authenticated;
create policy "training sessions owner" on public.training_sessions for all to authenticated
 using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "saved routes owner" on public.endurance_routes for all to authenticated
 using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
commit;
