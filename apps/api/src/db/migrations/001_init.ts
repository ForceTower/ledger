import { type Kysely, sql } from "kysely";

export async function up(db: Kysely<unknown>): Promise<void> {
  await sql`create extension if not exists pg_trgm`.execute(db);

  await db.schema
    .createTable("stores")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("name", "text", (col) => col.notNull())
    .addColumn("legal_name", "text")
    .addColumn("cnpj", "text", (col) => col.unique())
    .addColumn("address", "text")
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema
    .createTable("products")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("barcode", "text", (col) => col.notNull().unique())
    .addColumn("canonical_description", "text")
    .addColumn("default_category", "text")
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema
    .createTable("purchases")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("slug", "text", (col) => col.notNull().unique())
    .addColumn("date", "date", (col) => col.notNull())
    .addColumn("time", "text")
    .addColumn("source", "text", (col) => col.notNull())
    .addColumn("store_id", "uuid", (col) => col.references("stores.id").onDelete("set null"))
    .addColumn("access_key", "text", (col) => col.unique())
    .addColumn("receipt_number", "integer")
    .addColumn("receipt_series", "integer")
    .addColumn("gross_total", "numeric(12, 2)", (col) => col.notNull())
    .addColumn("discount_total", "numeric(12, 2)", (col) => col.notNull().defaultTo(0))
    .addColumn("paid_total", "numeric(12, 2)", (col) => col.notNull())
    .addColumn("item_count", "integer", (col) => col.notNull())
    .addColumn("taxes_total", "numeric(12, 2)")
    .addColumn("source_html", "text")
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema.createIndex("purchases_date_idx").on("purchases").column("date").execute();
  await db.schema.createIndex("purchases_store_id_idx").on("purchases").column("store_id").execute();

  await db.schema
    .createTable("purchase_items")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("purchase_id", "uuid", (col) => col.notNull().references("purchases.id").onDelete("cascade"))
    .addColumn("product_id", "uuid", (col) => col.references("products.id").onDelete("set null"))
    .addColumn("seq", "integer", (col) => col.notNull())
    .addColumn("description", "text", (col) => col.notNull())
    .addColumn("code", "text")
    .addColumn("barcode", "text")
    .addColumn("quantity", "numeric(12, 3)", (col) => col.notNull())
    .addColumn("unit", "text")
    .addColumn("unit_price", "numeric(12, 2)", (col) => col.notNull())
    .addColumn("total", "numeric(12, 2)", (col) => col.notNull())
    .addColumn("category", "text", (col) => col.notNull())
    .addUniqueConstraint("purchase_items_purchase_seq_unique", ["purchase_id", "seq"])
    .execute();

  await db.schema.createIndex("purchase_items_product_id_idx").on("purchase_items").column("product_id").execute();
  await db.schema.createIndex("purchase_items_barcode_idx").on("purchase_items").column("barcode").execute();
  await sql`
    create index purchase_items_description_trgm_idx
    on purchase_items using gin (description gin_trgm_ops)
  `.execute(db);

  await db.schema
    .createTable("payments")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("purchase_id", "uuid", (col) => col.notNull().references("purchases.id").onDelete("cascade"))
    .addColumn("code", "integer")
    .addColumn("method", "text", (col) => col.notNull())
    .addColumn("amount", "numeric(12, 2)", (col) => col.notNull())
    .addColumn("change", "numeric(12, 2)")
    .execute();

  await db.schema.createIndex("payments_purchase_id_idx").on("payments").column("purchase_id").execute();

  await db.schema
    .createTable("trips")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("date", "date", (col) => col.notNull().unique())
    .addColumn("legs", "jsonb", (col) => col.notNull())
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();

  await db.schema
    .createTable("donations")
    .addColumn("id", "uuid", (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn("date", "date", (col) => col.notNull())
    .addColumn("source_purchase_slug", "text")
    .addColumn("entries", "jsonb", (col) => col.notNull())
    .addColumn("total", "numeric(12, 2)")
    .addColumn("created_at", "timestamptz", (col) => col.notNull().defaultTo(sql`now()`))
    .execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable("donations").execute();
  await db.schema.dropTable("trips").execute();
  await db.schema.dropTable("payments").execute();
  await db.schema.dropTable("purchase_items").execute();
  await db.schema.dropTable("purchases").execute();
  await db.schema.dropTable("products").execute();
  await db.schema.dropTable("stores").execute();
}
