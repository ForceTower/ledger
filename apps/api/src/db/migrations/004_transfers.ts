import { type Kysely, sql } from "kysely";

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable("transfers")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    // The bank's end-to-end ID (e.g. Pix E2E). Dedup key, like access_key for NFC-e.
    .addColumn("transaction_id", "text", (col) => col.notNull().unique())
    .addColumn("transfer_type", "text", (col) => col.notNull()) // pix (ted/doc/boleto later)
    .addColumn("amount", "numeric(12, 2)", (col) => col.notNull())
    .addColumn("date", "date", (col) => col.notNull())
    .addColumn("time", "text")
    .addColumn("destination_name", "text", (col) => col.notNull())
    .addColumn("destination_institution", "text")
    .addColumn("destination_agency", "text")
    .addColumn("destination_account", "text")
    .addColumn("origin_name", "text")
    .addColumn("origin_institution", "text")
    // The purchase this transfer materialized into; the transfer row survives as raw evidence.
    .addColumn("purchase_id", "uuid", (col) => col.references("purchases.id").onDelete("set null"))
    // Full AI extraction, kept for audit (parallel to purchases.source_html).
    .addColumn("extracted", "jsonb")
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema.createIndex("transfers_date_idx").on("transfers").column("date").execute();
  await db.schema.createIndex("transfers_purchase_id_idx").on("transfers").column("purchase_id").execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable("transfers").execute();
}
