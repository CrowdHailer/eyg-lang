import { read as nativeRead, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Result$Ok, Result$Error, toBitArray } from "../../gleam.mjs";
export function temporaryDirectory(prefix) {
  try { return Result$Ok(mkdtempSync(join(tmpdir(), prefix))); }
  catch (error) { return Result$Error(String(error)); }
}

export function read(fd, length) {
  return new Promise(resolve => {
    try {
      const buffer = Buffer.alloc(length);
      nativeRead(fd, buffer, 0, length, null, (error, bytesRead) => {
        resolve(error
          ? Result$Error(String(error.code ?? error))
          : Result$Ok(toBitArray([buffer.subarray(0, bytesRead)])));
      });
    } catch (error) {
      resolve(Result$Error(String(error.code ?? error)));
    }
  });
}
