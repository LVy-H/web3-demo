import { tmpdir } from "node:os";
import { join } from "node:path";
import { mkdtempSync, rmSync } from "node:fs";
import { randomUUID } from "node:crypto";

/**
 * Allocate a fresh temp directory + sqlite file path for a test. WAL mode
 * requires a real file (not :memory:), so each test gets an isolated file in
 * a unique temp dir; call the returned `cleanup()` in afterEach.
 */
export function tmpDbPath(): { path: string; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), "tessera-db-"));
  const path = join(dir, `${randomUUID()}.sqlite`);
  return {
    path,
    cleanup: () => {
      try {
        rmSync(dir, { recursive: true, force: true });
      } catch {
        // best-effort temp cleanup
      }
    },
  };
}
