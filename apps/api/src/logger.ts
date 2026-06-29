import { OpenTelemetryTransport } from "@loglayer/transport-opentelemetry";
import { PinoTransport } from "@loglayer/transport-pino";
import { LogLayer, type LogLayerTransport } from "loglayer";
import pino from "pino";
import { serializeError } from "serialize-error";
import { otelEnabled } from "./otel";
import { createContext } from "./utils/context";

const p = pino({ level: "trace" });

export const makeLogger = (): LogLayer => {
  const transports: LogLayerTransport[] = [new PinoTransport({ enabled: true, logger: p })];
  if (otelEnabled) {
    transports.push(new OpenTelemetryTransport({ enabled: true }));
  }
  return new LogLayer({
    errorSerializer: serializeError,
    transport: transports,
  });
};

export const loggerContext = createContext<LogLayer>("Logger");

const defaultLogger = makeLogger();

export const useLog = (): LogLayer => {
  if (loggerContext.hasValue()) return loggerContext.use();
  return defaultLogger;
};
