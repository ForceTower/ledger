import { AsyncLocalStorage } from "node:async_hooks";

export interface ContextApi<T> {
  with<R>(value: T, fn: () => R): R;
  use(): T;
  hasValue(): boolean;
}

export function createContext<T>(contextName = "UnnamedContext"): ContextApi<T> {
  const storage = new AsyncLocalStorage<{ value: T }>();

  return {
    with<R>(value: T, fn: () => R): R {
      return storage.run({ value }, fn);
    },
    use(): T {
      const stored = storage.getStore();
      if (stored === undefined) {
        throw new Error(`ContextError: Cannot use() context "${contextName}" outside of its \`with\` scope.`);
      }
      return stored.value;
    },
    hasValue(): boolean {
      return storage.getStore() !== undefined;
    },
  };
}
