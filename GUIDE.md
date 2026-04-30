# Hướng Dẫn Sử Dụng ZK Voting Hub — Từ A đến Z

Tài liệu này hướng dẫn **toàn bộ quy trình** sử dụng hệ thống bỏ phiếu ẩn danh ZK Voting Hub, từ khâu khởi động hệ thống đến khi có kết quả cuối cùng.

---

## Mục Lục

1. [Khởi động hệ thống](#1-khởi-động-hệ-thống)
2. [Cài đặt MetaMask cho Admin](#2-cài-đặt-metamask-cho-admin)
3. [Admin: Tạo cuộc bỏ phiếu](#3-admin-tạo-cuộc-bỏ-phiếu)
4. [Admin: Tạo token mời và phát cho khách](#4-admin-tạo-token-mời-và-phát-cho-khách)
5. [Admin: Mở bỏ phiếu](#5-admin-mở-bỏ-phiếu)
6. [Khách: Nhận token và bỏ phiếu](#6-khách-nhận-token-và-bỏ-phiếu)
7. [Admin: Đóng bỏ phiếu và xem kết quả](#7-admin-đóng-bỏ-phiếu-và-xem-kết-quả)
8. [Tổng quan luồng hoạt động](#8-tổng-quan-luồng-hoạt-động)
9. [Xử lý sự cố](#9-xử-lý-sự-cố)

---

## 1. Khởi Động Hệ Thống

Mở terminal tại thư mục `web3-demo/` và chạy:

```bash
docker compose up --build -d
```

Đợi khoảng 30–60 giây để hệ thống sẵn sàng. Kiểm tra bằng lệnh:

```bash
docker compose logs contracts | grep "Contracts are fully deployed"
```

Khi thấy dòng `Contracts are fully deployed. Tailing logs...` nghĩa là thành công.

**Hệ thống gồm 4 dịch vụ:**

| Dịch vụ | Địa chỉ | Vai trò |
|---------|---------|---------|
| Frontend | http://localhost:5173 | Giao diện web cho admin và khách |
| Blockchain | http://localhost:8545 | Node Ethereum chạy cục bộ |
| Relayer | http://localhost:3001 | Dịch vụ gửi phiếu thay khách (không cần ví) |
| Explorer | http://localhost:3728 | Trình duyệt giao dịch blockchain |

> **Lưu ý WSL2**: Nếu dùng Windows + WSL2, thay `localhost` bằng IP của WSL2. Chạy `ip addr show eth0 | grep inet` trong WSL để lấy IP (ví dụ `172.28.190.11`).

---

## 2. Cài Đặt MetaMask Cho Admin

Admin cần cài MetaMask để tạo poll, tạo token và điều hành bỏ phiếu. **Khách KHÔNG cần cài MetaMask** nếu sử dụng chế độ Relayer.

### Bước 2.1: Thêm mạng Hardhat Local

1. Mở MetaMask trên browser
2. Click biểu tượng mạng (góc trái trên) → **Add a custom network**
3. Điền thông tin:

| Trường | Giá trị |
|--------|---------|
| Network name | `Hardhat Local` |
| New RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency symbol | `ETH` |

4. Nhấn **Save** → chuyển sang mạng `Hardhat Local`

### Bước 2.2: Import tài khoản Admin

1. MetaMask → click biểu tượng tài khoản → **Import Account**
2. Chọn loại **Private Key**
3. Dán private key sau:

```
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

4. Nhấn **Import**
5. Tài khoản hiện ra với số dư khoảng **10,000 ETH** (tiền test, không có giá trị thật)

> Đây là tài khoản test mặc định của Hardhat. Mỗi lần khởi động lại hệ thống, số dư reset về 10,000 ETH.

---

## 3. Admin: Tạo Cuộc Bỏ Phiếu

### Bước 3.1: Truy cập trang web

1. Mở browser, vào `http://localhost:5173` (hoặc IP WSL2)
2. Nhấn **Connect Wallet** ở góc phải trên → chọn **MetaMask**
3. MetaMask popup → nhấn **Connect** → nhấn **Switch Network** nếu được yêu cầu

### Bước 3.2: Tạo poll mới

1. Click **Create Poll** trên thanh điều hướng
2. Điền thông tin:

| Trường | Ví dụ | Mô tả |
|--------|-------|-------|
| **Poll Title** | `Bầu cử lớp trưởng K20` | Tên cuộc bỏ phiếu |
| **Description** | `Chọn lớp trưởng học kỳ 2` | Mô tả ngắn (tuỳ chọn) |
| **Poll Type** | `Anonymous (ZK)` | Loại bỏ phiếu — chọn ZK cho ẩn danh hoàn toàn |
| **Option 1** | `Nguyễn Văn A` | Lựa chọn thứ nhất |
| **Option 2** | `Trần Thị B` | Lựa chọn thứ hai |

3. Có thể nhấn **+ Add Option** để thêm lựa chọn (tối thiểu 2)
4. Xem bản xem trước (Preview) ở cột phải để kiểm tra
5. Nhấn **Create Poll**
6. MetaMask popup hiện ra → nhấn **Confirm** để xác nhận giao dịch
7. Đợi thông báo "Poll created successfully!" → tự động quay về Dashboard

> Poll vừa tạo sẽ xuất hiện trên Dashboard với trạng thái **Registration** (đang đăng ký).

---

## 4. Admin: Tạo Token Mời Và Phát Cho Khách

Đây là bước quan trọng nhất — Admin tạo ra các **invite token** (mã mời ẩn danh) và gửi cho từng khách. Mỗi token là một chuỗi hex dài 64 ký tự, đại diện cho một "danh tính ẩn" trên blockchain.

### Bước 4.1: Vào trang quản lý poll

1. Trên Dashboard, click vào poll vừa tạo
2. Trang poll hiện ra với 2 cột:
   - **Cột trái**: khu vực dành cho khách bỏ phiếu
   - **Cột phải**: kết quả realtime + **Admin Panel** (khung viền vàng)

### Bước 4.2: Tạo token

1. Trong **Admin Panel**, tìm mục **Generate Vote Tokens**
2. Nhập số lượng token cần tạo (ví dụ `10` nếu có 10 khách)
3. Nhấn **Generate 10 Tokens**
4. MetaMask popup → nhấn **Confirm**
5. Đợi giao dịch xác nhận (~5 giây)
6. Danh sách token hiện ra trong khung đen, ví dụ:

```
1. a3f7b2c9e1d4f8a6b0c3d5e7f9a1b2c4d6e8f0a2b4c6d8e0f1a3b5c7d9e1f3
2. 1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2
3. ...
```

### Bước 4.3: Copy và phát token

1. Nhấn **Copy All** để copy toàn bộ token
2. Dán vào notepad/file text để lưu lại
3. **Gửi MỖI token cho MỘT khách riêng biệt** qua:
   - Tin nhắn riêng (Zalo, Messenger, Telegram...)
   - Email
   - In ra giấy
4. **QUAN TRỌNG**: Mỗi token chỉ dùng được 1 lần. Không chia sẻ 1 token cho nhiều người.

> **Bảo mật**: Admin không biết token nào thuộc về ai sau khi phát. Ngay cả admin cũng không thể liên kết phiếu bầu với danh tính người bỏ phiếu nhờ Zero-Knowledge Proof.

### Bước 4.4: Thêm lựa chọn (tuỳ chọn)

Nếu cần thêm option sau khi tạo poll (chỉ trong giai đoạn Registration):
1. Trong **Admin Panel** → mục **Manage Options**
2. Nhập tên option mới → nhấn **+ Add**
3. MetaMask Confirm

---

## 5. Admin: Mở Bỏ Phiếu

Khi đã tạo đủ token và phát cho tất cả khách:

1. Trong **Admin Panel**, nhấn nút **Start Voting**
2. MetaMask popup → nhấn **Confirm**
3. Trạng thái poll chuyển từ **Registration** → **Voting**
4. Thanh tiến trình ở đầu trang hiện bước 2 (Voting) đang active

> Từ thời điểm này, khách có thể bắt đầu bỏ phiếu. Admin nên thông báo cho khách biết đã mở bỏ phiếu.

---

## 6. Khách: Nhận Token Và Bỏ Phiếu

### Những gì khách cần

- **Một trình duyệt** (Chrome, Firefox, Edge...) — không cần cài thêm gì
- **Invite token** nhận từ admin (chuỗi 64 ký tự hex)
- **Link trang poll** (admin gửi kèm token)

### Bước 6.1: Mở trang poll

Khách mở link poll trong browser, ví dụ:
```
http://172.28.190.11:5173/poll/0x6D544390Eb535d61e196c87d689c80dCD8628Acd
```

Trang hiện ra với giao diện bỏ phiếu. Phía trên có nhãn **ZK Anonymous** và thanh trạng thái hiện **Voting**.

### Bước 6.2: Nhập token — Xác nhận danh tính

1. Ở phần **Identity**, tìm ô nhập "Paste your invite token"
2. Dán invite token mà admin đã gửi
3. Nhấn **Load Identity**
4. Thấy dòng **"Identity Ready"** màu xanh lá → danh tính đã sẵn sàng

> Token chỉ cần nhập 1 lần. Nếu bạn quay lại trang sau, danh tính vẫn được lưu trong browser.

### Bước 6.3: Chọn chế độ bỏ phiếu

Ở phần **Cast Your Vote**, bạn thấy 2 tab:

| Tab | Mô tả | Cần ví? | Cần ETH? |
|-----|-------|---------|----------|
| **Direct (Wallet)** | Bạn tự gửi giao dịch bằng MetaMask | Có | Có |
| **Relayer (No Wallet)** | Relayer gửi giao dịch thay bạn | **Không** | **Không** |

**Khuyến nghị**: Chọn **Relayer (No Wallet)** — đơn giản nhất, không cần cài MetaMask, không cần ETH.

Nhấn vào tab **Relayer (No Wallet)** (nút tím). Dòng thông báo tím xuất hiện:
> "Your vote will be submitted anonymously via the relayer service. No wallet or ETH required."

### Bước 6.4: Bỏ phiếu

1. Chọn lựa chọn bạn muốn bầu (ví dụ `Nguyễn Văn A`)
2. Nhấn nút **Vote via Relayer (No Wallet)** (nút tím)
3. Quá trình diễn ra tự động:

```
Đang tạo bằng chứng zero-knowledge... (5-15 giây)
  → Browser tải mạch ZK (~2MB) và tạo Groth16 proof
  → Đây là phép toán nặng nhất, chạy hoàn toàn trong browser của bạn

Đang gửi phiếu tới relayer...
  → Proof được gửi qua HTTP tới Relayer service
  → Relayer ký giao dịch và gửi lên blockchain thay bạn

Vote relayed successfully! Tx: 0xabc123...
  → Phiếu đã được ghi ẩn danh trên blockchain
  → Không ai — kể cả admin, relayer, hay blockchain explorer — có thể biết bạn đã bầu cho ai
```

4. Sau khi vote thành công, phần **Privacy Receipt** hiện ra xác nhận:
   - **Đã ghi trên blockchain**: phiếu bầu (mã hoá), nullifier (chống bầu 2 lần), ZK proof
   - **KHÔNG BAO GIỜ ghi**: địa chỉ ví, danh tính, mối liên hệ giữa bạn và phiếu bầu

### Bước 6.5: Xem kết quả realtime

Ở cột phải, mục **Live Results** hiện biểu đồ thanh cập nhật theo thời gian thực:
- Số phiếu mỗi lựa chọn
- Phần trăm
- Tổng số phiếu đã bầu

> **Mỗi token chỉ bỏ phiếu được 1 lần.** Nếu bạn thử bỏ phiếu lại, hệ thống sẽ báo lỗi "You've already voted in this poll."

---

## 7. Admin: Đóng Bỏ Phiếu Và Xem Kết Quả

Khi tất cả khách đã bỏ phiếu xong (hoặc hết thời gian):

### Bước 7.1: Đóng bỏ phiếu

1. Admin mở trang poll (đảm bảo đang dùng tài khoản Admin trong MetaMask)
2. Trong **Admin Panel**, nhấn **Close Poll**
3. MetaMask popup → nhấn **Confirm**
4. Trạng thái chuyển sang **Ended**
5. Thông báo: "Voting has ended. Final results are now locked."

### Bước 7.2: Xem kết quả cuối cùng

- Kết quả hiện trong mục **Live Results** — giờ đã là kết quả chính thức
- Kết quả được **khoá vĩnh viễn trên blockchain** — không ai có thể thay đổi
- Bất kỳ ai cũng có thể mở trang poll để xem kết quả
- Có thể xem giao dịch chi tiết trên **Block Explorer** (`http://localhost:3728`)

---

## 8. Tổng Quan Luồng Hoạt Động

```
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║   ADMIN                                                              ║
║   ─────                                                              ║
║                                                                      ║
║   ① Tạo Poll                                                        ║
║      └─ Chọn loại (ZK Anonymous) + nhập tên + options                ║
║      └─ MetaMask xác nhận → poll xuất hiện trên Dashboard            ║
║                          ↓                                           ║
║   ② Tạo Token                                                       ║
║      └─ Generate N tokens → MetaMask xác nhận                       ║
║      └─ Copy All → lưu lại                                          ║
║                          ↓                                           ║
║   ③ Phát Token                                                      ║
║      └─ Gửi MỖI token cho MỘT khách qua kênh riêng tư              ║
║         (Zalo, email, giấy in...)                                    ║
║                          ↓                                           ║
║   ④ Start Voting                                                    ║
║      └─ MetaMask xác nhận → thông báo cho khách                     ║
║                          ↓                                           ║
║   ⑤ ... chờ khách bỏ phiếu ...                                      ║
║                          ↓                                           ║
║   ⑥ Close Poll                                                      ║
║      └─ MetaMask xác nhận → kết quả khoá vĩnh viễn                  ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║   KHÁCH (VOTER)                                                      ║
║   ─────────────                                                      ║
║                                                                      ║
║   ① Nhận token + link poll từ admin                                  ║
║                          ↓                                           ║
║   ② Mở link poll trong browser                                      ║
║      └─ KHÔNG cần cài MetaMask                                      ║
║      └─ KHÔNG cần có ETH                                            ║
║                          ↓                                           ║
║   ③ Dán token → Load Identity                                       ║
║      └─ Hiện "Identity Ready" → sẵn sàng                            ║
║                          ↓                                           ║
║   ④ Chọn tab "Relayer (No Wallet)"                                  ║
║                          ↓                                           ║
║   ⑤ Chọn option → Vote via Relayer                                  ║
║      └─ Browser tạo ZK proof (~10 giây)                              ║
║      └─ Proof gửi → Relayer → Blockchain                            ║
║                          ↓                                           ║
║   ⑥ "Vote relayed successfully!"                                    ║
║      └─ Phiếu ghi ẩn danh on-chain                                  ║
║      └─ Không ai biết bạn bầu cho ai                                ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

### Tính ẩn danh hoạt động như thế nào?

```
Token (64 hex chars)
    │
    ▼
Semaphore Identity (browser tạo từ token)
    │
    ▼
ZK Proof (browser tạo bằng mạch Groth16 ~2MB WASM)
    │  Proof chứng minh: "Tôi thuộc nhóm voter" NHƯNG KHÔNG tiết lộ "Tôi là ai"
    │
    ▼
Relayer (nhận proof → KHÔNG biết voter là ai → gửi lên blockchain)
    │
    ▼
Smart Contract (verify proof → ghi phiếu + nullifier → KHÔNG ghi danh tính)
```

**Kết quả**: Phiếu bầu tồn tại trên blockchain, có thể kiểm chứng (verifiable), nhưng KHÔNG THỂ liên kết ngược lại danh tính người bỏ phiếu.

---

## 9. Xử Lý Sự Cố

| Vấn đề | Nguyên nhân | Cách xử lý |
|--------|-------------|------------|
| Không mở được `localhost:5173` | Docker chưa chạy xong hoặc dùng WSL2 | Chạy `docker compose ps` kiểm tra. Nếu WSL2, dùng IP thật |
| MetaMask báo "Nonce too high" | MetaMask cache nonce cũ từ lần chạy trước | MetaMask → Settings → Advanced → **Clear activity tab data** |
| Tạo poll nhưng không thấy trên Dashboard | RPC URL sai | Kiểm tra MetaMask RPC URL = `http://127.0.0.1:8545` |
| "Identity Ready" nhưng vote bị lỗi | Token đã dùng hoặc poll chưa mở | Kiểm tra trạng thái poll = Voting. Mỗi token chỉ dùng 1 lần |
| Trang poll trắng/đen | Lỗi JavaScript (thường do localStorage hỏng) | Mở DevTools (F12) → Console → chạy: `Object.keys(localStorage).filter(k=>k.startsWith('semaphore-')).forEach(k=>localStorage.removeItem(k))` rồi refresh |
| Vote via Relayer báo lỗi mạng | Relayer chưa chạy hoặc port bị chặn | Chạy `curl http://localhost:3001/api/relay/status` kiểm tra |
| "This vote token has already been used" | Token đã bỏ phiếu rồi | Mỗi token chỉ dùng 1 lần — đây là thiết kế chống gian lận |
| Copy All không hoạt động | Browser chặn clipboard trên HTTP+IP | Đã fix bằng fallback. Nếu vẫn lỗi, select text thủ công và Ctrl+C |

### Khởi động lại từ đầu

Nếu muốn reset toàn bộ (xoá hết poll, token, phiếu):

```bash
docker compose down
docker compose up --build -d
```

Hệ thống deploy contracts mới, tất cả dữ liệu cũ bị xoá.

---

## Tóm Tắt Một Dòng

> **Admin** tạo poll → tạo token → phát token → mở bỏ phiếu → **Khách** dán token → bấm vote → xong. Không cần ví, không cần ETH, hoàn toàn ẩn danh.
