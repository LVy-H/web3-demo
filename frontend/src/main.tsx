import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { config } from './config'
import App from './App'
import './index.css'

// Prevent browser extensions (MetaMask) from crashing React when they modify the DOM.
// Use try/catch instead of skipping removal — skipping breaks React reconciliation.
if (typeof Node.prototype.removeChild === 'function') {
  const origRemoveChild = Node.prototype.removeChild
  Node.prototype.removeChild = function <T extends Node>(child: T): T {
    try {
      return origRemoveChild.call(this, child) as T
    } catch {
      return child
    }
  }
}
if (typeof Node.prototype.insertBefore === 'function') {
  const origInsertBefore = Node.prototype.insertBefore
  Node.prototype.insertBefore = function <T extends Node>(newNode: T, refNode: Node | null): T {
    try {
      return origInsertBefore.call(this, newNode, refNode) as T
    } catch {
      return newNode
    }
  }
}

const queryClient = new QueryClient()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </WagmiProvider>
  </StrictMode>,
)
