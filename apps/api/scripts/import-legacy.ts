/**
 * One-time import of the file-based prototype history into Postgres.
 *
 * Usage: bun run scripts/import-legacy.ts -- <path-to-prototype-repo>
 *
 * Reads dados/{compras,transporte,doacoes}/*.json, translates the Portuguese field names to the
 * English schema (see docs/architecture.md for the mapping), and upserts by natural key
 * (access_key / slug). Idempotent — safe to re-run.
 *
 * TODO: implement. Outline:
 *   1. Resolve the repo path from argv; glob dados/compras/*.json.
 *   2. For each purchase: upsert store (by cnpj), upsert products (by barcode), insert purchase
 *      (on conflict (access_key) do nothing), insert items + payments. Wrap each purchase in a tx.
 *   3. Import dados/transporte/*.json -> trips, dados/doacoes/*.json -> donations.
 *   4. Print a summary (inserted / skipped-duplicate counts).
 */

const repoPath = process.argv[2];
if (!repoPath) {
  console.error("Usage: bun run scripts/import-legacy.ts -- <path-to-prototype-repo>");
  process.exit(1);
}

console.error("import-legacy is not implemented yet — see the TODO in this file.");
process.exit(1);
