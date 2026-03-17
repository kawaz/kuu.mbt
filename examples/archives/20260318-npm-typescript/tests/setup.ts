import { loadKuu, type KuuParseFn } from "../src/kuu-bridge.js";

let cachedParse: KuuParseFn | null = null;

export async function getParser(): Promise<KuuParseFn> {
  if (!cachedParse) {
    cachedParse = await loadKuu();
  }
  return cachedParse;
}
