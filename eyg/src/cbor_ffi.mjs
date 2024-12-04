import CBOR from "cbor-sync";
import * as tinyCbor from "@levischuck/tiny-cbor";
import cbor from "cbor";


export function decodeOther(bitArray) {
  let x = cbor.decode(bitArray.buffer)
  // console.log(x)
  return x
}

export function decode(bitArray) {
  // tinyCbor.decodePartialCBOR(_input, 0)
  let [decoded] = tinyCbor.decodePartialCBOR(bitArray.buffer, 0)
  return Object.fromEntries(decoded)
}

import * as SimpleWebAuthnServer from '@simplewebauthn/server';
const verify = SimpleWebAuthnServer.verifyRegistrationResponse
export async function justAttest(body) {
  const response = JSON.parse(body)
  const expectedChallenge = "dXNlZCBpbiBhdHRlc3RhdGlvbg"
  const expectedOrigin = "http://localhost:8080"
  const { verified, registrationInfo } = await verify({ response, expectedChallenge, expectedOrigin })
  return [verified, registrationInfo]
}
const assert = SimpleWebAuthnServer.verifyAuthenticationResponse

export async function justAssert(body, key) {
  const response = JSON.parse(body)
  const expectedChallenge = "bXkgZmlyc3QgY29tbWl0"
  const expectedOrigin = "http://localhost:8080"
  const expectedRPID = "localhost"
  const credential = {publicKey: key.buffer}
  const out = await assert({ response, expectedChallenge, expectedOrigin ,expectedRPID,credential})
  console.log("OOUT",out)
  return [verified, registrationInfo]
}