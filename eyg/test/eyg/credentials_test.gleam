import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/http/response
import gleam/io
import gleam/json
import gleam/result
import gleam/string
import plinth/browser/credentials

const recording = credentials.PublicKeyCredential(
  "cross-platform",
  "Id8gys2-vHRr5GNrcK0JbQ",
  <<33, 223, 32, 202, 205, 190, 188, 116, 107, 228, 99, 107, 112, 173, 9, 109>>,
  credentials.AuthenticatorAttestationResponse(
    attestation_object: <<
      163, 99, 102, 109, 116, 100, 110, 111, 110, 101, 103, 97, 116, 116, 83,
      116, 109, 116, 160, 104, 97, 117, 116, 104, 68, 97, 116, 97, 88, 148, 73,
      150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143,
      228, 174, 185, 162, 134, 50, 199, 153, 92, 243, 186, 131, 29, 151, 99, 93,
      0, 0, 0, 0, 234, 155, 141, 102, 77, 1, 29, 33, 60, 228, 182, 180, 140, 181,
      117, 212, 0, 16, 33, 223, 32, 202, 205, 190, 188, 116, 107, 228, 99, 107,
      112, 173, 9, 109, 165, 1, 2, 3, 38, 32, 1, 33, 88, 32, 190, 106, 58, 76,
      197, 112, 254, 33, 233, 100, 43, 125, 205, 227, 122, 55, 60, 159, 41, 186,
      236, 129, 231, 102, 51, 100, 104, 232, 90, 128, 164, 104, 34, 88, 32, 224,
      86, 31, 9, 71, 46, 144, 24, 104, 221, 198, 5, 174, 44, 60, 36, 177, 163,
      28, 77, 59, 206, 198, 178, 73, 222, 222, 197, 63, 41, 241, 145,
    >>,
    client_data_json: <<
      123, 34, 116, 121, 112, 101, 34, 58, 34, 119, 101, 98, 97, 117, 116, 104,
      110, 46, 99, 114, 101, 97, 116, 101, 34, 44, 34, 99, 104, 97, 108, 108,
      101, 110, 103, 101, 34, 58, 34, 65, 65, 69, 67, 34, 44, 34, 111, 114, 105,
      103, 105, 110, 34, 58, 34, 104, 116, 116, 112, 58, 47, 47, 108, 111, 99,
      97, 108, 104, 111, 115, 116, 58, 56, 48, 56, 48, 34, 44, 34, 99, 114, 111,
      115, 115, 79, 114, 105, 103, 105, 110, 34, 58, 102, 97, 108, 115, 101, 125,
    >>,
  ),
  type_: "public-key",
)

@external(javascript, "../cbor_ffi.mjs", "decode")
fn decode_cbor(input: BitArray) -> Dynamic

type WebAuthn {
  WebAuthnCreate
  WebAuthnGet
}

type ClientData {
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

fn client_data_decoder(raw) {
  dynamic.decode4(
    ClientData,
    dynamic.field("challenge", base64),
    dynamic.field("crossOrigin", dynamic.bool),
    dynamic.field("origin", dynamic.string),
    dynamic.field("type", webauthn_type),
  )(raw)
}

type AttestationObject {
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
    False -> Error(given <> " did not match expected value of " <> expected)
  }
}

fn verify(credentials) {
  let credentials.PublicKeyCredential(
    authenticator_attachment,
    id,
    raw_id,
    credentials.AuthenticatorAttestationResponse(
      attestation_object,
      client_data_json,
    ),
    type_,
  ) = credentials

  use Nil <- result.try(case bit_array.base64_url_decode(id) {
    Ok(x) if x == raw_id -> Ok(Nil)
    _ -> Error("id and raw don't match")
  })
  use Nil <- result.try(case type_ {
    "public-key" -> Ok(Nil)
    _ -> Error("type needs to be public-key")
  })
  use ClientData(challenge, cross, origin, type_) <- result.try(
    json.decode_bits(client_data_json, client_data_decoder)
    |> result.map_error(string.inspect),
  )
  use Nil <- result.try(case type_ {
    WebAuthnCreate -> Ok(Nil)
    _ -> Error("type needs to be create")
  })
  use Nil <- result.try(case challenge {
    <<0, 1, 2>> -> Ok(Nil)
    _ -> Error("challenge is not correct")
  })
  use Nil <- result.try(assert_equal(origin, "http://localhost:8080"))
  use AttestationObject(fmt, data) <- result.try(
    attestation_object
    |> decode_cbor
    |> attestation_object_decoder
    |> result.map_error(string.inspect),
  )
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
      io.debug(rp_id_hash)
      // io.debug(credentials_length)
      io.debug(rest)
      io.debug("======================")
      bit_array.slice(rest, credentials_length, bit_array.byte_size(rest))
      |> io.debug
      // let assert <<id:size(credentials_length), public:bytes>> = rest
      // io.debug(id)
    }
    _ -> todo as "no match"
  }
  // io.debug(data)
  Ok(Nil)
}

pub fn verify_test() {
  verify(recording)
  |> io.debug
  todo
}
