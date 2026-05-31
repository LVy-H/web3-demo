import { useState, useEffect } from 'react'
import { BrowserRouter as Router, Routes, Route, Link, useLocation } from 'react-router-dom'
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain, useEnsName, useEnsAvatar } from 'wagmi'
import { hardhat, localhost, mainnet } from 'wagmi/chains'
import { normalize } from 'viem/ens'
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
import Verify from './pages/Verify'
import DemoReceipt from './pages/DemoReceipt'
import { TEST_ACCOUNT_ENABLED } from './config'

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

    // ENS resolution always queries mainnet, regardless of which chain the
    // user is voting on. Returns null for addresses without ENS (e.g. the
    // 0xf39F... Hardhat test account); the UI falls back to truncated address.
    const { data: ensName } = useEnsName({ address, chainId: mainnet.id })
    const { data: ensAvatar } = useEnsAvatar({
        name: ensName ? normalize(ensName) : undefined,
        chainId: mainnet.id,
    })
    const {
        connect,
        connectAsync,
        connectors,
        error: connectHookError,
        reset: resetConnect,
    } = useConnect()
    const { disconnect } = useDisconnect()
    const chainId = useChainId()
    // Same anti-pattern as useConnect: the sync `switchChain()` is fire-and-forget;
    // rejections (user clicks Reject in MetaMask, or wallet doesn't support
    // wallet_switchEthereumChain) land in `error`, never in any await chain. Use
    // switchChainAsync + try/catch + reset to surface them.
    const {
        switchChainAsync,
        error: switchChainHookError,
        reset: resetSwitchChain,
    } = useSwitchChain()

    // Theme switcher — three remap themes that share the `db-*` token names
    // (see index.css :root.theme-X blocks). Default = bauhaus.
    type ThemeName = 'bauhaus' | 'brutalist' | 'cyberpunk'
    const THEME_LABELS: Record<ThemeName, string> = {
        bauhaus: 'Dark Bauhaus',
        brutalist: 'Brutalist',
        cyberpunk: 'Cyberpunk',
    }
    const THEME_ORDER: ThemeName[] = ['bauhaus', 'brutalist', 'cyberpunk']
    const [theme, setTheme] = useState<ThemeName>(() => {
        if (typeof window !== 'undefined') {
            const stored = localStorage.getItem('theme') as ThemeName | null
            if (stored && THEME_ORDER.includes(stored)) return stored
        }
        return 'bauhaus'
    })

    useEffect(() => {
        const root = document.documentElement
        // `dark` class kept for legacy Tailwind dark: utilities used in the header.
        // Brutalist is the ONLY light-feeling theme; the others are dark.
        root.classList.toggle('dark', theme !== 'brutalist')
        // Strip any prior theme-* class then add the active one.
        for (const t of THEME_ORDER) root.classList.remove(`theme-${t}`)
        root.classList.add(`theme-${theme}`)
        localStorage.setItem('theme', theme)
    }, [theme])

    const cycleTheme = () => {
        const i = THEME_ORDER.indexOf(theme)
        setTheme(THEME_ORDER[(i + 1) % THEME_ORDER.length] as ThemeName)
    }

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

    // The injected connector wraps window.ethereum (MetaMask, Rabby, Brave, etc.).
    // Falls back to whatever non-mock connector exists, then connectors[0] as a
    // last resort (used to be hardcoded to look up by name "MetaMask" — that
    // matched the now-removed wagmi metaMask() SDK connector and would no longer
    // resolve even with the old connector list).
    const injectedConnector =
        connectors.find(c => c.id === 'injected') ??
        connectors.find(c => c.id !== 'mock') ??
        connectors[0]

    // Surfaces the "no injected provider" case to the user. Without this, a
    // click on Connect Wallet from a browser without MetaMask runs the handler
    // silently (window.ethereum is undefined → addHardhatNetwork early-returns,
    // wagmi connector no-ops) and the button looks broken.
    const [connectError, setConnectError] = useState<string | null>(null)

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
                        {/* Theme cycle: Bauhaus → Brutalist → Cyberpunk → ...
                          * Each click rotates and persists the choice in localStorage.
                          * Replaces the old dark/light toggle (which only worked in
                          * the header — page content stayed dark either way). */}
                        <button
                            onClick={cycleTheme}
                            className="px-3 py-2.5 bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 hover:bg-stone-100 dark:hover:bg-stone-700 text-stone-600 dark:text-stone-300 rounded-xl text-xs font-mono uppercase tracking-wider transition-colors min-h-[44px] cursor-pointer flex items-center gap-2"
                            aria-label={`Cycle theme (current: ${THEME_LABELS[theme]})`}
                            title={`Theme: ${THEME_LABELS[theme]} — click to cycle`}
                        >
                            {theme === 'brutalist' ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
                            <span className="hidden md:inline">{THEME_LABELS[theme]}</span>
                        </button>

                        {!isConnected ? (
                            <>
                                {TEST_ACCOUNT_ENABLED && (
                                    <button
                                        onClick={() => {
                                            setConnectError(null)
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
                                        if (typeof window !== 'undefined' && !window.ethereum) {
                                            setConnectError(
                                                TEST_ACCOUNT_ENABLED
                                                    ? 'No wallet detected. Install MetaMask, or click "Test Account" to use a Hardhat dev wallet.'
                                                    : 'No wallet detected. Install MetaMask (or another EIP-1193 provider) to connect.',
                                            )
                                            return
                                        }
                                        setConnectError(null)
                                        await addHardhatNetwork()
                                        if (!injectedConnector) {
                                            setConnectError('No injected connector available. This is a bundling bug; please report it.')
                                            return
                                        }
                                        try {
                                            // connectAsync surfaces rejections; the sync `connect()` swallows
                                            // them into useConnect().error which can be missed.
                                            await connectAsync({ connector: injectedConnector })
                                        } catch (err) {
                                            const e = err as { shortMessage?: string; message?: string; name?: string }
                                            setConnectError(
                                                e.shortMessage ??
                                                    e.message ??
                                                    `Connection failed${e.name ? ` (${e.name})` : ''}.`,
                                            )
                                        }
                                    }}
                                    className="inline-flex items-center gap-2 px-5 py-2.5 bg-stone-900 dark:bg-stone-100 hover:bg-stone-800 dark:hover:bg-stone-200 active:bg-stone-950 dark:active:bg-stone-300 text-white dark:text-stone-900 rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer"
                                >
                                    <Wallet className="w-4 h-4" />
                                    Connect Wallet
                                </button>
                            </>
                        ) : (
                            <>
                                {/* Address badge — shows ENS name when available, else truncated.
                                  * Avatar (if ENS has one) replaces the live-status pulse dot. */}
                                <div
                                    className="hidden sm:flex items-center gap-2 px-4 py-2 bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl text-sm text-stone-700 dark:text-stone-300 min-h-[44px]"
                                    title={address}
                                >
                                    {ensAvatar ? (
                                        <img
                                            src={ensAvatar}
                                            alt=""
                                            className="w-5 h-5 rounded-full object-cover shrink-0"
                                            referrerPolicy="no-referrer"
                                        />
                                    ) : (
                                        <span className="relative flex items-center justify-center w-2.5 h-2.5 shrink-0">
                                            <span className="absolute inline-flex h-full w-full rounded-full bg-teal-400 opacity-75 animate-ping" />
                                            <span className="relative inline-flex rounded-full h-2 w-2 bg-teal-500" />
                                        </span>
                                    )}
                                    <span className={ensName ? 'font-sans font-medium' : 'font-mono'}>
                                        {ensName ?? `${address?.slice(0, 6)}...${address?.slice(-4)}`}
                                    </span>
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

                {/* -- Connect/switch-chain error banner — three sources:
                  *   1. local state (e.g. no window.ethereum)
                  *   2. wagmi useConnect().error (rejected, wrong chain, etc.)
                  *   3. wagmi useSwitchChain().error (rejected switch, unsupported method)
                  * Dismiss must clear all three; banner shows whenever any one is truthy.
                  */}
                {(connectError || connectHookError || switchChainHookError) && (
                    <div className="bg-rose-50 dark:bg-rose-900/30 border-t border-rose-200 dark:border-rose-700">
                        <div className="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3 px-6 py-3 md:px-8">
                            <p className="flex items-center gap-2 text-sm font-semibold text-rose-800 dark:text-rose-300">
                                <AlertTriangle className="w-5 h-5 text-rose-500 shrink-0" />
                                {connectError ??
                                    connectHookError?.message ??
                                    switchChainHookError?.message ??
                                    'Connection failed.'}
                            </p>
                            <div className="flex items-center gap-2">
                                <a
                                    href="https://metamask.io/download/"
                                    target="_blank"
                                    rel="noreferrer noopener"
                                    className="inline-flex items-center gap-2 px-4 py-2 bg-rose-500 hover:bg-rose-600 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer whitespace-nowrap"
                                >
                                    Install MetaMask
                                </a>
                                <button
                                    onClick={() => {
                                        // Three error sources need clearing in lockstep —
                                        // missing any one re-shows the banner instantly because
                                        // wagmi mutation errors are sticky until reset().
                                        setConnectError(null)
                                        resetConnect()
                                        resetSwitchChain()
                                    }}
                                    className="inline-flex items-center gap-2 px-3 py-2 bg-transparent hover:bg-rose-100 dark:hover:bg-rose-900/50 text-rose-700 dark:text-rose-300 rounded-xl text-sm font-medium transition-colors min-h-[44px] cursor-pointer"
                                    aria-label="Dismiss connection error"
                                >
                                    Dismiss
                                </button>
                            </div>
                        </div>
                    </div>
                )}

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
                                    setConnectError(null)
                                    resetSwitchChain()
                                    await addHardhatNetwork()
                                    try {
                                        await switchChainAsync({ chainId: hardhat.id })
                                    } catch (err) {
                                        // Falls through to switchChainHookError via the rose
                                        // banner above, but also set local state so the message
                                        // is friendly even when wagmi's `error.message` is RPC-shaped.
                                        const e = err as { shortMessage?: string; message?: string }
                                        setConnectError(
                                            e.shortMessage ??
                                                e.message ??
                                                'Switching networks failed.',
                                        )
                                    }
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
                    <Route path="/verify" element={<Verify />} />
                    <Route path="/demo/receipt" element={<DemoReceipt />} />
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
