import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const lanDev = process.env.VITE_LAN_DEV === '1'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    ...(lanDev ? { host: true, allowedHosts: true } : { host: 'localhost' }),
  },
})
