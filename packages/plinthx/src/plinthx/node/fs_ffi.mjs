import { read as nativeRead } from "node:fs";
import { Result$Ok, Result$Error, toBitArray } from "../../gleam.mjs";

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
