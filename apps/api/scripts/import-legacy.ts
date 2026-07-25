/**
 * One-time import of the file-based prototype history into Postgres.
 *
 * Usage: DATABASE_URL=… bun run scripts/import-legacy.ts <path-to-prototype-repo>
 *
 * Reads dados/{compras,transporte,doacoes}/*.json, translates the Portuguese field names to the
 * English schema (see docs/architecture.md for the mapping), and upserts by natural key
 * (access_key / slug / date). Legacy purchase ids are kept as slugs so donation references stay
 * valid. Idempotent — safe to re-run.
 */

import { promises as fs } from "node:fs";
import path from "node:path";
import type { Category } from "@ledger/shared-types";
import type { Transaction } from "kysely";
import type { z } from "zod";
import type { Database, LedgerDb } from "../src/db";
import { makeDb } from "../src/db";
import type { LegacyItem, LegacyPurchase, legacyCategorySchema } from "./legacy-schema";
import { legacyDonationSchema, legacyPurchaseSchema, legacyTripSchema } from "./legacy-schema";

type Trx = Transaction<Database>;

const CATEGORY: Record<z.infer<typeof legacyCategorySchema>, Category> = {
  hortifruti: "produce",
  carnes: "meat",
  frios_laticinios: "dairy_deli",
  padaria: "bakery",
  mercearia: "grocery",
  bebidas: "beverages",
  doces_snacks: "snacks_sweets",
  congelados: "frozen",
  limpeza: "cleaning",
  higiene: "hygiene",
  pet: "pet",
  bazar_utilidades: "household",
  outros: "other",
};

const TRIP_MODE: Record<string, string> = {
  carro_proprio: "own_car",
  onibus: "bus",
  outro: "other",
};

type Outcome = "inserted" | "skipped";

async function importPurchase(db: LedgerDb, repoRoot: string, file: string): Promise<Outcome> {
  const legacy = legacyPurchaseSchema.parse(JSON.parse(await fs.readFile(file, "utf8")));
  const accessKey = legacy.nfce?.chave_acesso ?? null;

  return await db.transaction().execute(async (trx) => {
    const existing = await trx
      .selectFrom("purchases")
      .select("id")
      .where((eb) =>
        accessKey ? eb.or([eb("slug", "=", legacy.id), eb("accessKey", "=", accessKey)]) : eb("slug", "=", legacy.id),
      )
      .executeTakeFirst();
    if (existing) return "skipped";

    const storeId = await resolveStore(trx, legacy);
    const purchase = await trx
      .insertInto("purchases")
      .values({
        slug: legacy.id,
        date: legacy.data,
        time: legacy.hora || null,
        source: legacy.origem,
        storeId,
        accessKey,
        receiptNumber: legacy.nfce?.numero ?? null,
        receiptSeries: legacy.nfce?.serie ?? null,
        grossTotal: legacy.totais.valor_bruto,
        discountTotal: legacy.totais.descontos,
        paidTotal: legacy.totais.valor_pago,
        itemCount: legacy.totais.qtd_itens,
        taxesTotal: legacy.tributos_totais,
        sourceHtml: await readSourceHtml(repoRoot, legacy.fonte_html),
      })
      .returning("id")
      .executeTakeFirstOrThrow();

    const productIdByBarcode = await upsertProducts(trx, legacy.itens);

    await trx
      .insertInto("purchaseItems")
      .values(
        legacy.itens.map((item) => ({
          purchaseId: purchase.id,
          productId: item.codigo_barras ? (productIdByBarcode.get(item.codigo_barras) ?? null) : null,
          seq: item.seq,
          description: item.descricao,
          code: item.codigo || null,
          barcode: item.codigo_barras ?? null,
          quantity: item.quantidade,
          unit: item.unidade || null,
          unitPrice: item.valor_unitario,
          total: item.valor_total,
          category: CATEGORY[item.categoria],
        })),
      )
      .execute();

    if (legacy.pagamento.length > 0) {
      await trx
        .insertInto("payments")
        .values(
          legacy.pagamento.map((payment) => ({
            purchaseId: purchase.id,
            code: paymentCode(payment.codigo),
            method: payment.forma,
            amount: payment.valor,
            change: payment.troco ?? null,
          })),
        )
        .execute();
    }

    return "inserted";
  });
}

/**
 * Mirrors the scan flow's store resolution (see service/ingest.ts): CNPJ match wins and never
 * overwrites the user-curated name; the legacy nome is the printed razão social on NFC-e entries.
 */
async function resolveStore(trx: Trx, legacy: LegacyPurchase): Promise<string> {
  const cnpj = legacy.loja.cnpj || null;
  const name = legacy.loja.nome;

  const existing = await trx
    .selectFrom("stores")
    .select("id")
    .where((eb) => (cnpj ? eb("cnpj", "=", cnpj) : eb.and([eb("cnpj", "is", null), eb("name", "=", name)])))
    .executeTakeFirst();
  if (existing) return existing.id;

  const inserted = await trx
    .insertInto("stores")
    .values({
      name,
      legalName: legacy.origem === "nfce" ? name : null,
      cnpj,
      address: legacy.loja.endereco || null,
    })
    .returning("id")
    .executeTakeFirstOrThrow();
  return inserted.id;
}

async function upsertProducts(trx: Trx, items: LegacyItem[]): Promise<Map<string, string>> {
  const itemByBarcode = new Map<string, LegacyItem>();
  for (const item of items) {
    if (item.codigo_barras && !itemByBarcode.has(item.codigo_barras)) itemByBarcode.set(item.codigo_barras, item);
  }
  if (itemByBarcode.size === 0) return new Map();

  await trx
    .insertInto("products")
    .values(
      [...itemByBarcode.entries()].map(([barcode, item]) => ({
        barcode,
        canonicalDescription: item.descricao,
        defaultCategory: CATEGORY[item.categoria],
      })),
    )
    .onConflict((oc) => oc.column("barcode").doNothing())
    .execute();

  const rows = await trx
    .selectFrom("products")
    .select(["id", "barcode"])
    .where("barcode", "in", [...itemByBarcode.keys()])
    .execute();
  return new Map(rows.map((row) => [row.barcode, row.id]));
}

function paymentCode(raw: number | string | null | undefined): number | null {
  if (raw === null || raw === undefined || raw === "") return null;
  const code = typeof raw === "number" ? raw : Number(raw);
  return Number.isInteger(code) ? code : null;
}

/** The scan flow stores the simplified receipt HTML; prefer the html_simple file of the same name. */
async function readSourceHtml(repoRoot: string, fonteHtml: string | undefined): Promise<string | null> {
  if (!fonteHtml) return null;
  const candidates = [
    path.join(repoRoot, "fontes/html_simple", path.basename(fonteHtml)),
    path.join(repoRoot, fonteHtml),
  ];
  for (const candidate of candidates) {
    try {
      return await fs.readFile(candidate, "utf8");
    } catch {
      // fall through to the next candidate
    }
  }
  return null;
}

async function importTrip(db: LedgerDb, file: string): Promise<Outcome> {
  const legacy = legacyTripSchema.parse(JSON.parse(await fs.readFile(file, "utf8")));
  const legs = legacy.trajetos.map((leg) => ({
    mode: TRIP_MODE[leg.meio] ?? leg.meio,
    destinations: leg.destinos,
    distanceKm: leg.distancia_km,
    fuelCost: leg.custo_combustivel,
    parkingCost: leg.custo_estacionamento,
    totalCost: leg.custo_total,
    notes: leg.notas ?? null,
  }));

  const result = await db
    .insertInto("trips")
    .values({ date: legacy.data, legs: JSON.stringify(legs) })
    .onConflict((oc) => oc.column("date").doNothing())
    .executeTakeFirst();
  return result.numInsertedOrUpdatedRows === 1n ? "inserted" : "skipped";
}

async function importDonation(db: LedgerDb, file: string): Promise<Outcome> {
  const legacy = legacyDonationSchema.parse(JSON.parse(await fs.readFile(file, "utf8")));

  const existing = await db.selectFrom("donations").select("id").where("date", "=", legacy.data).executeTakeFirst();
  if (existing) return "skipped";

  const entries = legacy.doacoes.map((donation) => ({
    recipient: donation.destinatario,
    items: donation.itens.map((item) => ({
      description: item.descricao,
      code: item.codigo,
      quantity: item.quantidade,
      unit: item.unidade,
      unitPrice: item.valor_unitario,
      total: item.valor_total,
      refSeq: item.ref_seq,
      refPurchase: item.ref_compra ?? null,
    })),
    total: donation.valor_total,
  }));

  await db
    .insertInto("donations")
    .values({
      date: legacy.data,
      sourcePurchaseSlug: legacy.compra_origem ?? null,
      entries: JSON.stringify(entries),
      total: legacy.valor_total_doacoes,
    })
    .execute();
  return "inserted";
}

async function listJsonFiles(dir: string): Promise<string[]> {
  try {
    const names = await fs.readdir(dir);
    return names
      .filter((name) => name.endsWith(".json"))
      .sort()
      .map((name) => path.join(dir, name));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
}

async function importAll(db: LedgerDb, repoRoot: string): Promise<void> {
  const kinds = [
    { label: "purchases", dir: "dados/compras", run: (file: string) => importPurchase(db, repoRoot, file) },
    { label: "trips", dir: "dados/transporte", run: (file: string) => importTrip(db, file) },
    { label: "donations", dir: "dados/doacoes", run: (file: string) => importDonation(db, file) },
  ];

  for (const kind of kinds) {
    const files = await listJsonFiles(path.join(repoRoot, kind.dir));
    let inserted = 0;
    let skipped = 0;
    for (const file of files) {
      try {
        if ((await kind.run(file)) === "inserted") inserted++;
        else skipped++;
      } catch (error) {
        throw new Error(`${path.relative(repoRoot, file)}: ${error instanceof Error ? error.message : String(error)}`, {
          cause: error,
        });
      }
    }
    console.log(`${kind.label}: ${inserted} inserted, ${skipped} skipped (already present), ${files.length} total`);
  }
}

const repoPath = process.argv[2];
if (!repoPath) {
  console.error("Usage: DATABASE_URL=… bun run scripts/import-legacy.ts <path-to-prototype-repo>");
  process.exit(1);
}

const connectionString = process.env["DATABASE_URL"];
if (!connectionString) {
  console.error("DATABASE_URL is required");
  process.exit(1);
}

const db = makeDb(connectionString);
try {
  await importAll(db, path.resolve(repoPath));
} finally {
  await db.destroy();
}
