import eyg/interpreter/value as v
import gleam/dict
import touch_grass/cryptography/create_key
import touch_grass/cryptography/sign

fn eddsa_key(public_key, private_key) {
  create_key.encode_key(create_key.EddsaKey(public_key:, private_key:))
}

fn request(key, data) {
  v.Record(dict.from_list([#("key", key), #("data", v.Binary(data))]))
}

pub fn decode_eddsa_sign_request_test() {
  let key = eddsa_key(<<1, 2, 3>>, <<9, 9, 9>>)
  let assert Ok(sign.EddsaSign(private_key:, data:)) =
    sign.decode(request(key, <<"message">>))

  // The private seed (`d`) and the data are surfaced for the host to sign.
  assert private_key == <<9, 9, 9>>
  assert data == <<"message">>
}

pub fn decode_rejects_non_binary_data_test() {
  let key = eddsa_key(<<1>>, <<2>>)
  let bad = v.Record(dict.from_list([#("key", key), #("data", v.Integer(1))]))
  let assert Error(_) = sign.decode(bad)
}

pub fn decode_rejects_unknown_algorithm_test() {
  let key = v.Tagged("Rsa", v.unit())
  let assert Error(_) = sign.decode(request(key, <<"message">>))
}

pub fn encode_signature_is_ok_binary_test() {
  assert sign.encode(Ok(<<7, 7, 7>>)) == v.ok(v.Binary(<<7, 7, 7>>))
}

pub fn encode_error_is_result_error_test() {
  assert sign.encode(Error("bad key")) == v.error(v.String("bad key"))
}
