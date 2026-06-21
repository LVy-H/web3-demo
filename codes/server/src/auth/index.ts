// Tessera server — auth module public API (convener bearer auth, §9/§10).
//
// Route layers import from here, never from sibling files directly.
import "./express.d"; // registers the Express.Request.account augmentation

export {
  hashToken,
  bootstrapAdmin,
  mintConvenerToken,
  requireConvener,
} from "./auth";
