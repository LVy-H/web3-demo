export const MIGRATIONS: ReadonlyArray<{ id: number; sql: string }> = [
  {
    id: 1,
    sql: `
      CREATE TABLE tenants (
        slug            TEXT PRIMARY KEY,
        display_name    TEXT NOT NULL,
        status          TEXT NOT NULL,
        container_name  TEXT NOT NULL,
        volume_name     TEXT NOT NULL,
        internal_port   INTEGER NOT NULL,
        key_fingerprint TEXT,
        created_at      INTEGER NOT NULL
      );
      CREATE TABLE operator_admins (
        id         TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE _migrations (id INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL);
    `,
  },
];
