import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function serve(bun, options) {
  try { return Result$Ok(bun.serve({ port: options.port, hostname: options.hostname, fetch: options.fetch })); }
  catch (error) { return Result$Error(String(error)); }
}
export const port = server => server.port;
export async function stop(server, force) {
  try { await server.stop(force); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
