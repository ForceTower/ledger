import type { PricePoint, Purchase, PurchaseSummary } from "@ledger/shared-types";
import type { LedgerDb } from "../db";

export interface PurchaseFilters {
  from?: string;
  to?: string;
  store?: string;
}

export class PurchaseService {
  constructor(private readonly deps: { db: LedgerDb }) {}

  async list(filters: PurchaseFilters): Promise<PurchaseSummary[]> {
    // TODO: select from purchases (join stores), apply filters, aggregate category counts per purchase.
    return MOCK_SUMMARIES.filter((p) => {
      if (filters.store && p.store !== filters.store) return false;
      if (filters.from && p.date < filters.from) return false;
      if (filters.to && p.date > filters.to) return false;
      return true;
    });
  }

  async get(id: string): Promise<Purchase | null> {
    // TODO: select the purchase with jsonArrayFrom(items) + jsonArrayFrom(payments) + jsonObjectFrom(store).
    return id === MOCK_PURCHASE.id ? MOCK_PURCHASE : null;
  }

  async prices(barcode: string): Promise<PricePoint[]> {
    // TODO: select date, store name, unit_price, purchase slug from purchase_items where barcode matches.
    return MOCK_PRICES.filter((p) => p.purchaseId.length > 0 && barcode.length > 0);
  }
}

const MOCK_SUMMARIES: PurchaseSummary[] = [
  {
    id: "2026-03-26_atacadao_01",
    store: "Atacadão",
    date: "2026-03-26",
    time: "14:44:08",
    totalPaid: 208.75,
    itemCount: 10,
    categories: { meat: 4, grocery: 6 },
  },
];

const MOCK_PURCHASE: Purchase = {
  id: "2026-03-26_atacadao_01",
  date: "2026-03-26",
  time: "14:44:08",
  source: "nfce",
  store: {
    name: "Atacadão",
    legalName: "WMS SUPERMERCADOS DO BRASIL LTDA",
    cnpj: "93.209.765/0549-85",
    address: "Av Eduardo Froes da Mota, 5500, Sobradinho, Feira de Santana, BA",
  },
  receipt: { number: 141778, series: 501, accessKey: "29260393209765054985655010001417781048579178" },
  items: [
    {
      seq: 1,
      description: "Bov. Acém s/ Osso",
      code: "AR085698",
      barcode: null,
      quantity: 1.252,
      unit: "KG",
      unitPrice: 34.9,
      total: 43.69,
      category: "meat",
    },
    {
      seq: 2,
      description: "Bacon Fatiado Seara",
      code: "AR063548",
      barcode: "7894904203420",
      quantity: 1,
      unit: "UN",
      unitPrice: 23.9,
      total: 23.9,
      category: "meat",
    },
  ],
  totals: { itemCount: 10, gross: 211.75, discount: 3, totalPaid: 208.75 },
  payments: [{ code: 10, method: "Vale Alimentação", amount: 208.75 }],
  taxesTotal: 50.73,
};

const MOCK_PRICES: PricePoint[] = [
  { date: "2026-03-26", store: "Atacadão", unitPrice: 23.9, purchaseId: "2026-03-26_atacadao_01" },
];
