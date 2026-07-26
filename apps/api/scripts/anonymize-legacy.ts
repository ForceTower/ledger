/**
 * Generates the anonymized fixture set in data/sample from a copy of the file-based prototype.
 *
 * Usage: bun run scripts/anonymize-legacy.ts <path-to-prototype-repo> [out-dir]
 *
 * Output keeps the legacy layout (dados/{compras,transporte,doacoes}/*.json) so
 * import-legacy.ts can load it unchanged. What changes vs the source:
 *   - stores get fake names/CNPJs/addresses (valid check digits, rebuilt NFC-e access keys)
 *   - purchase slugs are rebuilt from the fake store, donation references remapped to match
 *   - unit prices are jittered ±10% and every total/payment recomputed to stay consistent
 *   - donation recipients come from a fake pool; receipt HTML is dropped
 *
 * Deterministic: identities and jitter are seeded from stable keys, so re-runs produce
 * identical output and no real name ever needs to appear in this file or in git history.
 */

import { promises as fs } from "node:fs";
import path from "node:path";
import {
  type LegacyDonation,
  type LegacyPurchase,
  type LegacyTrip,
  legacyDonationSchema,
  legacyPurchaseSchema,
  legacyTripSchema,
} from "./legacy-schema";

const MARKETS = [
  { legal: "COMERCIAL BOA PRACA LTDA", brand: "Mercado Boa Praça", street: "Avenida das Palmeiras, 1200, Centro" },
  { legal: "SUPERMERCADO ESTRELA DO NORTE LTDA", brand: "Estrela do Norte", street: "Rua do Comércio, 45, Kalilândia" },
  {
    legal: "ATACAREJO PONTO CERTO S/A",
    brand: "Ponto Certo Atacarejo",
    street: "Avenida Getúlio Vargas, 3300, Ponto Central",
  },
  {
    legal: "DISTRIBUIDORA HORIZONTE AZUL LTDA",
    brand: "Horizonte Azul",
    street: "Rua das Mangueiras, 78, Queimadinha",
  },
  {
    legal: "MERCADINHO SAO CRISTOVAO EIRELI",
    brand: "Mercadinho São Cristóvão",
    street: "Rua da Aurora, 210, Serraria Brasil",
  },
  {
    legal: "SUPERMERCADO PRIMAVERA LTDA",
    brand: "Supermercado Primavera",
    street: "Avenida João Durval, 950, Santa Mônica",
  },
  { legal: "COMERCIO DE ALIMENTOS VALE VERDE LTDA", brand: "Vale Verde", street: "Rua Barão de Cotegipe, 33, Centro" },
  {
    legal: "ATACADO BOM PRECO S/A",
    brand: "Bom Preço Atacado",
    street: "Avenida Presidente Dutra, 2100, Santo Antônio",
  },
  {
    legal: "EMPORIO DA SERRA ALIMENTOS LTDA",
    brand: "Empório da Serra",
    street: "Rua Intendente Rui, 18, Capuchinhos",
  },
  { legal: "REDE ECONOMIA SUPERMERCADOS LTDA", brand: "Rede Economia", street: "Avenida Maria Quitéria, 1500, Centro" },
] as const;

const VENDORS = [
  "Barraca da Dona Rosa",
  "Feira do Produtor",
  "Hortifruti do Seu Zé",
  "Ovos do Sítio Alegria",
  "Verduras da Praça",
  "Peixaria do Cais",
  "Sacolão do Bairro",
  "Frutas do Vale",
  "Tempero da Terra",
  "Água Mineral Fonte Clara",
  "Granja Bela Vista",
  "Padaria Pão Quente",
] as const;

const RECIPIENTS = [
  "Igreja do bairro",
  "Casa de Apoio Luz",
  "Dona Marta",
  "Seu Antônio",
  "Abrigo São Lucas",
  "Creche Sementinha",
  "Associação Comunitária",
  "Vizinhança",
] as const;

const CITY = "Feira de Santana, BA";

function fnv1a(str: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    hash ^= str.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function mulberry32(seed: number): () => number {
  let state = seed;
  return () => {
    state |= 0;
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rngFor = (key: string) => mulberry32(fnv1a(`ledger-sample:${key}`));
const randomInt = (rng: () => number, min: number, max: number) => min + Math.floor(rng() * (max - min + 1));
const round2 = (value: number) => Math.round(value * 100) / 100;
const jitter = (rng: () => number) => 0.9 + rng() * 0.2;

function pick<T>(pool: readonly T[], index: number): T {
  const value = pool[index % pool.length];
  if (value === undefined) throw new Error("empty pool");
  return value;
}

const strip = (value: string) =>
  value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
const normalize = (value: string) => strip(value).replace(/[^a-z0-9]+/g, "");
const tokenize = (value: string) =>
  strip(value)
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "");

function cnpjCheckDigits(base12: string): string {
  const digitFor = (digits: string, weights: number[]) => {
    let sum = 0;
    for (let i = 0; i < digits.length; i++) sum += Number(digits[i]) * (weights[i] ?? 0);
    const rem = sum % 11;
    return rem < 2 ? 0 : 11 - rem;
  };
  const d1 = digitFor(base12, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  const d2 = digitFor(base12 + d1, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  return `${d1}${d2}`;
}

function fakeCnpj(rng: () => number): string {
  let base = "";
  for (let i = 0; i < 8; i++) base += randomInt(rng, 0, 9);
  const full = `${base}0001${cnpjCheckDigits(`${base}0001`)}`;
  return `${full.slice(0, 2)}.${full.slice(2, 5)}.${full.slice(5, 8)}/${full.slice(8, 12)}-${full.slice(12)}`;
}

/** Layout: cUF(2) AAMM(4) CNPJ(14) mod(2) serie(3) nNF(9) tpEmis(1) cNF(8) cDV(1). */
function fakeAccessKey(rng: () => number, date: string, cnpj: string, serie: number, numero: number): string {
  const digits = cnpj.replace(/\D/g, "").padStart(14, "0");
  const yymm = date.slice(2, 4) + date.slice(5, 7);
  let cnf = "";
  for (let i = 0; i < 8; i++) cnf += randomInt(rng, 0, 9);
  const key43 = `29${yymm}${digits}65${String(serie).padStart(3, "0")}${String(numero).padStart(9, "0")}1${cnf}`;
  const weights = [2, 3, 4, 5, 6, 7, 8, 9];
  let sum = 0;
  for (let i = 0; i < key43.length; i++) sum += Number(key43[key43.length - 1 - i]) * (weights[i % 8] ?? 0);
  const rem = sum % 11;
  return key43 + (rem < 2 ? 0 : 11 - rem);
}

interface FakeStore {
  nome: string;
  brand: string;
  cnpj: string | null;
  endereco: string;
  token: string;
}

class StoreRegistry {
  private readonly byKey = new Map<string, FakeStore>();
  private readonly byOrigToken = new Map<string, FakeStore>();
  private readonly usedPoolIdx = { market: new Set<number>(), vendor: new Set<number>() };
  private readonly usedTokens = new Set<string>();

  resolve(loja: LegacyPurchase["loja"], origem: LegacyPurchase["origem"], origToken: string): FakeStore {
    const cnpjDigits = loja.cnpj.replace(/\D/g, "");
    const key = cnpjDigits || `name:${normalize(loja.nome)}`;
    let store = this.byKey.get(key);
    if (!store) {
      store = origem === "nfce" ? this.createMarket(key, loja) : this.createVendor(key, loja);
      this.byKey.set(key, store);
    }
    if (origToken && !this.byOrigToken.has(origToken)) this.byOrigToken.set(origToken, store);
    return store;
  }

  /** Trips reference stores by display name; reuse the purchase mapping when one matches. */
  resolveDestination(destino: string): string {
    const norm = normalize(destino);
    for (const [origToken, store] of this.byOrigToken) {
      const tokenNorm = normalize(origToken);
      if (norm.includes(tokenNorm) || tokenNorm.includes(norm)) return store.brand;
    }
    const key = `name:${norm}`;
    let store = this.byKey.get(key);
    if (!store) {
      store = this.createMarket(key, { nome: destino, cnpj: "", endereco: "" });
      this.byKey.set(key, store);
    }
    return store.brand;
  }

  private createMarket(key: string, loja: LegacyPurchase["loja"]): FakeStore {
    const rng = rngFor(`store:${key}`);
    const index = this.claimIndex("market", MARKETS.length, rng);
    const market = pick(MARKETS, index);
    return {
      nome: market.legal,
      brand: market.brand,
      cnpj: loja.cnpj ? fakeCnpj(rng) : null,
      endereco: loja.endereco ? `${market.street}, ${CITY}` : "",
      token: this.claimToken(tokenize(market.brand)),
    };
  }

  private createVendor(key: string, loja: LegacyPurchase["loja"]): FakeStore {
    const rng = rngFor(`store:${key}`);
    const index = this.claimIndex("vendor", VENDORS.length, rng);
    const name = pick(VENDORS, index);
    return {
      nome: name,
      brand: name,
      cnpj: loja.cnpj ? fakeCnpj(rng) : null,
      endereco: loja.endereco ? `Feira livre do Centro, ${CITY}` : "",
      token: this.claimToken(tokenize(name)),
    };
  }

  private claimIndex(kind: "market" | "vendor", poolSize: number, rng: () => number): number {
    const used = this.usedPoolIdx[kind];
    let index = randomInt(rng, 0, poolSize - 1);
    for (let step = 0; step < poolSize && used.has(index); step++) index = (index + 1) % poolSize;
    used.add(index);
    return index;
  }

  private claimToken(base: string): string {
    let token = base;
    for (let n = 2; this.usedTokens.has(token); n++) token = `${base}_${n}`;
    this.usedTokens.add(token);
    return token;
  }
}

interface AnonymizedItem {
  unitPrice: number;
  descricao: string;
}

interface AnonymizedPurchase {
  purchase: LegacyPurchase;
  itemBySeq: Map<number, AnonymizedItem>;
}

const SCRUB_STOPWORDS = new Set(["LTDA", "EIRELI"]);

/**
 * Item descriptions can embed the store's own brand (store-branded bags, private-label SKUs).
 * Replace any word of the real store name or slug token with the fake brand — computed at
 * runtime so no real name has to appear in this (public) file.
 */
function makeDescriptionScrubber(loja: LegacyPurchase["loja"], origToken: string, brand: string) {
  const tokens = new Set<string>();
  for (const word of strip(loja.nome)
    .toUpperCase()
    .split(/[^A-Z0-9]+/)) {
    if (word.length >= 5 && !SCRUB_STOPWORDS.has(word)) tokens.add(word);
  }
  for (const word of origToken.toUpperCase().split("_")) {
    if (word.length >= 5) tokens.add(word);
  }
  if (tokens.size === 0) return (descricao: string) => descricao;
  const pattern = new RegExp([...tokens].join("|"), "gi");
  const replacement = strip(brand).toUpperCase();
  return (descricao: string) => descricao.replace(pattern, replacement);
}

function anonymizePurchase(
  legacy: LegacyPurchase,
  registry: StoreRegistry,
  usedSlugs: Set<string>,
): AnonymizedPurchase {
  const origToken = legacy.id.replace(/^\d{4}-\d{2}-\d{2}_/, "").replace(/_\d+$/, "");
  const store = registry.resolve(legacy.loja, legacy.origem, origToken);
  const rng = rngFor(`purchase:${legacy.id}`);
  const scrubDescription = makeDescriptionScrubber(legacy.loja, origToken, store.brand);

  let suffix = Number(legacy.id.match(/_(\d+)$/)?.[1] ?? "1");
  let slug = `${legacy.data}_${store.token}_${String(suffix).padStart(2, "0")}`;
  while (usedSlugs.has(slug)) {
    suffix++;
    slug = `${legacy.data}_${store.token}_${String(suffix).padStart(2, "0")}`;
  }
  usedSlugs.add(slug);

  const itemBySeq = new Map<number, AnonymizedItem>();
  const itens = legacy.itens.map((item) => {
    const unitPrice = Math.max(0.01, round2(item.valor_unitario * jitter(rng)));
    const descricao = scrubDescription(item.descricao);
    itemBySeq.set(item.seq, { unitPrice, descricao });
    return { ...item, descricao, valor_unitario: unitPrice, valor_total: round2(item.quantidade * unitPrice) };
  });

  const grossTotal = round2(itens.reduce((sum, item) => sum + item.valor_total, 0));
  const discount = Math.min(round2(legacy.totais.descontos), grossTotal);
  const paidTotal = round2(grossTotal - discount);
  const scale = legacy.totais.valor_pago > 0 ? paidTotal / legacy.totais.valor_pago : 1;

  const pagamento = legacy.pagamento.map((payment) => ({
    ...payment,
    valor: round2(payment.valor * scale),
    ...(payment.troco === undefined ? {} : { troco: round2(payment.troco * scale) }),
  }));
  const last = pagamento.at(-1);
  if (last) {
    const settled = pagamento.reduce((sum, p) => sum + p.valor - (p.troco ?? 0), 0);
    last.valor = round2(last.valor + paidTotal - settled);
  }

  const numero = randomInt(rng, 100000, 999999);
  const purchase: LegacyPurchase = {
    id: slug,
    data: legacy.data,
    hora: legacy.hora,
    origem: legacy.origem,
    loja: { nome: store.nome, cnpj: store.cnpj ?? "", endereco: store.endereco },
    nfce: legacy.nfce
      ? {
          numero,
          serie: legacy.nfce.serie,
          chave_acesso: fakeAccessKey(rng, legacy.data, store.cnpj ?? "", legacy.nfce.serie, numero),
        }
      : null,
    itens,
    totais: {
      qtd_itens: legacy.totais.qtd_itens,
      valor_bruto: grossTotal,
      descontos: discount,
      valor_pago: paidTotal,
    },
    pagamento,
    tributos_totais: legacy.tributos_totais === null ? null : round2(legacy.tributos_totais * scale),
  };
  return { purchase, itemBySeq };
}

function anonymizeDonation(
  legacy: LegacyDonation,
  slugMap: Map<string, string>,
  purchasesByOrigSlug: Map<string, AnonymizedPurchase>,
): LegacyDonation {
  const recipientRng = rngFor(`recipients:${legacy.data}`);
  const usedRecipients = new Set<number>();
  const claimRecipient = () => {
    let index = randomInt(recipientRng, 0, RECIPIENTS.length - 1);
    for (let step = 0; step < RECIPIENTS.length && usedRecipients.has(index); step++) {
      index = (index + 1) % RECIPIENTS.length;
    }
    usedRecipients.add(index);
    return pick(RECIPIENTS, index);
  };

  const doacoes = legacy.doacoes.map((donation) => {
    const itens = donation.itens.map((item) => {
      const origSlug = item.ref_compra ?? legacy.compra_origem;
      const origin = origSlug ? purchasesByOrigSlug.get(origSlug)?.itemBySeq.get(item.ref_seq) : undefined;
      const unitPrice =
        origin?.unitPrice ??
        Math.max(
          0.01,
          round2(
            (item.valor_total / Math.max(item.quantidade, 0.01)) *
              jitter(rngFor(`donation:${legacy.data}:${item.ref_seq}`)),
          ),
        );
      return {
        ...item,
        descricao: origin?.descricao ?? item.descricao,
        ...(item.ref_compra ? { ref_compra: slugMap.get(item.ref_compra) ?? undefined } : {}),
        valor_unitario: unitPrice,
        valor_total: round2(item.quantidade * unitPrice),
      };
    });
    return {
      destinatario: claimRecipient(),
      itens,
      valor_total: round2(itens.reduce((sum, item) => sum + item.valor_total, 0)),
    };
  });

  return {
    data: legacy.data,
    ...(legacy.compra_origem ? { compra_origem: slugMap.get(legacy.compra_origem) ?? undefined } : {}),
    doacoes,
    valor_total_doacoes: round2(doacoes.reduce((sum, donation) => sum + donation.valor_total, 0)),
  };
}

/** Free-text notes could carry anything; only these pass through to the public fixtures. */
const SAFE_NOTES = new Set(["Ida", "Volta", "Ida e volta"]);

function anonymizeTrip(legacy: LegacyTrip, registry: StoreRegistry): LegacyTrip {
  const rng = rngFor(`trip:${legacy.data}`);
  return {
    data: legacy.data,
    trajetos: legacy.trajetos.map((leg) => {
      const fuel = leg.custo_combustivel === null ? null : round2(leg.custo_combustivel * jitter(rng));
      const parking = leg.custo_estacionamento === null ? null : round2(leg.custo_estacionamento * jitter(rng));
      const partsTotal = (fuel ?? 0) + (parking ?? 0);
      const total =
        fuel !== null || parking !== null
          ? round2(partsTotal)
          : leg.custo_total === null
            ? null
            : round2(leg.custo_total * jitter(rng));
      return {
        ...leg,
        destinos: leg.destinos.map((destino) => registry.resolveDestination(destino)),
        distancia_km: leg.distancia_km === null ? null : Math.round(leg.distancia_km * jitter(rng) * 10) / 10,
        custo_combustivel: fuel,
        custo_estacionamento: parking,
        custo_total: total,
        notas: leg.notas != null && SAFE_NOTES.has(leg.notas) ? leg.notas : null,
      };
    }),
  };
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

async function writeJson(file: string, value: unknown): Promise<void> {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

async function run(repoRoot: string, outRoot: string): Promise<void> {
  const registry = new StoreRegistry();
  const usedSlugs = new Set<string>();
  const slugMap = new Map<string, string>();
  const purchasesByOrigSlug = new Map<string, AnonymizedPurchase>();

  await fs.rm(path.join(outRoot, "dados"), { recursive: true, force: true });

  const purchaseFiles = await listJsonFiles(path.join(repoRoot, "dados/compras"));
  for (const file of purchaseFiles) {
    const legacy = legacyPurchaseSchema.parse(JSON.parse(await fs.readFile(file, "utf8")));
    const anonymized = anonymizePurchase(legacy, registry, usedSlugs);
    slugMap.set(legacy.id, anonymized.purchase.id);
    purchasesByOrigSlug.set(legacy.id, anonymized);
    const output = legacyPurchaseSchema.parse(anonymized.purchase);
    await writeJson(path.join(outRoot, "dados/compras", `${output.id}.json`), output);
  }
  console.log(`purchases: ${purchaseFiles.length} anonymized`);

  const donationFiles = await listJsonFiles(path.join(repoRoot, "dados/doacoes"));
  for (const file of donationFiles) {
    const legacy = legacyDonationSchema.parse(JSON.parse(await fs.readFile(file, "utf8")));
    const output = legacyDonationSchema.parse(anonymizeDonation(legacy, slugMap, purchasesByOrigSlug));
    await writeJson(path.join(outRoot, "dados/doacoes", path.basename(file)), output);
  }
  console.log(`donations: ${donationFiles.length} anonymized`);

  const tripFiles = await listJsonFiles(path.join(repoRoot, "dados/transporte"));
  for (const file of tripFiles) {
    const legacy = legacyTripSchema.parse(JSON.parse(await fs.readFile(file, "utf8")));
    const output = legacyTripSchema.parse(anonymizeTrip(legacy, registry));
    await writeJson(path.join(outRoot, "dados/transporte", path.basename(file)), output);
  }
  console.log(`trips: ${tripFiles.length} anonymized`);
}

const repoPath = process.argv[2];
if (!repoPath) {
  console.error("Usage: bun run scripts/anonymize-legacy.ts <path-to-prototype-repo> [out-dir]");
  process.exit(1);
}
const outPath = process.argv[3] ?? path.resolve(import.meta.dir, "../../../data/sample");

await run(path.resolve(repoPath), path.resolve(outPath));
