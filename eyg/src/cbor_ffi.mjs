import CBOR from "cbor-sync";
import * as tinyCbor from "@levischuck/tiny-cbor";

export function decode(bitArray) {
  // tinyCbor.decodePartialCBOR(_input, 0)
  let [decoded] =tinyCbor.decodePartialCBOR(bitArray.buffer, 0)
  return Object.fromEntries(decoded)
}