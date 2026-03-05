import { BrowserRouter as Router, Routes, Route } from 'react-router-dom'
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import Home from './pages/Home'
import Poll from './pages/Poll'

export default function App() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

  return (
    <Router>
      <div className="min-h-screen bg-slate-50 text-slate-900 p-6 md:p-12 font-sans selection:bg-blue-200">
        <div className="max-w-6xl mx-auto space-y-10">
          {/* HEADER NAV */}
          <header className="flex flex-col md:flex-row justify-between items-start md:items-center border-b border-slate-200 pb-6 gap-4">
            <div>
              <h1 className="text-3xl font-extrabold tracking-tight text-slate-900">
                ZK Voting Hub
              </h1>
              <p className="text-slate-500 mt-1 text-sm font-medium">Anonymous, provable, and secure multi-poll platform.</p>
            </div>

            <div>
              {!isConnected ? (
                <div className="flex gap-2">
                  {connectors.map((connector) => (
                    <button
                      key={connector.uid}
                      onClick={() => connect({ connector })}
                      className="px-5 py-2.5 bg-slate-900 hover:bg-slate-800 text-white transition-colors rounded-xl text-sm font-medium shadow-sm"
                    >
                      Connect {connector.name}
                    </button>
                  ))}
                </div>
              ) : isWrongNetwork ? (
                <div className="flex items-center gap-3">
                  <button
                    onClick={() => switchChain({ chainId: hardhat.id })}
                    className="px-4 py-2 bg-rose-50 text-rose-600 border border-rose-200 hover:bg-rose-100 transition-colors rounded-xl text-sm font-medium flex items-center gap-2"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
                    Switch Network
                  </button>
                  <button
                    onClick={() => disconnect()}
                    className="px-3 py-2 bg-white border border-slate-200 hover:bg-slate-50 text-slate-600 transition-colors rounded-xl text-sm font-medium shadow-sm"
                  >
                    Disconnect
                  </button>
                </div>
              ) : (
                <div className="flex items-center gap-3">
                  <div className="text-sm px-4 py-2 bg-white border border-slate-200 text-slate-700 rounded-xl font-mono shadow-sm">
                    {address?.slice(0, 6)}...{address?.slice(-4)}
                  </div>
                  <button
                    onClick={() => disconnect()}
                    className="px-3 py-2 bg-white border border-slate-200 hover:bg-rose-50 hover:text-rose-600 hover:border-rose-200 text-slate-600 transition-colors rounded-xl text-sm font-medium shadow-sm"
                  >
                    Disconnect
                  </button>
                </div>
              )}
            </div>
          </header>

          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/poll/:address" element={<Poll />} />
          </Routes>
        </div>
      </div>
    </Router>
  )
}
