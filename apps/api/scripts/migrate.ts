import { promises as fs } from "node:fs";
import path from "node:path";
import { FileMigrationProvider, Migrator } from "kysely";
import { makeDb } from "../src/db";

const connectionString = process.env["DATABASE_URL"];
if (!connectionString) {
  console.error("DATABASE_URL is required");
  process.exit(1);
}

const db = makeDb(connectionString);
const migrator = new Migrator({
  db,
  provider: new FileMigrationProvider({
    fs,
    path,
    migrationFolder: path.resolve(import.meta.dir, "../src/db/migrations"),
  }),
});

const cmd = process.argv[2] ?? "up";

async function run() {
  if (cmd === "up") {
    const { error, results } = await migrator.migrateToLatest();
    report(results, error);
  } else if (cmd === "down-latest") {
    const { error, results } = await migrator.migrateDown();
    report(results, error);
  } else if (cmd === "status") {
    const all = await migrator.getMigrations();
    for (const m of all) {
      console.log(`${m.executedAt ? "[x]" : "[ ]"} ${m.name}`);
    }
  } else {
    console.error(`Unknown command: ${cmd}`);
    console.error("Usage: bun run scripts/migrate.ts [up|down-latest|status]");
    process.exit(1);
  }

  await db.destroy();
}

function report(results: Awaited<ReturnType<Migrator["migrateToLatest"]>>["results"], error: unknown) {
  for (const r of results ?? []) {
    if (r.status === "Success") {
      console.log(`  ok   ${r.direction} ${r.migrationName}`);
    } else if (r.status === "Error") {
      console.error(`  fail ${r.direction} ${r.migrationName}`);
    } else {
      console.log(`  skip ${r.direction} ${r.migrationName}`);
    }
  }
  if (error) {
    console.error("migration failed:", error);
    process.exit(1);
  }
}

await run();
