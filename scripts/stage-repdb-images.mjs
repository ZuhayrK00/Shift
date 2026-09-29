// Explicit staging/upload step. A temporary, reviewer-only Storage INSERT policy
// must be enabled first and removed immediately after staging is verified.
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const root=new URL('../',import.meta.url);
const folder=new URL('../migration-preparation/repdb/',import.meta.url);
const snapshot=JSON.parse(readFileSync(new URL('snapshot.json',folder),'utf8'));
const key=readFileSync(new URL('Shift/Helpers/SupabaseClient.swift',root),'utf8').match(/supabaseKey: "([^"]+)"/)[1];
const password=execFileSync('security',['find-generic-password','-s','ShiftLaunchReviewAccount','-a','shift-review-20260929@shiftfitness.pro','-w'],{encoding:'utf8'}).trim();
const base='https://dtzlfvuazdrgyyutjysm.supabase.co';
const response=await fetch(`${base}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({email:'shift-review-20260929@shiftfitness.pro',password})});
if(!response.ok)throw new Error(`Authentication failed ${response.status}`);
const auth=await response.json();
const previous=process.argv.includes('--retry-failed')?JSON.parse(readFileSync(new URL('image-staging-report.json',folder),'utf8')):null;
const pending=previous?previous.failures.map(f=>f.path):snapshot.assets;
const completed=new Set(); const failures=[];let next=0;
async function worker(){
 while(next<pending.length){
  const path=pending[next++];
  try {
   const target=`${base}/storage/v1/object/public/repdb-exercise-images/${path}`;
   const existing=await fetch(target,{method:'HEAD'});
   if(!existing.ok){
    const original=await fetch(`${snapshot.source}/${path}`);
    if(!original.ok)throw new Error(`Source HTTP ${original.status}`);
    const bytes=new Uint8Array(await original.arrayBuffer());
    if(bytes.length>1048576||String.fromCharCode(...bytes.slice(0,4))!=='RIFF'||String.fromCharCode(...bytes.slice(8,12))!=='WEBP')throw new Error('Invalid WebP asset');
    const uploaded=await fetch(`${base}/storage/v1/object/repdb-exercise-images/${path}`,{method:'POST',headers:{apikey:key,Authorization:`Bearer ${auth.access_token}`,'Content-Type':'image/webp','Cache-Control':'31536000','x-upsert':'false'},body:bytes});
    if(!uploaded.ok)throw new Error(`Storage HTTP ${uploaded.status}`);
   }
const check=await fetch(target,{method:'HEAD'});
   if(!check.ok||!check.headers.get('content-type')?.includes('image/webp'))throw new Error(`Verification HTTP ${check.status}`);
   completed.add(path);
   if(completed.size%100===0)console.log(`${completed.size}/${snapshot.assets.length} images verified`);
  }catch(error){failures.push({path,error:error.message});}
 }
}
await Promise.all(Array.from({length:previous?1:3},worker));
const verified=(previous?.verified??0)+completed.size;
writeFileSync(new URL('image-staging-report.json',folder),JSON.stringify({revision:snapshot.revision,verified,expected:snapshot.assets.length,failures},null,2));
console.log(JSON.stringify({verified,expected:snapshot.assets.length,failures:failures.length}));
if(failures.length)process.exitCode=1;
