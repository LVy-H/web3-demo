# Tessera Docs

Living references for the current Tessera product: a self-hosted verifiable
bulletin board plus one Flutter client.

The old on-chain/Semaphore/relayer documentation is retained only in
`docs/archive/`, `docs/superpowers/`, and the project changelog where historical
context is useful. Current runbooks should point to the REST server, Flutter app,
and multi-tenant control plane.

## Current Map

```text
docs/
├── architecture/
│   ├── system-overview.md       Current component/trust model overview
│   ├── module-m1-anon-voting.md Current single-choice/open-secret method note
│   ├── module-approval.md       Current approval method note
│   ├── module-ranked.md         Current ranked/IRV method note
│   ├── module-quadratic.md      Current quadratic method note
│   ├── module-survey.md         Current survey method note
│   └── module-airdrop.md        Retired airdrop note
├── project/
│   ├── STATUS.md                Current project status
│   ├── ROADMAP.md               Current 1.0 roadmap
│   ├── TEST-COVERAGE.md         Current test map
│   └── RELEASING.md             Release process
├── standards/
│   ├── client-conventions.md    Flutter/client conventions
│   ├── ux-design-principles.md  Product UX principles
│   └── visual-design-guide.md   Visual language
└── archive/                     Retired historical material
```

## Runbooks

- Local demo: `./demo.sh up`
- Server only: `./dev-stack.sh up`
- Self-hosting: [`../deploy/README.md`](../deploy/README.md)
- Multi-tenant localhost: [`../deploy/multi-tenant/README.md`](../deploy/multi-tenant/README.md)
