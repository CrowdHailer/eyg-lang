// emitting assets adds a file that is considered complete, vite does no translation of it.
// emitting a chunk is looked at as an entrypoint for rollup, but rollup assumes it is a JS module.
// Rollup/Rolldown use files as entry points and then treeshake. Use a thin wrapper that calles just the needed functions for a individual entrypoint.
import { defineConfig } from 'vite'
import { readFileSync, readdirSync } from "fs";
import { execSync } from "child_process";
import gleam from 'vite-gleam'
import { resolve, join } from "path";
export default defineConfig({
 
  plugins: [gleam(), ssg()],
  server: {
    port: 5173,
    historyApiFallback: true,
  },
})

function getPackageName() {
  const toml = readFileSync("./gleam.toml", "utf8");
  return toml.match(/^name\s*=\s*"(.+)"/m)[1];
}

async function generatePages() {
  console.log("Compiling Gleam...");
  execSync("gleam build", { stdio: "inherit" });
  let project = getPackageName()
  let dir = `./build/dev/javascript/${project}/${project}/routes`
  let files = readdirSync(dir)
  
  const routeMap = new Map();
  for (const file of files) {
    if (!file.endsWith(".mjs")) continue;
    const fullPath = resolve(dir, file);
    const module = await import(`${fullPath}?update=${Date.now()}`);
    const html = module.render()
    
    const route = "/" + file.replace(".mjs","")
    routeMap.set(route, html);
  }
  return routeMap
}

function ssg() {
  return {
    name: "gleamStatic",

    // DEV: serve pages from memory
    async configureServer(server) {
      let routes = await generatePages(); // once on start
      server.watcher.add("src/**/*.gleam");
      server.watcher.on('change', async f => {
        if (f.endsWith(".gleam")) {
          routes = await generatePages()
          server.ws.send({ type: 'full-reload' });
        }
      });
      server.middlewares.use(async (req, res, next) => {
        const rawHtml = routes.get(req.url)
        if (rawHtml) {
          
          const html = await server.transformIndexHtml(req.url, rawHtml);
          res.setHeader('Content-Type', 'text/html');
          res.end(html);
        } else {
          next();
        }
      });
    },


    // PROD: emit into bundle
    async generateBundle() {
      const pages = await generatePages();
      for (const [fileName, source] of pages) {
        this.emitFile({ type: 'asset', fileName: fileName.replace(/^\//,""), source });
      }
    }
  }
}