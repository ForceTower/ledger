import { OTLPLogExporter } from "@opentelemetry/exporter-logs-otlp-http";
import { resourceFromAttributes } from "@opentelemetry/resources";
import { BatchLogRecordProcessor, LoggerProvider } from "@opentelemetry/sdk-logs";
import { ATTR_SERVICE_NAME } from "@opentelemetry/semantic-conventions";
import { logs as logsApi } from "@opentelemetry/api-logs";

const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT?.trim();
const serviceName = process.env.OTEL_SERVICE_NAME?.trim() ?? "ledger-api";
const headers = parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS);

let provider: LoggerProvider | undefined;

export const otelEnabled = Boolean(endpoint);

if (endpoint) {
  const exporter = new OTLPLogExporter({ url: `${endpoint.replace(/\/$/, "")}/v1/logs`, headers });
  provider = new LoggerProvider({
    resource: resourceFromAttributes({ [ATTR_SERVICE_NAME]: serviceName }),
    processors: [new BatchLogRecordProcessor(exporter)],
  });
  logsApi.setGlobalLoggerProvider(provider);
}

export const shutdownOtel = async (): Promise<void> => {
  if (provider) await provider.shutdown();
};

function parseHeaders(raw: string | undefined): Record<string, string> {
  if (!raw) return {};
  const result: Record<string, string> = {};
  for (const pair of raw.split(",")) {
    const idx = pair.indexOf("=");
    if (idx === -1) continue;
    result[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
  }
  return result;
}
