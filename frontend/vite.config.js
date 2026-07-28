import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// Vite config. During dev we proxy /api to the backend ingress so the SPA can
// use relative URLs and avoid CORS. The proxy target comes from VITE_API_BASE_URL.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const target = env.VITE_API_BASE_URL || 'http://localhost:8080'
  return {
    plugins: [react()],
    server: {
      port: 5173,
      proxy: {
        '/api': {
          target,
          changeOrigin: true,
        },
      },
    },
  }
})
