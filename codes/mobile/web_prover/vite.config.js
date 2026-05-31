import { resolve } from 'path'
import { defineConfig } from 'vite'

// Bundle entry.js (Semaphore v4 prover) into a single self-contained IIFE at
// codes/mobile/web/zkprover.js, which the Flutter web app loads via a <script>
// tag and calls through dart:js_interop. emptyOutDir:false so we don't wipe the
// generated web/ scaffold (index.html etc.).
export default defineConfig({
  build: {
    lib: {
      entry: resolve(import.meta.dirname, 'entry.js'),
      name: 'ZkProver',
      formats: ['iife'],
      fileName: () => 'zkprover.js',
    },
    outDir: resolve(import.meta.dirname, '../web'),
    emptyOutDir: false,
    minify: true,
  },
})
