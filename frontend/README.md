# Frontend — ZK Voting Hub

React 19 web interface for the ZK Voting Hub platform.

## Stack

| Library | Version | Purpose |
|---------|---------|---------|
| React | 19 | UI framework |
| Vite | 8 | Build tool + dev server |
| TypeScript | 5.9 | Type safety |
| Wagmi | 3 | React hooks for Ethereum |
| Viem | 2 | Ethereum client library |
| TailwindCSS | 4 | Utility-first CSS |
| lucide-react | 0.460 | Icon library |
| @tanstack/react-query | 5 | Async state management |
| @semaphore-protocol/* | 4 | ZK identity, group, proof generation |
| @metamask/sdk | 0.33 | MetaMask wallet connector |

## Commands

```bash
npm install      # Install dependencies
npm run dev      # Start dev server at http://localhost:5173
npm run build    # TypeScript check + production build
npm run lint     # ESLint
```

## Pages

| Route | Component | Description |
|-------|-----------|-------------|
| `/` | `Home.tsx` | Dashboard — poll list, stats, quick actions |
| `/create` | `CreatePoll.tsx` | Create new poll (ZK or Blind type) |
| `/poll/:address` | `PollRouter.tsx` | Routes to `Poll.tsx` (ZK) or `BlindPoll.tsx` (Blind) |

## Features

- **Dark mode** toggle with localStorage persistence
- **Two voting modes**: Direct (wallet) and Relayer (no wallet)
- **ZK proof generation** runs client-side in browser (WASM)
- **Live results** with animated bar charts and auto-refresh
- **Admin panel** for poll lifecycle management and token generation
- **Error boundary** prevents white-screen crashes
- **Responsive** design with mobile navigation

## Key Hooks

| Hook | File | Purpose |
|------|------|---------|
| `useAllPolls` | `hooks/useRegistry.ts` | Read all polls from PollRegistry |
| `useCreatePoll` | `hooks/useRegistry.ts` | Create poll transaction |
| `usePollState/Options/Results` | `hooks/usePoll.ts` | Read poll data via IZkPoll interface |
| `useBlindPollWrite` | `hooks/useBlindPoll.ts` | Blind poll mutations |
| `useRelayVote` | `hooks/useRelay.ts` | Submit vote via relayer HTTP API |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_RPC_URL` | `http://127.0.0.1:8545` | Ethereum JSON-RPC endpoint |
| `VITE_RELAYER_URL` | `http://127.0.0.1:3001` | Relayer service URL |
