// Run the schema/RLS integration test in a fresh, in-memory PostgreSQL engine.
// Install @electric-sql/pglite in an isolated tools directory, then optionally
// set PGLITE_MODULE_PATH to its dist/index.js. No server connection is accepted.
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
const migration = await readFile(new URL('../supabase/migrations/027_endurance.sql', import.meta.url), 'utf8');
let sql = await readFile(new URL('./test-endurance-schema.sql', import.meta.url), 'utf8');
if (!sql.includes("current_database() not like 'shift_endurance_test_%'")) {
  throw new Error('Expected the disposable-database guard');
}
// PGlite's fresh in-memory database is always named postgres. Adapt only the
// name check; preserve the executable SQL and all security assertions.
sql = sql.replace("current_database() not like 'shift_endurance_test_%'", 'false')
  .replace(/^\\set .*$/gm, '')
  .replace('\\ir ../supabase/migrations/027_endurance.sql', migration);
const db = new PGlite();
try {
  const results = await db.exec(sql);
  console.log(results.at(-1).rows);
} finally {
  await db.close();
}
