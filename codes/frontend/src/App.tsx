import { BrowserRouter as Router, Routes, Route } from 'react-router-dom'
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import Home from './pages/Home'
import PollRouter from './pages/PollRouter'

const RPC_URL = import.meta.env.VITE_RPC_URL || 'http://127.0.0.1:8545'

async function addHardhatNetwork() {
  if (!window.ethereum) return
  try {
    await window.ethereum.request({
      method: 'wallet_addEthereumChain',
      params: [{
        chainId: '0x7A69', // 31337
        chainName: 'Hardhat Local',
        nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
        rpcUrls: [RPC_URL],
      }],
    })
  } catch {
    // User rejected or chain already added -- either is fine
  }
}

export default function App() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

  const metaMaskConnector = connectors.find(c => c.name === 'MetaMask') ?? connectors[0]

  return (
    <Router>
      <div className="min-h-screen bg-slate-50 text-slate-900 font-sans selection:bg-blue-200 flex flex-col">

        {/* ── Header ─────────────────────────────────────────── */}
        <header className="sticky top-0 z-40 bg-white/80 backdrop-blur-md border-b border-slate-200">
          <div className="max-w-6xl mx-auto flex items-center justify-between px-6 py-4 md:px-8">
            {/* Left: logo + title */}
            <a href="/" className="flex items-center gap-3 no-underline">
              {/* Shield-check icon */}
              <svg className="w-8 h-8 text-slate-900" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden="true">
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z" />
              </svg>
              <div>
                <span className="text-lg font-extrabold tracking-tight text-slate-900">
                  Voting Hub
                </span>
                <span className="hidden sm:block text-xs font-normal text-slate-500">
                  Anonymous &amp; Provable
                </span>
              </div>
            </a>

            {/* Right: wallet controls */}
            <div className="flex items-center gap-3">
              {!isConnected ? (
                <button
                  onClick={async () => {
                    await addHardhatNetwork()
                    if (metaMaskConnector) connect({ connector: metaMaskConnector })
                  }}
                  className="inline-flex items-center gap-2 px-5 py-2.5 bg-slate-900 hover:bg-slate-800 active:bg-slate-950 text-white rounded-xl text-sm font-semibold shadow-sm transition-colors min-h-[44px] cursor-pointer"
                >
                  {/* Wallet icon */}
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M21 12a2.25 2.25 0 0 0-2.25-2.25H15a3 3 0 1 1 0-6h.75A2.25 2.25 0 0 1 18 6v0a2.25 2.25 0 0 1-2.25 2.25H15M3 18.75V7.5A2.25 2.25 0 0 1 5.25 5.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5" />
                  </svg>
                  Connect Wallet
                </button>
              ) : (
                <>
                  {/* Address badge */}
                  <div className="hidden sm:flex items-center gap-2 px-4 py-2 bg-slate-100 border border-slate-200 rounded-xl text-sm text-slate-700 font-mono min-h-[44px]">
                    <span className="w-2 h-2 rounded-full bg-emerald-500 shrink-0" aria-label="Connected" />
                    {address?.slice(0, 6)}...{address?.slice(-4)}
                  </div>
                  {/* Disconnect */}
                  <button
                    onClick={() => disconnect()}
                    className="px-3 py-2 bg-white border border-slate-200 hover:bg-rose-50 hover:text-rose-600 hover:border-rose-200 text-slate-500 rounded-xl text-sm font-normal transition-colors min-h-[44px] cursor-pointer"
                    aria-label="Disconnect wallet"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9" />
                    </svg>
                  </button>
                </>
              )}
            </div>
          </div>

          {/* ── Wrong-network banner ─────────────────────────── */}
          {isWrongNetwork && (
            <div className="bg-amber-50 border-t border-amber-200">
              <div className="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3 px-6 py-3 md:px-8">
                <p className="flex items-center gap-2 text-sm font-semibold text-amber-800">
                  {/* Warning icon */}
                  <svg className="w-5 h-5 text-amber-500 shrink-0" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
                  </svg>
                  You are on the wrong network.
                </p>
                <button
                  onClick={async () => {
                    await addHardhatNetwork()
                    switchChain({ chainId: hardhat.id })
                  }}
                  className="inline-flex items-center gap-2 px-4 py-2 bg-amber-600 hover:bg-amber-700 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer whitespace-nowrap"
                >
                  Switch to Hardhat Network
                </button>
              </div>
            </div>
          )}
        </header>

        {/* ── Main content ───────────────────────────────────── */}
        <main className="flex-1 max-w-6xl w-full mx-auto px-6 py-8 md:px-8 md:py-12">
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/poll/:address" element={<PollRouter />} />
          </Routes>
        </main>

        {/* ── Footer ─────────────────────────────────────────── */}
        <footer className="border-t border-slate-200 bg-white">
          <div className="max-w-6xl mx-auto px-6 py-6 md:px-8 flex items-center justify-center gap-2 text-slate-400 text-xs">
            {/* Lock icon */}
            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
              <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
            </svg>
            <span>Secured by Zero-Knowledge Proofs</span>
          </div>
        </footer>
      </div>
    </Router>
  )
}
