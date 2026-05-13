import { useState, useEffect } from 'react'
import { BrowserRouter as Router, Routes, Route, Link, useLocation } from 'react-router-dom'
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import {
    ShieldCheck,
    Wallet,
    LogOut,
    AlertTriangle,
    Lock,
    Moon,
    Sun,
    LayoutDashboard,
    Plus,
    Code2,
    BookOpen,
    HelpCircle,
} from 'lucide-react'
import Home from './pages/Home'
import CreatePoll from './pages/CreatePoll'
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

/* -- Nav Link component -------------------------------------------------- */
function NavLink({ to, icon: Icon, children }: { to: string; icon: React.ComponentType<{ className?: string }>; children: React.ReactNode }) {
    const location = useLocation()
    const isActive = location.pathname === to
    return (
        <Link
            to={to}
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                isActive
                    ? 'text-teal-700 dark:text-teal-400 bg-teal-50 dark:bg-teal-900/30'
                    : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800'
            }`}
        >
            <Icon className="w-4 h-4" />
            {children}
        </Link>
    )
}

function AppContent() {
    const { address, isConnected } = useAccount()
    const { connect, connectors } = useConnect()
    const { disconnect } = useDisconnect()
    const chainId = useChainId()
    const { switchChain } = useSwitchChain()

    const [darkMode, setDarkMode] = useState(() => {
        if (typeof window !== 'undefined') {
            return localStorage.getItem('theme') === 'dark' ||
                (!localStorage.getItem('theme') && window.matchMedia('(prefers-color-scheme: dark)').matches)
        }
        return false
    })

    useEffect(() => {
        document.documentElement.classList.toggle('dark', darkMode)
        localStorage.setItem('theme', darkMode ? 'dark' : 'light')
    }, [darkMode])

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

    const metaMaskConnector = connectors.find(c => c.name === 'MetaMask') ?? connectors[0]

    return (
        <div className="min-h-screen bg-[#FAFAF9] dark:bg-stone-950 dot-grid-bg text-stone-900 dark:text-stone-100 font-sans flex flex-col">

            {/* -- Header ----------------------------------------------------- */}
            <header className="sticky top-0 z-40 bg-white/80 dark:bg-stone-900/80 backdrop-blur-md border-b border-stone-200 dark:border-stone-800 shadow-[0_1px_2px_0_rgba(0,0,0,0.03)]">
                <div className="max-w-6xl mx-auto flex items-center justify-between px-6 py-4 md:px-8">
                    {/* Left: logo + title + nav */}
                    <div className="flex items-center gap-6">
                        <a href="/" className="flex items-center gap-3 no-underline group">
                            <div className="w-9 h-9 rounded-xl bg-stone-900 dark:bg-stone-100 flex items-center justify-center group-hover:bg-stone-800 dark:group-hover:bg-stone-200 transition-colors">
                                <ShieldCheck className="w-5 h-5 text-white dark:text-stone-900" />
                            </div>
                            <div>
                                <span className="text-lg font-extrabold tracking-tight text-stone-900 dark:text-stone-100">
                                    Voting Hub
                                </span>
                                <span className="hidden sm:block text-xs font-normal text-stone-500 dark:text-stone-400">
                                    Anonymous &amp; Provable
                                </span>
                            </div>
                        </a>

                        {/* Navigation links */}
                        <nav className="hidden sm:flex items-center gap-1">
                            <NavLink to="/" icon={LayoutDashboard}>Dashboard</NavLink>
                            <NavLink to="/create" icon={Plus}>Create Poll</NavLink>
                        </nav>
                    </div>

                    {/* Right: theme toggle + wallet controls */}
                    <div className="flex items-center gap-3">
                        {/* Dark mode toggle */}
                        <button
                            onClick={() => setDarkMode(!darkMode)}
                            className="p-2.5 bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 hover:bg-stone-100 dark:hover:bg-stone-700 text-stone-600 dark:text-stone-300 rounded-xl text-sm transition-colors min-h-[44px] cursor-pointer"
                            aria-label="Toggle dark mode"
                        >
                            {darkMode ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
                        </button>

                        {!isConnected ? (
                            <>
                                {import.meta.env.DEV && (
                                    <button
                                        onClick={() => {
                                            const mockConnector = connectors.find(c => c.id === 'mock')
                                            if (mockConnector) connect({ connector: mockConnector })
                                        }}
                                        className="inline-flex items-center gap-2 px-4 py-2.5 bg-teal-50 dark:bg-teal-900/30 hover:bg-teal-100 dark:hover:bg-teal-900/50 text-teal-700 dark:text-teal-300 border border-teal-200 dark:border-teal-700 rounded-xl text-sm font-medium transition-colors min-h-[44px] cursor-pointer"
                                        title="Connect using a built-in Hardhat test account. No MetaMask required."
                                    >
                                        <Code2 className="w-4 h-4" />
                                        Test Account
                                    </button>
                                )}
                                <button
                                    onClick={async () => {
                                        await addHardhatNetwork()
                                        if (metaMaskConnector) connect({ connector: metaMaskConnector })
                                    }}
                                    className="inline-flex items-center gap-2 px-5 py-2.5 bg-stone-900 dark:bg-stone-100 hover:bg-stone-800 dark:hover:bg-stone-200 active:bg-stone-950 dark:active:bg-stone-300 text-white dark:text-stone-900 rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer"
                                >
                                    <Wallet className="w-4 h-4" />
                                    Connect Wallet
                                </button>
                            </>
                        ) : (
                            <>
                                {/* Address badge */}
                                <div className="hidden sm:flex items-center gap-2 px-4 py-2 bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl text-sm text-stone-700 dark:text-stone-300 font-mono min-h-[44px]">
                                    <span className="relative flex items-center justify-center w-2.5 h-2.5">
                                        <span className="absolute inline-flex h-full w-full rounded-full bg-teal-400 opacity-75 animate-ping" />
                                        <span className="relative inline-flex rounded-full h-2 w-2 bg-teal-500" />
                                    </span>
                                    {address?.slice(0, 6)}...{address?.slice(-4)}
                                </div>
                                {/* Disconnect */}
                                <button
                                    onClick={() => disconnect()}
                                    className="px-3 py-2 bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 hover:bg-rose-50 dark:hover:bg-rose-900/30 hover:text-rose-600 dark:hover:text-rose-400 hover:border-rose-200 dark:hover:border-rose-700 text-stone-500 dark:text-stone-400 rounded-xl text-sm font-normal transition-all min-h-[44px] cursor-pointer"
                                    aria-label="Disconnect wallet"
                                >
                                    <LogOut className="w-4 h-4" />
                                </button>
                            </>
                        )}
                    </div>
                </div>

                {/* -- Wrong-network banner ------------------------------------ */}
                {isWrongNetwork && (
                    <div className="bg-amber-50 dark:bg-amber-900/30 border-t border-amber-200 dark:border-amber-700">
                        <div className="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3 px-6 py-3 md:px-8">
                            <p className="flex items-center gap-2 text-sm font-semibold text-amber-800 dark:text-amber-300">
                                <AlertTriangle className="w-5 h-5 text-amber-500 shrink-0" />
                                You are on the wrong network.
                            </p>
                            <button
                                onClick={async () => {
                                    await addHardhatNetwork()
                                    switchChain({ chainId: hardhat.id })
                                }}
                                className="inline-flex items-center gap-2 px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer whitespace-nowrap"
                            >
                                Switch to Hardhat Network
                            </button>
                        </div>
                    </div>
                )}

                {/* Mobile nav */}
                <nav className="sm:hidden flex items-center gap-1 px-6 pb-3">
                    <NavLink to="/" icon={LayoutDashboard}>Dashboard</NavLink>
                    <NavLink to="/create" icon={Plus}>Create</NavLink>
                </nav>
            </header>

            {/* -- Main content ----------------------------------------------- */}
            <main className="flex-1 max-w-6xl w-full mx-auto px-6 py-8 md:px-8 md:py-12">
                <Routes>
                    <Route path="/" element={<Home />} />
                    <Route path="/create" element={<CreatePoll />} />
                    <Route path="/poll/:address" element={<PollRouter />} />
                </Routes>
            </main>

            {/* -- Footer ----------------------------------------------------- */}
            <footer className="border-t border-stone-200 dark:border-stone-800 bg-stone-50 dark:bg-stone-900">
                <div className="max-w-6xl mx-auto px-6 py-8 md:px-8">
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 mb-6">
                        {/* About */}
                        <div>
                            <h4 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-3">About</h4>
                            <p className="text-xs text-stone-400 dark:text-stone-500 leading-relaxed">
                                Voting Hub is a decentralized voting platform that uses zero-knowledge proofs and commit-reveal schemes to ensure voter privacy.
                            </p>
                        </div>
                        {/* Links */}
                        <div>
                            <h4 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-3">Resources</h4>
                            <ul className="space-y-2">
                                <li>
                                    <a href="#" className="text-xs text-stone-400 dark:text-stone-500 hover:text-teal-600 dark:hover:text-teal-400 transition-colors flex items-center gap-1.5">
                                        <BookOpen className="w-3.5 h-3.5" /> Documentation
                                    </a>
                                </li>
                                <li>
                                    <a href="#" className="text-xs text-stone-400 dark:text-stone-500 hover:text-teal-600 dark:hover:text-teal-400 transition-colors flex items-center gap-1.5">
                                        <Code2 className="w-3.5 h-3.5" /> Source Code
                                    </a>
                                </li>
                                <li>
                                    <a href="#" className="text-xs text-stone-400 dark:text-stone-500 hover:text-teal-600 dark:hover:text-teal-400 transition-colors flex items-center gap-1.5">
                                        <HelpCircle className="w-3.5 h-3.5" /> How It Works
                                    </a>
                                </li>
                            </ul>
                        </div>
                        {/* Tech */}
                        <div>
                            <h4 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-3">Technology</h4>
                            <div className="flex flex-wrap gap-2">
                                <span className="text-xs px-2 py-1 bg-stone-100 dark:bg-stone-800 text-stone-500 dark:text-stone-400 rounded-md border border-stone-200 dark:border-stone-700">Semaphore</span>
                                <span className="text-xs px-2 py-1 bg-stone-100 dark:bg-stone-800 text-stone-500 dark:text-stone-400 rounded-md border border-stone-200 dark:border-stone-700">Groth16</span>
                                <span className="text-xs px-2 py-1 bg-stone-100 dark:bg-stone-800 text-stone-500 dark:text-stone-400 rounded-md border border-stone-200 dark:border-stone-700">Solidity</span>
                                <span className="text-xs px-2 py-1 bg-stone-100 dark:bg-stone-800 text-stone-500 dark:text-stone-400 rounded-md border border-stone-200 dark:border-stone-700">React</span>
                            </div>
                        </div>
                    </div>
                    <div className="border-t border-stone-200 dark:border-stone-800 pt-6 flex items-center justify-center gap-2 text-stone-400 dark:text-stone-500 text-xs">
                        <Lock className="w-4 h-4" />
                        <span>Secured by Zero-Knowledge Proofs</span>
                    </div>
                </div>
            </footer>
        </div>
    )
}

export default function App() {
    return (
        <Router>
            <AppContent />
        </Router>
    )
}
