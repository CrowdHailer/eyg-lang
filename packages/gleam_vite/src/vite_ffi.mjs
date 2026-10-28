import { defineConfig } from "vite";
import gleamPlugin from "vite-gleam";

export const configure = (json, plugins) => defineConfig({ ...JSON.parse(json), plugins: Array.from(plugins) });
export const gleam = () => gleamPlugin();
export const plugin = (name, configureServer, changed) => ({
  name, configureServer,
  handleHotUpdate: ({ file, server }) => changed(file, server) ? [] : undefined,
});
export const watch = (server, paths) => { server.watcher.add(Array.from(paths)); };
export const reload = server => { server.ws.send({ type: "full-reload" }); };
