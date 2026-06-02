import eyg/interpreter/value as v
import gleam/dict
import touch_grass/cryptography/create_key

pub fn decode_eddsa_request_test() {
  // CreateKey is performed with `Eddsa(opts)`; the options are ignored.
  let request = v.Tagged("Eddsa", v.unit())
  let assert Ok(create_key.Eddsa) = create_key.decode(request)
}

pub fn decode_eddsa_ignores_options_test() {
  let request =
    v.Tagged("Eddsa", v.Record(dict.from_list([#("extractable", v.true())])))
  let assert Ok(create_key.Eddsa) = create_key.decode(request)
}

pub fn decode_rejects_unknown_algorithm_test() {
  let request = v.Tagged("Rsa", v.unit())
  let assert Error(_) = create_key.decode(request)
}

pub fn encode_eddsa_key_is_jwk_shaped_test() {
  let key =
    create_key.EddsaKey(public_key: <<1, 2, 3>>, private_key: <<4, 5, 6>>)
  let assert v.Tagged("Ok", v.Tagged("Eddsa", v.Record(fields))) =
    create_key.encode(Ok(key))

  assert dict.get(fields, "kty") == Ok(v.String("OKP"))
  assert dict.get(fields, "crv") == Ok(v.String("Ed25519"))
  assert dict.get(fields, "x") == Ok(v.Binary(<<1, 2, 3>>))
  assert dict.get(fields, "d") == Ok(v.Binary(<<4, 5, 6>>))
}

pub fn encode_error_is_result_error_test() {
  assert create_key.encode(Error("no entropy"))
    == v.error(v.String("no entropy"))
}
