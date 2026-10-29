// Disposable PostgreSQL fixtures. No network or customer data.
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
const db = new PGlite();
const owner = '11111111-1111-4111-8111-111111111111', other = '22222222-2222-4222-8222-222222222222';
const program = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', second = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
function sessions(user = owner, id = program, count = 5) {
 return Array.from({length:count},(_,i)=>({id:`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`,userId:user,programID:id,
 title:'Fixture walk',kind:'endurance',sport:'walk',status:'scheduled',targetSeconds:1800,scheduledAt:new Date(Date.now()+(i+1)*86400000).toISOString()}));
}
async function save(id, items) { return (await db.query('select public.save_endurance_week_preview($1,$2::jsonb) as saved',[id,JSON.stringify(items)])).rows[0].saved; }
async function rejected(action) { let failed=false; try {await action();} catch {failed=true;} if(!failed) throw Error('Expected rejection'); }
try {
 await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth; create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth to authenticated; insert into auth.users values ('${owner}'),('${other}');`);
 for (const file of ['028_endurance_training.sql','029_endurance_week_preview.sql']) await db.exec(await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec(`set role authenticated; set request.jwt.claim.sub='${owner}'`);
 await rejected(()=>save(program,[]));
 await rejected(()=>save(program,sessions(other)));
 const invalid=sessions(); invalid[1].targetSeconds=-1; await rejected(()=>save(program,invalid));
 const wide=sessions();wide[4].scheduledAt=new Date(Date.now()+20*86400000).toISOString();await rejected(()=>save(program,wide));
 if((await db.query('select * from public.endurance_week_previews')).rows.length!==0) throw Error('Failed claim consumed preview');
 const saved=await save(program,sessions());
 if(saved.sessions.length!==5 || saved.receipt.user_id!==owner) throw Error('Incomplete week');
 const again=await save(program,sessions()); if(again.sessions.length!==5) throw Error('Retry duplicated week');
 const another=await save(second,sessions(owner,second)); if(another.receipt.program_id!==program) throw Error('Second week accepted');
 if((await db.query('select count(*)::int as n from public.training_sessions')).rows[0].n!==5) throw Error('Duplicate sessions');
 await rejected(()=>db.exec('delete from public.endurance_week_previews'));
 await rejected(()=>db.exec(`update public.endurance_week_previews set program_id='${second}'`));
 await db.exec(`delete from public.training_sessions where id='00000000-0000-4000-8000-000000000001'`);
 const deletedRetry=await save(program,sessions());if(deletedRetry.sessions.length!==4)throw Error('Deleted session resurrected');
 await db.exec(`update public.training_sessions set details=details||'{"title":"Edited"}' where id='00000000-0000-4000-8000-000000000002'`);
 if(!(await save(program,sessions())).sessions.some(s=>s.title==='Edited')) throw Error('Edit overwritten');
 await db.exec(`set request.jwt.claim.sub='${other}'`);
 if((await db.query('select * from public.endurance_week_previews')).rows.length!==0) throw Error('Other account receipt visible');
 // ID collisions roll back both session inserts and receipt.
 await rejected(()=>save(second,sessions(other,second)));
 if((await db.query('select * from public.endurance_week_previews')).rows.length!==0) throw Error('Collision burned preview');
 await db.exec(`reset role; set role anon`);await rejected(()=>save(program,sessions()));await rejected(()=>db.query('select * from public.endurance_week_previews'));
 await db.exec(`reset role; delete from auth.users where id='${owner}'`);
 if((await db.query('select * from public.endurance_week_previews')).rows.length!==0) throw Error('Account deletion did not cascade');
 console.log('Preview schema: full week, rollback, idempotency, second-claim denial, account isolation, read-only receipt, edit/deletion preservation, anonymous denial and account deletion passed.');
} finally {await db.close();}
