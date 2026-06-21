import type { Account } from "../db";

/**
 * Express `Request` augmentation: `requireConvener` attaches the authenticated
 * convener Account here after a successful bearer-token match, so downstream
 * route handlers can read `req.account` with full type safety.
 */
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      account?: Account;
    }
  }
}

export {};
