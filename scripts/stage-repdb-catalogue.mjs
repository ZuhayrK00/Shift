// Upload prepared rows to a temporary RLS-protected staging table. The catalogue
// remains unchanged until the checked SQL import transaction commits.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const root=new URL('../',import.meta.url);
const folder=new URL('../migration-preparation/repdb/',import.meta.url);
const snapshot=JSON.parse(readFileSync(new URL('snapshot.json',folder),'utf8'));
const images=JSON.parse(readFileSync(new URL('image-staging-report.json',folder),'utf8'));
if(images.revision!==snapshot.revision||images.verified!==snapshot.assets.length||images.failures.length)throw new Error('Verify all images before staging catalogue');
const key=readFileSync(new URL('Shift/Helpers/SupabaseClient.swift',root),'utf8').match(/supabaseKey: "([^"]+)"/)[1];
const password=execFileSync('security',['find-generic-password','-s','ShiftLaunchReviewAccount','-a','shift-review-20260929@shiftfitness.pro','-w'],{encoding:'utf8'}).trim();
const base='https://dtzlfvuazdrgyyutjysm.supabase.co';
const response=await fetch(`${base}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({email:'shift-review-20260929@shiftfitness.pro',password})});
if(!response.ok)throw new Error(`Authentication failed ${response.status}`);
const auth=await response.json();
const rows=[...snapshot.exercises.map(e=>({id:e.id,kind:'exercise',payload:e})),...snapshot.redirects.map(r=>({id:r.old_id,kind:'redirect',payload:{old_id:r.old_id,new_id:r.new_id,matched:r.matched}}))];
for(let start=0;start<rows.length;start+=75){
 const result=await fetch(`${base}/rest/v1/shift_catalogue_import`,{method:'POST',headers:{apikey:key,Authorization:`Bearer ${auth.access_token}`,'Content-Type':'application/json'},body:JSON.stringify(rows.slice(start,start+75))});
 if(!result.ok)throw new Error(`Staging batch ${start} HTTP ${result.status}`);
}
const check=await fetch(`${base}/rest/v1/shift_catalogue_import?select=id`,{method:'HEAD',headers:{apikey:key,Authorization:`Bearer ${auth.access_token}`,Prefer:'count=exact'}});
if(!check.ok||!check.headers.get('content-range')?.endsWith('/'+rows.length))throw new Error('Staging row count mismatch');
console.log(`${rows.length} catalogue and redirect rows staged; production catalogue unchanged`);
