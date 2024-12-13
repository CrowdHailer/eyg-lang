import eygir/decode
import eygir/expression as e
import gleam/dynamic
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/json
import gleam/pair
import gleam/result
import gleam/string
import midas/task as t
import snag

const anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndyZGlvbGJhZnVkZ21jZ3ZxaG5iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzM5MzI3NDgsImV4cCI6MjA0OTUwODc0OH0.1NiYvSdqzwekOrHAIlaoD0B6ncI5F1RK8zX6kcTdIJ0"

const api_host = "wrdiolbafudgmcgvqhnb.supabase.co"

fn base() {
  request.new()
  |> request.set_host(api_host)
  |> request.prepend_header("apikey", anon)
  // Authorization header needed for auth endpoint
  |> request.prepend_header("Authorization", "Bearer " <> anon)
  |> request.set_body(<<>>)
}

fn decode(response: response.Response(_), decoder) {
  case response.status {
    200 ->
      json.decode_bits(response.body, decoder)
      |> result.map_error(fn(reason) { snag.new(string.inspect(reason)) })
    _ -> panic
  }
}

pub fn get_fragments() {
  let request =
    base()
    |> request.set_path("/rest/v1/fragments")
    |> request.set_query([#("select", "*")])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, dynamic.list(fragment_decoder)))
  t.done(data)
}

pub type Fragment {
  Fragment(hash: String, code: e.Expression)
}

fn fragment_decoder(raw) {
  dynamic.decode2(
    Fragment,
    dynamic.field("hash", dynamic.string),
    dynamic.field("code", decode.decoder),
  )(raw)
}

pub fn get_releases() {
  let request =
    base()
    |> request.set_path("/rest/v1/releases")
    |> request.set_query([#("select", "*")])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, dynamic.list(release_decoder)))
  t.done(data)
}

pub type Release {
  Release(package_id: String, version: Int, created_at: String, hash: String)
}

fn release_decoder(raw) {
  dynamic.decode4(
    Release,
    dynamic.field("package_id", dynamic.string),
    dynamic.field("version", dynamic.int),
    dynamic.field("created_at", dynamic.string),
    dynamic.field("hash", dynamic.string),
  )(raw)
}

pub fn get_registrations() {
  let request =
    base()
    |> request.set_path("/rest/v1/registrations")
    |> request.set_query([#("select", "*")])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, dynamic.list(registration_decoder)))
  t.done(data)
}

pub type Registration {
  Registration(id: Int, created_at: String, name: String, package_id: String)
}

fn registration_decoder(raw) {
  dynamic.decode4(
    Registration,
    dynamic.field("id", dynamic.int),
    dynamic.field("created_at", dynamic.string),
    dynamic.field("name", dynamic.string),
    dynamic.field("package_id", dynamic.string),
  )(raw)
}

// invite needs admin
pub fn invite(email_address) {
  let request =
    base()
    |> request.set_method(http.Post)
    |> request.set_path("/auth/v1/invite")
    |> request.set_body(<<
      json.to_string(json.object([#("email", json.string(email_address))])):utf8,
    >>)
  io.debug(request)
  use response <- t.do(t.fetch(request))
  io.debug(response)

  use data <- t.try(decode(response, Ok))
  t.done(data)
}

pub fn sign_in_with_otp(email_address) {
  let request =
    base()
    |> request.set_method(http.Post)
    |> request.set_path("/auth/v1/otp")
    |> request.set_body(<<
      json.to_string(
        json.object([
          #("email", json.string(email_address)),
          #("create_user", json.bool(True)),
        ]),
      ):utf8,
    >>)
  use response <- t.do(t.fetch(request))
  decode_response(response, fn(_) { Ok(Nil) })
}

pub fn verify_otp(email_address, token) {
  let request =
    base()
    |> request.set_method(http.Post)
    |> request.set_path("/auth/v1/verify")
    |> request.set_body(<<
      json.to_string(
        json.object([
          #("email", json.string(email_address)),
          #("token", json.string(token)),
          #("type", json.string("magiclink")),
        ]),
      ):utf8,
    >>)
  use response <- t.do(t.fetch(request))
  decode_response(response, verify_decoder)
}

pub fn verify_decoder(raw) {
  dynamic.decode2(
    pair.new,
    session_decoder,
    dynamic.field("user", user_decoder),
  )(raw)
}

// useful for storage
pub fn verify_to_json(session, user) {
  let User(created_at, email, id) = user
  let user =
    json.object([
      #("created_at", json.string(created_at)),
      #("email", json.string(email)),
      #("id", json.string(id)),
    ])
  let Session(access_token, expires_at, expires_in, refresh_token, token_type) =
    session
  json.object([
    #("access_token", json.string(access_token)),
    #("expires_at", json.int(expires_at)),
    #("expires_in", json.int(expires_in)),
    #("refresh_token", json.string(refresh_token)),
    #("token_type", json.string(token_type)),
    #("user", user),
  ])
}

pub type Session {
  Session(
    access_token: String,
    expires_at: Int,
    expires_in: Int,
    refresh_token: String,
    token_type: String,
  )
}

fn session_decoder(raw) {
  dynamic.decode5(
    Session,
    dynamic.field("access_token", dynamic.string),
    dynamic.field("expires_at", dynamic.int),
    dynamic.field("expires_in", dynamic.int),
    dynamic.field("refresh_token", dynamic.string),
    dynamic.field("token_type", dynamic.string),
  )(raw)
}

pub type User {
  User(created_at: String, email: String, id: String)
}

fn user_decoder(raw) {
  dynamic.decode3(
    User,
    dynamic.field("created_at", dynamic.string),
    dynamic.field("email", dynamic.string),
    dynamic.field("id", dynamic.string),
  )(raw)
}

fn decode_response(response: response.Response(_), decoder) {
  case response.status {
    200 ->
      case json.decode_bits(response.body, decoder) {
        Ok(data) -> t.done(data)
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
    _ ->
      case json.decode_bits(response.body, error_decoder) {
        Ok(reason) -> t.abort(snag.new(reason.message))
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
  }
}

pub type Reason {
  Reason(error: String, message: String)
}

fn error_decoder(raw) {
  dynamic.decode2(
    Reason,
    dynamic.field("error_code", dynamic.string),
    dynamic.field("msg", dynamic.string),
  )(raw)
}
