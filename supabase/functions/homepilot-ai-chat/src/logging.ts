export interface SafeLogEvent {
  operation: string;
  requestId: string | null;
  contractVersion: number;
  configVersion?: number;
  outcome: string;
  status: number;
  latencyMs?: number;
  retryCount?: number;
  inputChars?: number;
  historyMessages?: number;
  outputChars?: number;
  locale?: string;
}

export interface SafeLogger {
  info(event: SafeLogEvent): void;
  error(event: SafeLogEvent): void;
}

export const consoleSafeLogger: SafeLogger = {
  info: (event) => console.info(JSON.stringify(event)),
  error: (event) => console.error(JSON.stringify(event)),
};
