import { Result$Ok, Result$Error, toList } from '../../gleam.mjs';
export async function build(bun, options) {
  try { return Result$Ok(await bun.build(JSON.parse(options))); }
  catch (error) { return Result$Error(String(error)); }
}
export const success = build => build.success;
export const logs = build => toList(build.logs.map(String));
export const outputs = build => toList(build.outputs);
export const text = artifact => artifact.text();
