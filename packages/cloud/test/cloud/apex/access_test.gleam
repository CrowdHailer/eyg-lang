import cloud/apex/access
import cloud/apex/server
import cloud/helpers
import gleam/bit_array
import gleam/http
import wisp/simulate

fn basic(credentials) {
  Ok("Basic " <> bit_array.base64_encode(<<credentials:utf8>>, True))
}

pub fn local_access_test() {
  assert "127.0.0.1" == access.bind(access.Local)
  assert access.allowed(access.Local, Error(Nil))
}

pub fn password_access_test() {
  let password = access.Password("s3cret")
  assert "0.0.0.0" == access.bind(password)
  // Any user name with the password is let in.
  assert access.allowed(password, basic("me:s3cret"))
  assert access.allowed(password, basic(":s3cret"))
  assert !access.allowed(password, basic("me:wrong"))
  assert !access.allowed(password, basic("s3cret"))
  assert !access.allowed(password, Ok("Bearer s3cret"))
  assert !access.allowed(password, Ok("Basic not base64"))
  assert !access.allowed(password, Error(Nil))
}

pub fn api_needs_the_password_test() {
  use context <- helpers.context()
  let handle = server.handler(context, access.Password("s3cret"))
  assert 401 == handle(simulate.request(http.Get, "/boxes")).status
  let response =
    simulate.request(http.Get, "/boxes")
    |> simulate.header("authorization", {
      let assert Ok(header) = basic("me:s3cret")
      header
    })
    |> handle
  assert 200 == response.status
  // Health checks do not need it.
  assert 200 == handle(simulate.request(http.Get, "/health")).status
}
