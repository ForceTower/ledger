/**
 * Re-run categorization over purchase items already in the database, so improvements to the rules
 * reach history and not just the next scan. Resolution is the same chain the scan flow uses: the
 * keyword rules, then what the barcode was filed under before, then the model for what is left.
 *
 * Usage: DATABASE_URL=… bun run scripts/recategorize.ts [--apply] [--all] [--no-ai]
 *
 * Prints the diff and changes nothing unless --apply is passed. Only `nfce` purchases are touched by
 * default: `manual` and `pix` items were categorized by the owner or by the photo scan, and those
 * are deliberate answers rather than rule output. --all includes them anyway.
 *
 * Idempotent — safe to re-run.
 */

import { categorize } from "@ledger/nfce";
import type { Category } from "@ledger/shared-types";
import { z } from "zod";
import { makeDb } from "../src/db";
import { AiClient } from "../src/service/ai";
import { CategorizerService, DEFAULT_CATEGORIZE_PROMPT } from "../src/service/categorize";

const argsSchema = z.object({
  DATABASE_URL: z.string(),
  ANTHROPIC_API_KEY: z.string().optional(),
  CLAUDE_CODE_OAUTH_TOKEN: z.string().optional(),
  CLAUDE_CATEGORIZE_MODEL: z.string().default("claude-sonnet-5"),
  // Nobody is waiting on a backfill, so it can afford a slower model than the scan path.
  CLAUDE_TIMEOUT_MS: z.coerce.number().default(180_000),
});

interface Row {
  id: string;
  description: string;
  barcode: string | null;
  category: Category;
  source: string;
  slug: string;
}

async function main(): Promise<void> {
  const flags = new Set(process.argv.slice(2));
  const apply = flags.has("--apply");
  const includeAll = flags.has("--all");
  const useAi = !flags.has("--no-ai");

  const env = argsSchema.parse(process.env);
  const db = makeDb(env.DATABASE_URL);

  try {
    let query = db
      .selectFrom("purchaseItems")
      .innerJoin("purchases", "purchases.id", "purchaseItems.purchaseId")
      .select([
        "purchaseItems.id",
        "purchaseItems.description",
        "purchaseItems.barcode",
        "purchaseItems.category",
        "purchases.source",
        "purchases.slug",
      ])
      .orderBy("purchases.date")
      .orderBy("purchaseItems.seq");
    if (!includeAll) query = query.where("purchases.source", "=", "nfce");
    const rows: Row[] = await query.execute();

    // The rules run first so the resolver only pays for what they cannot place, exactly as at ingest.
    const ruled = rows.map((row) => ({ row, category: categorize(row.description) }));

    const ai = useAi
      ? new AiClient({
          apiKey: env.ANTHROPIC_API_KEY || undefined,
          model: env.CLAUDE_CATEGORIZE_MODEL,
          timeoutMs: env.CLAUDE_TIMEOUT_MS,
        })
      : undefined;
    const categorizer = new CategorizerService({ db, ai, prompt: DEFAULT_CATEGORIZE_PROMPT });
    const resolved = await categorizer.resolve(
      ruled.map(({ row, category }) => ({
        seq: 0,
        description: row.description,
        code: "",
        barcode: row.barcode,
        quantity: 0,
        unit: "",
        unitPrice: 0,
        total: 0,
        category,
      })),
    );

    const changes = ruled
      .map(({ row }, index) => ({ row, next: resolved[index]?.category ?? row.category }))
      .filter(({ row, next }) => next !== row.category);

    for (const { row, next } of changes) {
      console.log(`${row.slug}  ${row.category.padEnd(14)} -> ${next.padEnd(14)}  ${row.description}`);
    }

    const stillOther = resolved.filter((item) => item.category === "other").length;
    console.log(
      `\n${rows.length} items (${includeAll ? "all sources" : "nfce only"}) | ` +
        `${changes.length} to change | ${stillOther} left as other`,
    );

    if (!apply) {
      console.log("\nDry run — pass --apply to write these changes.");
      return;
    }
    if (changes.length === 0) return;

    await db.transaction().execute(async (trx) => {
      for (const { row, next } of changes) {
        await trx.updateTable("purchaseItems").set({ category: next }).where("id", "=", row.id).execute();
      }
      // Keep the barcode memory in step, so the next scan of a product agrees with its history.
      for (const { row, next } of changes) {
        if (!row.barcode || next === "other") continue;
        await trx
          .updateTable("products")
          .set({ defaultCategory: next })
          .where("barcode", "=", row.barcode)
          .where((eb) => eb.or([eb("defaultCategory", "is", null), eb("defaultCategory", "=", "other")]))
          .execute();
      }
    });
    console.log(`\nApplied ${changes.length} changes.`);
  } finally {
    await db.destroy();
  }
}

await main();
