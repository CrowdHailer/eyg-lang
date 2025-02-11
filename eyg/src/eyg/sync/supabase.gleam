import eygir/decode
import eygir/expression as e
import gleam/dynamic
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/json
import gleam/result
import gleam/string
import midas/task as t
import snag
import supa/client

pub const client = client.Client(
  "wrdiolbafudgmcgvqhnb.supabase.co",
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndyZGlvbGJhZnVkZ21jZ3ZxaG5iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzM5MzI3NDgsImV4cCI6MjA0OTUwODc0OH0.1NiYvSdqzwekOrHAIlaoD0B6ncI5F1RK8zX6kcTdIJ0",
)

fn base() {
  request.new()
  |> request.set_host(client.host)
  |> request.prepend_header("apikey", client.key)
  // Authorization header needed for auth endpoint
  |> request.prepend_header("Authorization", "Bearer " <> client.key)
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
  Fragment(hash: String, created_at: String, code: e.Expression)
}

fn fragment_decoder(raw) {
  dynamic.decode3(
    Fragment,
    dynamic.field("hash", dynamic.string),
    dynamic.field("created_at", dynamic.string),
    dynamic.field("code", decode.decode_dynamic_error),
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
