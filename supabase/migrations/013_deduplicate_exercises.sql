-- =============================================================================
-- Migration 013: deduplicate built-in exercises.
--
-- Multiple import rounds left duplicate rows sharing the same name +
-- equipment. For each duplicate group, the row with an exercise-images
-- storage URL is the "keeper". Session_sets and plan_exercises that
-- reference the old (image-less) row are re-pointed to the keeper before
-- the old row is deleted.
--
-- Idempotent: the CTE only finds groups with more than one member, and
-- the final DELETE only hits rows that still exist.
-- =============================================================================

-- Step 1: re-point session_sets from old duplicates to the keeper.
with keepers as (
  select
    name,
    coalesce(equipment, '') as eq,
    -- Prefer the row whose image_url points at our bucket; break ties by id.
    (array_agg(id order by
      case when image_url like '%/storage/v1/object/public/exercise-images/%' then 0 else 1 end,
      id
    ))[1] as keeper_id
  from public.exercises
  where is_built_in = true
  group by name, coalesce(equipment, '')
  having count(*) > 1
),
old_rows as (
  select e.id as old_id, k.keeper_id
  from public.exercises e
  join keepers k
    on e.name = k.name
    and coalesce(e.equipment, '') = k.eq
  where e.is_built_in = true
    and e.id <> k.keeper_id
)
update public.session_sets ss
set exercise_id = o.keeper_id
from old_rows o
where ss.exercise_id = o.old_id;

-- Step 2: re-point plan_exercises the same way.
with keepers as (
  select
    name,
    coalesce(equipment, '') as eq,
    (array_agg(id order by
      case when image_url like '%/storage/v1/object/public/exercise-images/%' then 0 else 1 end,
      id
    ))[1] as keeper_id
  from public.exercises
  where is_built_in = true
  group by name, coalesce(equipment, '')
  having count(*) > 1
),
old_rows as (
  select e.id as old_id, k.keeper_id
  from public.exercises e
  join keepers k
    on e.name = k.name
    and coalesce(e.equipment, '') = k.eq
  where e.is_built_in = true
    and e.id <> k.keeper_id
)
update public.plan_exercises pe
set exercise_id = o.keeper_id
from old_rows o
where pe.exercise_id = o.old_id;

-- Step 3: delete the old duplicates (now unreferenced).
with keepers as (
  select
    name,
    coalesce(equipment, '') as eq,
    (array_agg(id order by
      case when image_url like '%/storage/v1/object/public/exercise-images/%' then 0 else 1 end,
      id
    ))[1] as keeper_id
  from public.exercises
  where is_built_in = true
  group by name, coalesce(equipment, '')
  having count(*) > 1
)
delete from public.exercises e
using keepers k
where e.name = k.name
  and coalesce(e.equipment, '') = k.eq
  and e.is_built_in = true
  and e.id <> k.keeper_id;
