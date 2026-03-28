import { defineConfig } from 'vite'
import { execSync } from "child_process";
import { readdirSync, statSync, existsSync, readFileSync } from "fs";
import { resolve, join } from "path";

function getPackageName() {
  const toml = readFileSync("./gleam.toml", "utf8");
  return toml.match(/^name\s*=\s*"(.+)"/m)[1];
}

const outDir = resolve("./generated");

function generatePages() {
  console.log("Running Gleam SSG...");
  execSync(`gleam dev --target javascript pages ${outDir}`, { stdio: "inherit" });
}

function ssg() {
  return {
    name: "gleamStatic",

    configureServer(server) {
      generatePages();
      const devDir = resolve("./dev");
      server.watcher.add(devDir);
      const srcDir = resolve("./src");
      server.watcher.add(srcDir);
      server.watcher.on('change', async f => {
        if (f.endsWith(".gleam")) {
          generatePages()
          server.ws.send({ type: 'full-reload' });
        }
      });

    },
  }
}

function findHtml(dir) {
  return readdirSync(dir).flatMap(file => {
    const full = join(dir, file)
    return statSync(full).isDirectory() ? findHtml(full) : full
  }).filter(f => f.endsWith('.html'))
}

function gleam() {
  return {
    name: "gleam",

    resolveId(source) {
      if (!source.endsWith('.gleam')) return null
      if (!source.startsWith("/src/")) this.error("Gleam imports must be absolute starting at '/src")
      const packageDir = resolve(".", "build", "dev", "javascript", getPackageName())

      let builtPath = source
        .replace(/^\/src/, packageDir)
        .replace(/\.gleam$/, ".mjs")

      if (!existsSync(builtPath)) {
        this.error(`Gleam build output not found: ${builtPath}. Did you run 'gleam build'?`)
      }

      return { id: builtPath }
    }
  }
}

export default defineConfig({
  plugins: [gleam(), ssg()],
  root: outDir,
  server: {
    port: 5173,
    // historyApiFallback: true,
  },
  build: {
    rollupOptions: {
      input: findHtml(outDir).reduce((acc, file) => {
        const name = file.replace(outDir + '/', '').replace('.html', '')
        acc[name] = file
        return acc
      }, {})
    }
  }
})


