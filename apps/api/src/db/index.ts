import { CamelCasePlugin, Kysely, PostgresDialect, sql } from "kysely";
import pg from "pg";
import type { Database } from "./schema";

// Postgres returns BIGINT (int8) and NUMERIC as strings by default. Our IDs are uuids and our money
// values are small and well within Number.MAX_SAFE_INTEGER, so parse both as JS numbers for ergonomics.
pg.types.setTypeParser(pg.types.builtins.INT8, Number);
pg.types.setTypeParser(pg.types.builtins.NUMERIC, Number);
// Keep DATE as the "YYYY-MM-DD" string the wire contract uses; pg's default JS Date would drag
// timezones into a plain calendar date.
pg.types.setTypeParser(pg.types.builtins.DATE, (value) => value);

export type LedgerDb = Kysely<Database>;

export function makeDb(connectionString: string): LedgerDb {
  const pool = new pg.Pool({ connectionString, max: 10 });
  return new Kysely<Database>({
    dialect: new PostgresDialect({ pool }),
    plugins: [new CamelCasePlugin()],
  });
}

export { sql };
export type { Database };
