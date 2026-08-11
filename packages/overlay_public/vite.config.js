import { defineConfig } from 'vite'
import gleam from 'vite-gleam'

export default defineConfig({
  base: '/overlay/',
  envPrefix: 'OLLAMA_',
  plugins: [gleam()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: {
      '/api': {
        target: 'https://ollama.com',
        changeOrigin: true,
      },
      '/guides': {
        target: 'https://eyg.run',
        changeOrigin: true,
      },
    },
    watch: {
      usePolling: true, // needed in Docker
    },
  },
})
