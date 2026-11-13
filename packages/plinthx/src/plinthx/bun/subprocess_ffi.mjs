import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function spawnWithInput(bun, options, input) {
  try {
    return Result$Ok(bun.spawn({ cmd: Array.from(options.cmd), cwd: options.cwd, env: Object.fromEntries(options.env),
      stdin: input.buffer, stdout: options.stdout, stderr: options.stderr }));
  } catch (error) { return Result$Error(String(error)); }
}

export async function exited(process) {
  try { return Result$Ok(await process.exited); }
  catch (error) { return Result$Error(String(error)); }
}
export const stdout = process => process.stdout instanceof globalThis.ReadableStream ? Result$Ok(process.stdout) : Result$Error(undefined);
export const stderr = process => process.stderr instanceof globalThis.ReadableStream ? Result$Ok(process.stderr) : Result$Error(undefined);

export async function readableStreamToText(bun, stream) {
  try { return Result$Ok(await bun.readableStreamToText(stream)); }
  catch (error) { return Result$Error(String(error)); }
}
