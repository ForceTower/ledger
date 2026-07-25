/**
 * Zod schemas for the file-based prototype's JSON (Portuguese field names). Shared by
 * import-legacy.ts (prototype → Postgres) and anonymize-legacy.ts (prototype → data/sample).
 */

import { z } from "zod";

export const legacyCategorySchema = z.enum([
  "hortifruti",
  "carnes",
  "frios_laticinios",
  "padaria",
  "mercearia",
  "bebidas",
  "doces_snacks",
  "congelados",
  "limpeza",
  "higiene",
  "pet",
  "bazar_utilidades",
  "outros",
]);

export const legacyItemSchema = z.object({
  seq: z.number().int(),
  descricao: z.string(),
  codigo: z.string(),
  codigo_barras: z.string().nullish(),
  quantidade: z.number(),
  unidade: z.string(),
  valor_unitario: z.number(),
  valor_total: z.number(),
  categoria: legacyCategorySchema,
});

export const legacyPaymentSchema = z.object({
  forma: z.string(),
  codigo: z.union([z.number(), z.string()]).nullish(),
  valor: z.number(),
  troco: z.number().optional(),
});

export const legacyPurchaseSchema = z.object({
  id: z.string(),
  data: z.string(),
  hora: z.string(),
  origem: z.enum(["nfce", "manual"]),
  loja: z.object({ nome: z.string(), cnpj: z.string(), endereco: z.string() }),
  nfce: z.object({ numero: z.number().int(), serie: z.number().int(), chave_acesso: z.string() }).nullable(),
  itens: z.array(legacyItemSchema).min(1),
  totais: z.object({
    qtd_itens: z.number(),
    valor_bruto: z.number(),
    descontos: z.number(),
    valor_pago: z.number(),
  }),
  pagamento: z.array(legacyPaymentSchema),
  tributos_totais: z.number().nullable(),
  fonte_html: z.string().optional(),
});

export const legacyTripSchema = z.object({
  data: z.string(),
  trajetos: z.array(
    z.object({
      meio: z.string(),
      destinos: z.array(z.string()),
      distancia_km: z.number().nullable(),
      custo_combustivel: z.number().nullable(),
      custo_estacionamento: z.number().nullable(),
      custo_total: z.number().nullable(),
      notas: z.string().nullish(),
    }),
  ),
});

export const legacyDonationSchema = z.object({
  data: z.string(),
  compra_origem: z.string().optional(),
  doacoes: z.array(
    z.object({
      destinatario: z.string(),
      itens: z.array(
        z.object({
          descricao: z.string(),
          codigo: z.string(),
          quantidade: z.number(),
          unidade: z.string(),
          valor_unitario: z.number(),
          valor_total: z.number(),
          ref_seq: z.number().int(),
          ref_compra: z.string().optional(),
        }),
      ),
      valor_total: z.number(),
    }),
  ),
  valor_total_doacoes: z.number(),
});

export type LegacyItem = z.infer<typeof legacyItemSchema>;
export type LegacyPurchase = z.infer<typeof legacyPurchaseSchema>;
export type LegacyTrip = z.infer<typeof legacyTripSchema>;
export type LegacyDonation = z.infer<typeof legacyDonationSchema>;
