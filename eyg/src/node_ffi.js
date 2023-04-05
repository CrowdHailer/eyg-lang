import * as crypto from "node:crypto";

export function hash(array) {
  return crypto.createHash("sha1").update(array.buffer).digest("hex");
}
