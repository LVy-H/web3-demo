import { createHash } from "node:crypto";
export function fingerprintOfPem(pem: string): string {
  return createHash("sha256").update(pem).digest("hex");
}
export async function fetchFingerprint(baseUrl: string, fetchImpl: typeof fetch = fetch): Promise<string> {
  const res = await fetchImpl(`${baseUrl}/key`);
  if (!res.ok) throw new Error(`/key returned ${res.status}`);
  const body = (await res.json()) as { serverPubKeyPem?: string };
  if (!body.serverPubKeyPem) throw new Error("/key missing serverPubKeyPem");
  return fingerprintOfPem(body.serverPubKeyPem);
}
