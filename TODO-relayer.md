# TODO: Relayer Service — Gasless Anonymous Voting

## Mục tiêu

Xây dựng **Relayer Service** (backend trung gian) để voter **không cần connect ví MetaMask**, chỉ cần:
1. Nhận invite token từ admin
2. Paste token vào web → hệ thống tạo ZK proof trong browser
3. Proof được gửi tới Relayer → Relayer ký và gửi transaction lên blockchain thay voter

**Kết quả**: Voter hoàn toàn ẩn danh — không cần ví, không cần ETH, không có on-chain footprint.

---

## Tại sao cần Relayer?

| Hiện tại (có ví) | Với Relayer (không cần ví) |
|---|---|
| Voter phải cài MetaMask | Voter chỉ cần browser |
| Voter phải có ETH trả gas | Admin trả gas qua Relayer |
| Wallet address xuất hiện trong tx | Relayer address xuất hiện (không phải voter) |
| UX phức tạp: connect → switch network → approve tx | UX đơn giản: paste token → chọn option → vote |

**Tính ẩn danh vẫn đảm bảo** vì:
- ZK proof chứng minh voter thuộc group mà không tiết lộ danh tính
- Relayer không biết voter là ai — chỉ forward proof
- Smart contract verify proof on-chain, không cần biết ai gửi transaction

---

## Kiến trúc tổng quan

```
┌──────────────┐     HTTP POST      ┌──────────────┐     On-chain TX      ┌──────────────┐
│   Browser    │  ───────────────>  │   Relayer    │  ───────────────>   │  Hardhat /   │
│  (Frontend)  │   {vote, proof,   │  (Express)   │   castVote(...)    │  Blockchain  │
│              │    pollAddress}    │              │   signed by        │              │
│ ZK proof     │                    │ Hot wallet   │   relayer wallet   │ ZkAnonVoting │
│ generated    │  <───────────────  │ pays gas     │  <───────────────  │ verifies ZKP │
│ client-side  │   {txHash, ok}    │              │   tx receipt       │              │
└──────────────┘                    └──────────────┘                    └──────────────┘
```

---

## Cấu trúc thư mục cần tạo

```
web3-demo/
├── relayer/                     ← THƯ MỤC MỚI
│   ├── package.json
│   ├── tsconfig.json
│   ├── Dockerfile
│   ├── src/
│   │   ├── index.ts             ← Entry point: Express server
│   │   ├── relay.ts             ← Core logic: nhận proof, gửi tx
│   │   ├── wallet.ts            ← Hot wallet management
│   │   ├── validation.ts        ← Validate request trước khi relay
│   │   └── config.ts            ← Environment config
│   └── .env.example
├── docker-compose.yml           ← CẬP NHẬT: thêm relayer service
├── contracts/                   ← KHÔNG THAY ĐỔI
└── frontend/
    ├── src/
    │   ├── config.ts            ← CẬP NHẬT: thêm RELAYER_URL
    │   └── pages/
    │       └── Poll.tsx          ← CẬP NHẬT: thêm mode relay (gửi qua HTTP thay vì wallet)
    └── ...
```

---

## Các tác vụ chi tiết

### Phase 1: Relayer Backend

#### Task 1.1: Khởi tạo project relayer
- Tạo `relayer/package.json` với dependencies:
  - `express` — HTTP server
  - `cors` — cho phép frontend gọi cross-origin
  - `ethers` (v6) — tương tác blockchain, ký transaction
  - `dotenv` — đọc environment variables
  - `typescript`, `ts-node`, `@types/express`, `@types/cors` — dev deps
- Tạo `relayer/tsconfig.json`
- Tạo `relayer/.env.example`:
  ```env
  RPC_URL=http://127.0.0.1:8545
  RELAYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
  PORT=3001
  ```

#### Task 1.2: Xây dựng `src/config.ts`
```ts
// Đọc env vars, export typed config
export const config = {
    rpcUrl: process.env.RPC_URL || 'http://127.0.0.1:8545',
    privateKey: process.env.RELAYER_PRIVATE_KEY || '0xac09...', // Hardhat Account #0
    port: Number(process.env.PORT) || 3001,
    maxGasLimit: 5_000_000n,
}
```

#### Task 1.3: Xây dựng `src/wallet.ts`
```ts
// Tạo ethers.Wallet từ private key
// Connect tới JSON-RPC provider
// Export hàm getRelayerWallet() và getBalance()
```

#### Task 1.4: Xây dựng `src/validation.ts`
Validate request body trước khi relay:
- `pollAddress`: phải là valid Ethereum address
- `vote`: phải là uint256 (số nguyên >= 0)
- `proof`: phải có đủ 6 fields (merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, points)
- `proof.points`: phải là array 8 phần tử
- `proof.message` phải bằng `vote`
- `proof.scope` phải bằng `uint256(uint160(pollAddress))`

#### Task 1.5: Xây dựng `src/relay.ts` — core logic
```ts
import { ethers } from 'ethers';
import ZkAnonVotingABI from './abi/ZkAnonVoting.json';

export async function relayCastVote(
    wallet: ethers.Wallet,
    pollAddress: string,
    vote: number,
    proof: SemaphoreProof
): Promise<string> {
    const contract = new ethers.Contract(pollAddress, ZkAnonVotingABI.abi, wallet);

    const tx = await contract.castVote(vote, proof, {
        gasLimit: 5_000_000n,
    });

    const receipt = await tx.wait();
    return receipt.hash;
}

// Tương tự cho relayClaimAirdrop()
export async function relayClaimAirdrop(
    wallet: ethers.Wallet,
    airdropAddress: string,
    receiver: string,
    proof: SemaphoreProof
): Promise<string> { ... }
```

#### Task 1.6: Xây dựng `src/index.ts` — Express server
```
POST /api/relay/vote
  Body: { pollAddress, vote, proof }
  Response: { success: true, txHash: "0x..." }
  Errors: 400 (validation), 500 (tx revert)

POST /api/relay/claim-airdrop
  Body: { airdropAddress, receiver, proof }
  Response: { success: true, txHash: "0x..." }

GET /api/relay/status
  Response: { balance: "9999.5", address: "0xf39F..." }
```

#### Task 1.7: Tạo `relayer/Dockerfile`
```dockerfile
FROM node:lts
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3001
CMD ["npx", "ts-node", "src/index.ts"]
```

---

### Phase 2: Cập nhật Frontend

#### Task 2.1: Thêm RELAYER_URL vào config
- `frontend/src/config.ts`: thêm `export const RELAYER_URL = import.meta.env.VITE_RELAYER_URL || 'http://127.0.0.1:3001'`

#### Task 2.2: Tạo `frontend/src/hooks/useRelay.ts`
```ts
// Hook gửi vote qua relayer thay vì wallet
export function useRelayVote() {
    async function relayVote(pollAddress, vote, proof) {
        const res = await fetch(`${RELAYER_URL}/api/relay/vote`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ pollAddress, vote, proof }),
        });
        if (!res.ok) throw new Error((await res.json()).error);
        return (await res.json()).txHash;
    }
    return { relayVote };
}
```

#### Task 2.3: Cập nhật `Poll.tsx` — thêm Relay mode
- Thêm toggle/button "Vote without wallet (via Relayer)"
- Khi voter KHÔNG connect ví:
  - Vẫn cho nhập invite token và chọn option
  - ZK proof vẫn được generate client-side (WASM)
  - Thay vì gọi `writeContractAsync(castVote)`, gọi `relayVote()`
  - Hiển thị txHash khi thành công
- Khi voter CÓ connect ví:
  - Giữ nguyên flow hiện tại (voter tự gửi tx)
  - Hoặc cho voter chọn dùng relayer

#### Task 2.4: Cập nhật UI cho voter không có ví
- Ẩn nút "Connect Wallet" requirement cho vote flow
- Hiển thị: "Your vote will be submitted anonymously via relayer"
- Thêm trạng thái loading khi relayer đang gửi tx

---

### Phase 3: Docker Integration

#### Task 3.1: Cập nhật `docker-compose.yml`
```yaml
relayer:
  build:
    context: ./relayer
  ports:
    - "3001:3001"
  environment:
    - RPC_URL=http://contracts:8545
    - RELAYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    - PORT=3001
  depends_on:
    - contracts
```

Cập nhật frontend service:
```yaml
frontend:
  environment:
    - VITE_RELAYER_URL=http://127.0.0.1:3001   # browser gọi từ host
```

#### Task 3.2: Copy ABI files sang relayer
- Cập nhật `contracts/scripts/copyAbis.ts` để cũng copy ABI sang `relayer/src/abi/`
- Hoặc relayer đọc ABI từ shared volume

---

### Phase 4: Bảo mật Relayer

#### Task 4.1: Rate limiting
- Giới hạn mỗi IP: tối đa 10 request / phút (dùng `express-rate-limit`)
- Ngăn spam vote (dù contract đã chặn double-vote qua nullifier)

#### Task 4.2: Replay protection
- Relayer check nullifier trên contract trước khi gửi tx
- Tránh lãng phí gas cho proof đã dùng:
  ```ts
  const isUsed = await contract.isNullifierUsed(proof.nullifier);
  if (isUsed) return res.status(400).json({ error: 'Nullifier already used' });
  ```

#### Task 4.3: Gas management
- Monitor balance relayer wallet
- Alert/log khi balance thấp
- Endpoint GET /api/relay/status trả về balance hiện tại

#### Task 4.4: Request validation
- Validate proof format trước khi gửi tx
- Check poll state on-chain (phải đang ở Voting phase)
- Reject nếu vote index >= options.length

---

## Thứ tự thực hiện (ưu tiên)

```
1. [Phase 1] Task 1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7
2. [Phase 3] Task 3.1 → 3.2
3. [Phase 2] Task 2.1 → 2.2 → 2.3 → 2.4
4. [Phase 4] Task 4.1 → 4.2 → 4.3 → 4.4
```

Phase 1 + 3 có thể test bằng curl trước khi sửa frontend.
Phase 2 làm sau khi relayer đã hoạt động.
Phase 4 là hardening, làm cuối cùng.

---

## Cách test

### Test relayer bằng curl (sau Phase 1)

```bash
# 1. Check relayer status
curl http://localhost:3001/api/relay/status

# 2. Relay a vote (cần proof thật từ frontend)
curl -X POST http://localhost:3001/api/relay/vote \
  -H "Content-Type: application/json" \
  -d '{
    "pollAddress": "0x...",
    "vote": 0,
    "proof": {
      "merkleTreeDepth": 20,
      "merkleTreeRoot": "123...",
      "nullifier": "456...",
      "message": "0",
      "scope": "789...",
      "points": ["...8 elements..."]
    }
  }'
```

### Test full flow (sau Phase 2)

1. Admin (Account #0): Tạo poll, generate tokens, start voting
2. Voter (KHÔNG connect ví): Mở trang poll, paste token, chọn option
3. Click "Vote via Relayer" → ZK proof generate trong browser → gửi HTTP tới relayer
4. Relayer ký tx → gửi lên blockchain → trả txHash
5. Kiểm tra kết quả trên Dashboard

---

## Lưu ý quan trọng

1. **Private key relayer**: Trên local dev dùng Hardhat Account #0. Trên testnet/mainnet, dùng key riêng và KHÔNG commit vào git.

2. **Proof generation vẫn ở browser**: Relayer KHÔNG generate proof. Browser tải WASM circuit (~2MB) và chạy Groth16 prover. Relayer chỉ forward proof đã tạo.

3. **Trust model**: Voter không cần trust relayer vì:
   - Relayer không biết voter là ai (ZK proof)
   - Relayer không thể đổi vote (proof.message == vote, enforced on-chain)
   - Relayer không thể vote lại (nullifier prevents double-vote)
   - Relayer chỉ có thể: (a) forward đúng, hoặc (b) từ chối forward (censorship)

4. **Anti-censorship**: Nếu relayer từ chối, voter vẫn có thể connect ví và tự gửi tx. Relayer là tiện ích, không phải dependency.

5. **Chi phí gas**: Mỗi vote tốn ~300k-600k gas. Trên Hardhat local: miễn phí. Trên Sepolia testnet: ~0.001 ETH/vote. Admin cần fund relayer wallet.
