// Tessera server — auth module public API (convener bearer auth, §9/§10).
//
// Route layers import from here, never from sibling files directly.
// The Express.Request.account augmentation lives in ./express.d.ts — an ambient
// `declare global` picked up via the tsconfig "src" include. It must NOT be
// imported: a runtime `require()` of a .d.ts crashes ts-node / `node dist`.

export {
  hashToken,
  bootstrapAdmin,
  mintConvenerToken,
  requireConvener,
} from "./auth";
