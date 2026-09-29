// Preparation only. Writes local, ignored SQL/files, never production. Secrets are never logged.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const root = new URL('../', import.meta.url);
const key = readFileSync(new URL('Shift/Helpers/SupabaseClient.swift', root), 'utf8').match(/supabaseKey: "([^"]+)"/)[1];
const password = execFileSync('security', ['find-generic-password','-s','ShiftLaunchReviewAccount','-a','shift-review-20260929@shiftfitness.pro','-w'], {encoding:'utf8'}).trim();
const base = 'https://dtzlfvuazdrgyyutjysm.supabase.co';
async function json(url, options = {}) {
  const response = await fetch(url, options);
  if (!response.ok) throw new Error(`HTTP ${response.status} for ${new URL(url).pathname}`);
  return response.json();
}
const auth = await json(`${base}/auth/v1/token?grant_type=password`, {method:'POST', headers:{apikey:key,'Content-Type':'application/json'}, body:JSON.stringify({email:'shift-review-20260929@shiftfitness.pro',password})});
async function rows(table) {
  let result=[];
  for(let offset=0;;offset+=500) {
    const page=await json(`${base}/rest/v1/${table}?select=*&order=id&offset=${offset}&limit=500`, {headers:{apikey:key,Authorization:`Bearer ${auth.access_token}`}});
    result.push(...page); if(page.length<500) return result;
  }
}
const revision = await json('https://api.github.com/repos/RepDB/exercise-dataset/commits/main');
const source = `https://raw.githubusercontent.com/RepDB/exercise-dataset/${revision.sha}`;
const [old,muscles,data] = await Promise.all([rows('exercises'),rows('muscle_groups'),json(`${source}/exercises.json`)]);
if (old.some(e=>e.catalogue_source==='repdb')) throw new Error('Already migrated: refusing to prepare a second destructive import');
if(data.count!==data.exercises.length || data.count<500) throw new Error('Unexpected RepDB snapshot');
const folder = new URL('../migration-preparation/repdb/', import.meta.url);
mkdirSync(folder,{recursive:true});
const muscleSlugs = {rectus_abdominis:'abs',transverse_abdominis:'abs',obliques:'abs',latissimus_dorsi:'back',rhomboids:'back',erector_spinae:'back',quadratus_lumborum:'back',pectoralis_major:'chest',anterior_deltoid:'shoulders',lateral_deltoid:'shoulders',posterior_deltoid:'shoulders',biceps_brachii:'biceps',brachialis:'biceps',triceps_brachii:'triceps',forearm_flexors:'forearms',forearm_extensors:'forearms',brachioradialis:'forearms',trapezius:'traps',gluteus_maximus:'glutes',gluteus_medius:'glutes',gastrocnemius:'calves',soleus:'calves',hip_flexors:'quadriceps'};
function muscleId(name) {
  const slug=({serratus_anterior:'chest',rotator_cuff:'shoulders',iliopsoas:'core',sternocleidomastoid:'neck',scalenes:'neck',teres_major:'back',teres_minor:'shoulders',infraspinatus:'shoulders',supraspinatus:'shoulders',tibialis_anterior:'calves',tensor_fasciae_latae:'abductors',multifidus:'lower-back'}[name])??muscleSlugs[name]??name;
  const match=muscles.find(m=>m.slug===slug) ?? muscles.find(m=>m.slug===({abs:'abdominals',back:'lats',quadriceps:'quads'}[slug]));
  if(!match) throw new Error(`Unmapped muscle ${name} (${slug}), available: ${muscles.map(m=>m.slug).join(',')}`);
  return match.id;
}
function uuid(slug) { const s=createHash('sha256').update(`shift:repdb:v1:${slug}`).digest('hex').slice(0,32); return `${s.slice(0,8)}-${s.slice(8,12)}-5${s.slice(13,16)}-a${s.slice(17,20)}-${s.slice(20)}`; }
const normalize = s=>s.toLowerCase().replace(/pullups?/g,'pull up').replace(/pushups?/g,'push up').replace(/chinups?/g,'chin up').replace(/[^a-z0-9 ]/g,' ').replace(/\s+/g,' ').trim();
const signature = s=>normalize(s).replace(/triceps/g,'tricep').replace(/biceps/g,'bicep').split(' ').filter(t=>!['with','the','on','a'].includes(t)).sort().join(' ');
const explicit = {'barbell squat':'squat','barbell front squat':'front-squat','barbell romanian deadlift':'romanian-deadlift','dumbbell incline bench press':'incline-db-press','dumbbell rear lunge':'reverse-lunge','cable seated row':'seated-cable-row','chest dip':'dips','cable pushdown':'tricep-pushdown','cable triceps pushdown':'tricep-pushdown',
 'cable triceps pushdown v bar':'v-bar-tricep-pushdown', 'lever seated leg curl':'seated-leg-curl',
 'sled 45 leg press':'leg-press', 'barbell bent over row':'barbell-row',
 'barbell lying triceps extension':'skull-crusher', 'dumbbell decline bench press':'decline-bench-press',
 'dumbbell bench press':'db-bench-press', 'dumbbell fly':'db-fly', 'lever leg extension':'leg-extension',
 'lever lying leg curl':'leg-curl', 'trap bar deadlift':'hex-bar-deadlift',
 'barbell front chest squat':'front-squat', 'barbell full squat back pov':'squat'};
const canonical = data.exercises.map(e=>({id:uuid(e.id),name:e.name_en,slug:e.id,instructions:null,primary_muscle_id:muscleId(e.primary_muscles[0]),secondary_muscle_ids:[...new Set([...e.primary_muscles.slice(1),...(e.secondary_muscles??[])].map(muscleId))].filter(x=>x!==muscleId(e.primary_muscles[0])),equipment:(e.equipment??'bodyweight').replaceAll('_',' '),is_built_in:true,created_by:null,image_url:`https://raw.githubusercontent.com/RepDB/exercise-dataset/main/${e.images.flat.start??e.images.flat.main}`,secondary_image_url:e.images.flat.peak?`https://raw.githubusercontent.com/RepDB/exercise-dataset/main/${e.images.flat.peak}`:null,level:e.difficulty,force:e.force_type,mechanic:e.mechanic,category:e.category,instructions_steps:e.instructions_en,body_part:e.body_part.replaceAll('_',' '),description:e.description_en??null,catalogue_source:'repdb',source_id:e.id,primary_muscles:e.primary_muscles,secondary_muscles:e.secondary_muscles??[],form_tips:e.tips_en??[],secondary_equipment:[],is_archived:false}));
// Supporting equipment is derived only from explicit setup instructions, not
// guessed from image recognition. Keep it separate from the weighted implement.
for (const e of canonical) {
 const setup=e.instructions_steps.slice(0,2).join(' ').toLowerCase();
 if(e.equipment!=='flat bench' && /(?:lie|sit|rest|place|support|position|set|adjust).*\bbench\b/.test(setup)) {
  e.secondary_equipment=[/preacher/.test(setup)?'preacher bench':/incline|decline/.test(`${setup} ${e.slug}`)?'adjustable bench':'flat bench'];
 }
 if(e.slug==='decline-bench-press') {
  e.name='Decline Dumbbell Bench Press';
  e.instructions_steps=['Set an adjustable bench to a slight decline and secure your feet.','Lie back with a dumbbell in each hand beside your lower chest.','Press the dumbbells upward with control, without banging them together.','Lower them slowly to the starting position.','Use manageable weights and ask for assistance getting into position when needed.'];
 }
}
const redirects=[];
for(const previous of old.filter(e=>e.is_built_in)) {
 const explicitSlug=explicit[normalize(previous.name)];
 const exact=canonical.filter(e=>explicitSlug?e.slug===explicitSlug:signature(e.name)===signature(previous.name));
 const match=exact.length===1?exact[0]:null;
 redirects.push({old_id:previous.id,new_id:match?.id??uuid(`history:${previous.id}`),name:previous.name,matched:!!match});
}
const assets = [...new Set(data.exercises.flatMap(e=>Object.values(e.images.flat)))];
for (const e of canonical) {
 e.image_url=e.image_url.replace('https://raw.githubusercontent.com/RepDB/exercise-dataset/main/',`${base}/storage/v1/object/public/repdb-exercise-images/`);
 if(e.secondary_image_url) e.secondary_image_url=e.secondary_image_url.replace('https://raw.githubusercontent.com/RepDB/exercise-dataset/main/',`${base}/storage/v1/object/public/repdb-exercise-images/`);
}
writeFileSync(new URL('snapshot.json',folder), JSON.stringify({revision:revision.sha,source,exercises:canonical,redirects,muscles,assets},null,2));
writeFileSync(new URL('report.json',folder),JSON.stringify({revision:revision.sha,oldBuiltIns:redirects.length,newCatalogue:canonical.length,exactMatches:redirects.filter(r=>r.matched).length,unmatched:redirects.filter(r=>!r.matched).map(r=>({id:r.old_id,name:r.name})),muscles},null,2));
// The import is one transaction. Retain only user-linked movement labels for
// unmatched history; no ExerciseDB descriptions, equipment or artwork survives.
const q = value => "'"+value.replaceAll("'","''")+"'";
const sql = [readFileSync(new URL('../supabase/migrations/026_repdb_catalogue.sql',import.meta.url),'utf8'), 'begin;',
 `do $$ begin if (select count(*) from public.exercises where is_built_in) <> ${redirects.length} or exists(select 1 from public.exercises where catalogue_source='repdb') then raise exception 'Catalogue changed; re-audit before import'; end if; end $$;`,
 'create temporary table shift_before_counts as select (select count(*) from public.plan_exercises) p,(select count(*) from public.session_sets) s,(select count(*) from public.exercise_goals) g;',
 `insert into public.muscle_groups(id,name,slug) values(${q(uuid('history-muscle'))},'Unclassified','unclassified') on conflict(id) do nothing;`,
 `insert into public.exercises select r.* from public.shift_catalogue_import s cross join lateral jsonb_populate_record(null::public.exercises,s.payload) r where s.kind='exercise';`,
 'create temporary table shift_redirects(old_id uuid,new_id uuid,matched boolean);',
 `insert into shift_redirects select (payload->>'old_id')::uuid,(payload->>'new_id')::uuid,(payload->>'matched')::boolean from public.shift_catalogue_import where kind='redirect';`,
 `insert into public.exercises(id,name,slug,primary_muscle_id,secondary_muscle_ids,is_built_in,catalogue_source,is_archived)
 select r.new_id,case when exists(select 1 from public.plan_exercises where exercise_id=e.id)
 or exists(select 1 from public.session_sets where exercise_id=e.id)
 or exists(select 1 from public.exercise_goals where exercise_id=e.id)
 then e.name else 'Archived exercise' end,'history-'||r.new_id,${q(uuid('history-muscle'))}::uuid,'{}'::uuid[],true,'history',true
 from shift_redirects r join public.exercises e on e.id=r.old_id where not r.matched;`,
 'insert into public.exercise_catalogue_redirects select old_id,new_id from shift_redirects;',
 ...['plan_exercises','session_sets','exercise_goals'].map(t=>`update public.${t} t set exercise_id=r.new_id from shift_redirects r where t.exercise_id=r.old_id;`),
 'delete from public.exercises e using shift_redirects r where e.id=r.old_id;',
 `do $$ begin if (select count(*) from public.exercises where catalogue_source='repdb' and not is_archived) <> ${canonical.length}
 or exists(select 1 from public.exercises where is_built_in and catalogue_source is null)
 or exists(select 1 from shift_before_counts c where c.p<>(select count(*) from public.plan_exercises) or c.s<>(select count(*) from public.session_sets) or c.g<>(select count(*) from public.exercise_goals))
 then raise exception 'Migration validation failed'; end if; end $$;`,
 'drop table public.shift_catalogue_import;', 'commit;',
 'select catalogue_source,is_archived,count(*) from public.exercises where is_built_in group by 1,2;'];
writeFileSync(new URL('apply-catalogue.sql',folder),sql.join('\n'));
writeFileSync(new URL('stage-storage.sql',folder),`insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('repdb-exercise-images','repdb-exercise-images',true,1048576,array['image/webp']) on conflict(id) do nothing;
drop policy if exists shift_repdb_staging_upload on storage.objects;
create policy shift_repdb_staging_upload on storage.objects for insert to authenticated
with check(bucket_id='repdb-exercise-images' and (select auth.uid())=${q(auth.user.id)}::uuid);`);
writeFileSync(new URL('stage-catalogue.sql',folder),`begin;
create table public.shift_catalogue_import(id uuid primary key,kind text not null check(kind in ('exercise','redirect')),payload jsonb not null);
alter table public.shift_catalogue_import enable row level security;
revoke all on public.shift_catalogue_import from anon,authenticated;
grant insert,select on public.shift_catalogue_import to authenticated;
create policy shift_import_insert on public.shift_catalogue_import for insert to authenticated with check((select auth.uid())=${q(auth.user.id)}::uuid);
create policy shift_import_read on public.shift_catalogue_import for select to authenticated using((select auth.uid())=${q(auth.user.id)}::uuid);
drop policy if exists shift_repdb_staging_upload on storage.objects;
commit;`);
console.log(JSON.stringify({oldBuiltIns:redirects.length,newCatalogue:canonical.length,exactMatches:redirects.filter(r=>r.matched).length,assets:assets.length,revision:revision.sha}));
