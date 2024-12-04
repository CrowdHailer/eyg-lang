import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/http/response
import gleam/io
import gleam/javascript/map.{type Map}
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/result
import gleam/string
import gleeunit/should
import plinth/browser/credentials
import plinth/browser/credentials/public_key
import plinth/browser/crypto/subtle

const create_credentials = "{\"authenticatorAttachment\":\"cross-platform\",\"clientExtensionResults\":{},\"id\":\"6Dl8NoapOzxuvFFx8LpO0A\",\"rawId\":\"6Dl8NoapOzxuvFFx8LpO0A\",\"response\":{\"attestationObject\":\"o2NmbXRkbm9uZWdhdHRTdG10oGhhdXRoRGF0YViUSZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2NdAAAAAOqbjWZNAR0hPOS2tIy1ddQAEOg5fDaGqTs8brxRcfC6TtClAQIDJiABIVggsGbipYhVHO6j0xErAoDMxtKdyBDhwaP5_ohxSFSteHYiWCAR1aKgOd3Olw1k7pUbJqmU6Ga7XxBSbCEVQTBdy4AQXQ\",\"authenticatorData\":\"SZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2NdAAAAAOqbjWZNAR0hPOS2tIy1ddQAEOg5fDaGqTs8brxRcfC6TtClAQIDJiABIVggsGbipYhVHO6j0xErAoDMxtKdyBDhwaP5_ohxSFSteHYiWCAR1aKgOd3Olw1k7pUbJqmU6Ga7XxBSbCEVQTBdy4AQXQ\",\"clientDataJSON\":\"eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIiwiY2hhbGxlbmdlIjoiZFhObFpDQnBiaUJoZEhSbGMzUmhkR2x2YmciLCJvcmlnaW4iOiJodHRwOi8vbG9jYWxob3N0OjgwODAiLCJjcm9zc09yaWdpbiI6ZmFsc2UsIm90aGVyX2tleXNfY2FuX2JlX2FkZGVkX2hlcmUiOiJkbyBub3QgY29tcGFyZSBjbGllbnREYXRhSlNPTiBhZ2FpbnN0IGEgdGVtcGxhdGUuIFNlZSBodHRwczovL2dvby5nbC95YWJQZXgifQ\",\"publicKey\":\"MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEsGbipYhVHO6j0xErAoDMxtKdyBDhwaP5_ohxSFSteHYR1aKgOd3Olw1k7pUbJqmU6Ga7XxBSbCEVQTBdy4AQXQ\",\"publicKeyAlgorithm\":-7,\"transports\":[\"hybrid\",\"internal\"]},\"type\":\"public-key\"}"

const get_credentials = "{\"authenticatorAttachment\":\"cross-platform\",\"clientExtensionResults\":{},\"id\":\"6Dl8NoapOzxuvFFx8LpO0A\",\"rawId\":\"6Dl8NoapOzxuvFFx8LpO0A\",\"response\":{\"authenticatorData\":\"SZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2MdAAAAAA\",\"clientDataJSON\":\"eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiYlhrZ1ptbHljM1FnWTI5dGJXbDAiLCJvcmlnaW4iOiJodHRwOi8vbG9jYWxob3N0OjgwODAiLCJjcm9zc09yaWdpbiI6ZmFsc2V9\",\"signature\":\"MEQCHxn-UJOAx0tiaIExqcToMg8aIKXvWMygf4EhDQ31bsMCIQDkP9tgFMEmFaXEoif4IEQBRCvI4NrDC-sUfliGZg2tlw\",\"userHandle\":\"dGVzdA\"},\"type\":\"public-key\"}"

@external(javascript, "../cbor_ffi.mjs", "decode")
fn decode_cbor(input: BitArray) -> Dynamic

@external(javascript, "../cbor_ffi.mjs", "decodeOther")
fn decode_cbor_other(input: BitArray) -> Map(Int, Dynamic)

@external(javascript, "../cbor_ffi.mjs", "justAttest")
fn just_attest(input: String) -> Promise(#(Bool, Dynamic))

@external(javascript, "../cbor_ffi.mjs", "justAssert")
fn just_assert(input: String, key: BitArray) -> Promise(#(Bool, Dynamic))

pub type Credential(response) {
  Credential(
    authenticator_attachment: public_key.AuthenticatorAttachement,
    id: String,
    raw_id: BitArray,
    response: response,
  )
}

pub fn credential_decoder(raw, response_decoder) {
  dynamic.decode4(
    Credential,
    dynamic.field("authenticatorAttachment", authenticator_attachment_decoder),
    dynamic.field("id", dynamic.string),
    dynamic.field("rawId", base64),
    dynamic.field("response", response_decoder),
  )(raw)
}

fn authenticator_attachment_decoder(raw) {
  use str <- result.try(dynamic.string(raw))
  case str {
    "platform" -> Ok(public_key.Platform)
    "cross-platform" -> Ok(public_key.CrossPlatform)
    _ ->
      Error([
        dynamic.DecodeError("authenticator attachment type", "not valid", []),
      ])
  }
}

pub type AuthenticatorAttestationResponse {
  AuthenticatorAttestationResponse(
    attestation_object: AttestationObject,
    client_data_json: ClientData,
  )
}

pub fn attestation_decoder(raw) {
  dynamic.decode2(
    AuthenticatorAttestationResponse,
    dynamic.field("attestationObject", fn(raw) {
      use bytes <- result.try(base64(raw))
      //   attestation_object
      decode_cbor(bytes)
      |> attestation_object_decoder
    }),
    dynamic.field("clientDataJSON", fn(raw) {
      use bytes <- result.try(base64(raw))
      //   attestation_object
      case json.decode_bits(bytes, client_data_decoder) {
        Ok(value) -> Ok(value)
        Error(reason) ->
          Error([dynamic.DecodeError("validJSON", string.inspect(reason), [])])
      }
      // |> attestation_object_decoder
    }),
  )(raw)
}

pub type AuthenticatorAssertionResponse {
  AuthenticatorAssertionResponse(
    client_data_json: BitArray,
    authenticator_data: BitArray,
    signature: BitArray,
    user_handle: BitArray,
  )
}

fn assertion_response_decoder(raw) {
  dynamic.decode4(
    AuthenticatorAssertionResponse,
    dynamic.field("clientDataJSON", base64),
    dynamic.field("authenticatorData", base64),
    dynamic.field("signature", base64),
    dynamic.field("userHandle", base64),
  )(raw)
}

pub type WebAuthn {
  WebAuthnCreate
  WebAuthnGet
}

pub type ClientData {
  ClientData(
    challenge: BitArray,
    cross_origin: Bool,
    origin: String,
    type_: WebAuthn,
  )
}

fn base64(raw) {
  use str <- result.try(dynamic.string(raw))
  bit_array.base64_url_decode(str)
  |> result.replace_error([dynamic.DecodeError("base64", "not base64", [])])
}

fn webauthn_type(raw) {
  use str <- result.try(dynamic.string(raw))
  case str {
    "webauthn.create" -> Ok(WebAuthnCreate)
    "webauthn.get" -> Ok(WebAuthnGet)
    _ -> Error([dynamic.DecodeError("webauthn type", "not valid", [])])
  }
}

fn client_data_decoder(raw) -> Result(_, List(dynamic.DecodeError)) {
  dynamic.decode4(
    ClientData,
    dynamic.field("challenge", base64),
    dynamic.field("crossOrigin", dynamic.bool),
    dynamic.field("origin", dynamic.string),
    dynamic.field("type", webauthn_type),
  )(raw)
}

pub type AttestationObject {
  AttestationObject(fmt: String, data: BitArray)
}

fn attestation_object_decoder(raw) {
  dynamic.decode2(
    AttestationObject,
    dynamic.field("fmt", dynamic.string),
    dynamic.field("authData", dynamic.bit_array),
  )(raw)
}

fn assert_equal(given, expected) {
  case given == expected {
    True -> Ok(Nil)
    False ->
      Error(
        string.inspect(given)
        <> " did not match expected value of "
        <> string.inspect(expected),
      )
  }
}

pub type AuthenticatorData {
  AuthenticatorData(
    relaying_party_id_hash: BitArray,
    flags: Int,
    sign_count: BitArray,
  )
}

fn parse_authenticator_data(data) {
  case data {
    <<rp_id_hash:32-bytes, flags, sign_count:4-bytes, rest:bytes>> -> {
      Ok(#(AuthenticatorData(rp_id_hash, flags, sign_count), rest))
    }
    _ -> todo as "no match"
  }
}

pub type PublicKey {
  PublicKey(id: BitArray, key: BitArray)
}

pub fn verify_registration(json, expected_challenge) {
  let assert Ok(credentials) =
    json.decode(json, credential_decoder(_, attestation_decoder))
  let Credential(
    authenticator_attachment,
    id,
    raw_id,
    AuthenticatorAttestationResponse(attestation_object, client_data),
  ) = credentials
  use Nil <- result.try(case bit_array.base64_url_decode(id) {
    Ok(x) if x == raw_id -> Ok(Nil)
    _ -> Error("id and raw don't match")
  })
  // use Nil <- result.try(assert_equal(type_, "public-key"))
  // use ClientData(challenge, cross, origin, type_) <- result.try(
  //   json.decode_bits(client_data_json, client_data_decoder)
  //   |> result.map_error(string.inspect),
  // )
  let ClientData(challenge, cross, origin, type_) = client_data
  use Nil <- result.try(assert_equal(type_, WebAuthnCreate))
  use Nil <- result.try(assert_equal(challenge, expected_challenge))
  use Nil <- result.try(assert_equal(origin, "http://localhost:8080"))
  // use AttestationObject(fmt, data) <- result.try(
  //   attestation_object
  //   |> decode_cbor
  //   |> attestation_object_decoder
  //   |> result.map_error(string.inspect),
  // )
  let AttestationObject(fmt, data) = attestation_object
  case data {
    <<
      rp_id_hash:32-bytes,
      flags,
      sign_count:4-bytes,
      aaguid:16-bytes,
      // This 16 is bits
      credentials_length:16,
      rest:bytes,
    >> -> {
      io.debug(#("flags", flags))
      // io.debug(rp_id_hash)
      // promise.map(
      //   subtle.digest(subtle.SHA256, bit_array.from_string("localhost")),
      //   io.debug,
      // )
      // |> io.debug
      // io.debug(credentials_length)
      // io.debug(#(rest, credentials_length, bit_array.byte_size(rest)))
      // io.debug("======================")
      use credentials_id <- result.try(
        bit_array.slice(rest, 0, credentials_length)
        |> result.replace_error("failed to extract credentials_id"),
      )
      // io.debug(rest)
      use credentials_public_key <- result.try(
        bit_array.slice(
          rest,
          credentials_length,
          bit_array.byte_size(rest) - credentials_length,
        )
        |> result.replace_error("failed to extract credentials_public_key"),
      )
      use Nil <- result.try(assert_equal(credentials_id, raw_id))
      Ok(PublicKey(credentials_id, credentials_public_key))
    }
    _ -> todo as "no match"
  }
}

pub fn authentication_test() {
  use #(verified, info) <- promise.map(just_attest(create_credentials))
  verified
  |> should.equal(True)
  let assert Ok(pk) =
    dynamic.field("credential", dynamic.field("publicKey", dynamic.bit_array))(
      info,
    )
  just_assert(get_credentials, pk)
  // let PublicKey(id, key) =
  //   verify_registration(create_credentials, <<"used in attestation">>)
  //   |> should.be_ok
  // io.debug(#("id from reg", id))
  // use r <- promise.map(verify_assertion(get_credentials, key))
  // r
  // |> io.debug
}

fn verify_assertion(json, cose_key) {
  // needs to be binary for signature data
  let assert Ok(credentials) =
    json.decode(json, credential_decoder(_, assertion_response_decoder))
  // |> io.debug
  let Credential(authenticator_attachment, id, raw_id, response) = credentials
  io.debug(#(
    "id from auth",
    id,
    raw_id,
    bit_array.base64_url_encode(raw_id, False),
  ))
  // io.debug(cose_key)
  io.debug("KEY DECOG")
  let m =
    cose_key
    // |> bit_array.slice(10, bit_array.byte_size(cose_key) - 10)
    // |> should.be_ok
    |> decode_cbor_other()

  let ec2 = dynamic.from(2)
  let ecdsa = dynamic.from(-7)

  let key = case map.get(m, 1), map.get(m, 3) {
    Ok(kty), Ok(alg) if kty == ec2 && alg == ecdsa -> {
      let assert Ok(crv) = map.get(m, -1)
      let assert Ok(1) = dynamic.int(crv)
      let assert Ok(x) = map.get(m, -2)
      let assert Ok(x) = dynamic.bit_array(x)
      let assert Ok(y) = map.get(m, -3)
      let assert Ok(y) = dynamic.bit_array(y)
      io.debug(#(x, y))
      json.object([
        #("kty", json.string("EC")),
        #("crv", json.string("P-256")),
        #("x", json.string(bit_array.base64_url_encode(x, False))),
        #("y", json.string(bit_array.base64_url_encode(y, False))),
        #("ext", json.bool(True)),
      ])
    }
    _, _ -> panic as "unhandled"
  }

  let AuthenticatorAssertionResponse(
    client_data,
    authenticator_data,
    signature,
    user_id,
  ) = response
  use client_data_hash <- promise.await(subtle.digest(
    subtle.SHA256,
    client_data,
  ))
  let assert Ok(client_data_hash) = client_data_hash
  subtle.verify(<<>>, key, signature, <<
    authenticator_data:bits,
    client_data_hash:bits,
  >>)
  // io.debug(parse_authenticator_data(authenticator_data))
  // io.debug("GOOD")
  // #(id, raw_id)
}
