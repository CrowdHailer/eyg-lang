import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/option.{Some}
import gleam/result.{try}
import plinth/browser/credentials
import plinth/browser/credentials/public_key

pub const l = "Stamp"

pub const lift = t.Binary

pub fn lower() {
  t.result(t.Binary, t.String)
}

pub fn type_() {
  #(l, #(lift, lower()))
}

pub fn cast(lift) {
  cast.as_binary(lift)
}

pub fn run(bytes) {
  promise.map(do(bytes), result_to_eyg)
}

pub fn do(max) {
  use container <- promise.try_await(
    credentials.from_navigator()
    |> result.replace_error("credentials unavailable in browser")
    |> promise.resolve,
  )
  // The user_id is the profile
  let user_id = <<123>>
  // challenge will be hash of what's gone before
  let challenge = <<33>>
  let options =
    public_key.creation(
      challenge,
      public_key.ES256,
      "EYG",
      user_id,
      "account",
      "My Device",
    )
  let options =
    public_key.CreationOptions(
      ..options,
      authenticator_attachement: Some(public_key.Platform),
      resident_key: public_key.Discouraged,
    )
  // Just use webauthn for a bit
  // How to make sure that you don't create a new key
  // apple will always sync
  use result <- promise.await(public_key.create(container, options))
  echo result
  promise.resolve(result)
}

pub fn result_to_eyg(result) {
  case result {
    Ok(response) -> v.ok(todo)
    Error(reason) -> v.error(v.String(reason))
  }
}
