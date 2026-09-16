import { defineConfig } from 'vite'
import gleam from 'vite-gleam'
import { resolve } from 'node:path'

// The hub the page resolves contexts and packages from. Set EYG_HUB to point at
// a hub running locally.
const hub = process.env.EYG_HUB ?? 'https://eyg.run'
function watchGleamDependencies(packagePaths) {
  const srcPaths = packagePaths.map((path) => resolve(path, 'src'))
  return {
    name: 'watch-gleam-dependencies',
    configureServer(server) {
      server.watcher.add(srcPaths)
    },
    handleHotUpdate({ file, server }) {
      if (srcPaths.some((srcPath) => file.startsWith(srcPath)) && file.endsWith('.gleam')) {
        // vite-gleam rebuilds the package; Vite needs a reload for its emitted module.
        server.ws.send({ type: 'full-reload' })
        return []
      }
    },
  }
}


export default defineConfig({
  base: '/overlay/',
  plugins: [gleam(), watchGleamDependencies(['../overlay_web', '../pal'])],
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
      '/modules': {
        target: hub,
        changeOrigin: true,
      },
      '/packages': {
        target: hub,
        changeOrigin: true,
      },
    },
    watch: {
      usePolling: true, // needed in Docker
    },
  },
})
