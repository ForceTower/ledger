import { type Kysely, sql } from "kysely";

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable("ai_requests")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("operation", "text", (col) => col.notNull()) // photo_scan | entry | categorize | transfer | chat
    .addColumn("model", "text", (col) => col.notNull())
    .addColumn("transport", "text", (col) => col.notNull()) // api | agent
    .addColumn("input_tokens", "integer", (col) => col.notNull())
    .addColumn("output_tokens", "integer", (col) => col.notNull())
    // USD, unlike the BRL money columns. Null when the model has no pricing entry.
    .addColumn("cost_usd", "numeric(12, 6)")
    .addColumn("duration_ms", "integer", (col) => col.notNull())
    // Chat only: the Agent SDK session and how many turns the run took.
    .addColumn("session_id", "text")
    .addColumn("num_turns", "integer")
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema.createIndex("ai_requests_created_at_idx").on("ai_requests").column("created_at").execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable("ai_requests").execute();
}
