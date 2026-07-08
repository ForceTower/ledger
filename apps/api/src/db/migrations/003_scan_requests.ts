import { type Kysely, sql } from "kysely";

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable("scan_requests")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("url", "text", (col) => col.notNull())
    .addColumn("status", "text", (col) => col.notNull()) // saved | duplicate | failed
    .addColumn("error_code", "text")
    .addColumn("error_message", "text")
    .addColumn("purchase_slug", "text")
    .addColumn("warnings", "jsonb")
    .addColumn("duration_ms", "integer", (col) => col.notNull())
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema.createIndex("scan_requests_created_at_idx").on("scan_requests").column("created_at").execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable("scan_requests").execute();
}
