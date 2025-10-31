import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import midas/task as t
import snag
import supa/client

pub const client = client.Client(
  "wrdiolbafudgmcgvqhnb.supabase.co",
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndyZGlvbGJhZnVkZ21jZ3ZxaG5iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzM5MzI3NDgsImV4cCI6MjA0OTUwODc0OH0.1NiYvSdqzwekOrHAIlaoD0B6ncI5F1RK8zX6kcTdIJ0",
)

fn base(client) {
  let client.Client(host:, key:) = client
  request.new()
  |> request.set_host(host)
  |> request.prepend_header("apikey", key)
  // Authorization header needed for auth endpoint
  |> request.prepend_header("Authorization", "Bearer " <> key)
  |> request.set_body(<<>>)
}

fn decode(response: response.Response(_), decoder) {
  case response.status {
    200 ->
      case json.parse_bits(response.body, decoder) {
        Ok(dyn) -> Ok(dyn)
        Error(reason) -> snag.error(string.inspect(reason))
      }
    _ -> panic
  }
}

pub fn get_fragments(client) {
  let request =
    base(client)
    |> request.set_path("/rest/v1/fragments")
    |> request.set_query([#("select", "*")])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, decode.list(fragment_decoder())))
  t.done(data)
}

pub fn fetch_fragment(client, cid) {
  let request = fetch_fragment_request(client, cid)
  use response <- t.do(t.fetch(request))
  use data <- t.try(fetch_fragment_response(response))
  t.done(data)
}

pub fn fetch_fragment_request(client, cid) {
  base(client)
  |> request.set_path("/rest/v1/fragments")
  |> request.set_query([#("select", "*"), #("hash", "eq." <> cid)])
}

pub fn fetch_fragment_response(response) {
  use data <- result.try(decode(response, decode.list(fragment_decoder())))
  case data {
    [Fragment(code:, ..)] ->
      // Ideally I'd download bytes but we trust supabase
      Ok(code)
    _ -> Error(snag.new("no hash with cid"))
  }
}

pub type Fragment {
  Fragment(hash: String, created_at: String, code: ir.Node(Nil))
}

fn fragment_decoder() {
  use hash <- decode.field("hash", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use code <- decode.field("code", dag_json.decoder(Nil))
  decode.success(Fragment(hash, created_at, code))
}

pub fn get_releases(client) {
  let request = get_registrations_request(client)
  use response <- t.do(t.fetch(request))
  use data <- t.try(get_releases_response(response))
  t.done(data)
}

pub fn get_releases_request(client) {
  base(client)
  |> request.set_path("/rest/v1/releases")
  |> request.set_query([#("select", "*")])
}

pub fn get_releases_response(response) {
  decode(response, decode.list(release_decoder()))
}

fn release_decoder() {
  use package_id <- decode.field("package_id", decode.string)
  use version <- decode.field("version", decode.int)
  use created_at <- decode.field("created_at", decode.string)
  use hash <- decode.field("hash", decode.string)
  decode.success(Release(package_id, version, created_at, hash))
}

pub fn get_registrations(client) {
  let request = get_registrations_request(client)

  use response <- t.do(t.fetch(request))
  use data <- t.try(get_registrations_response(response))
  t.done(data)
}

pub fn get_registrations_request(client) {
  base(client)
  |> request.set_path("/rest/v1/registrations")
  |> request.set_query([#("select", "*")])
}

pub fn get_registrations_response(response) {
  decode(response, decode.list(registration_decoder()))
}

pub type Registration {
  Registration(id: Int, created_at: String, name: String, package_id: String)
}

fn registration_decoder() {
  use id <- decode.field("id", decode.int)
  use created_at <- decode.field("created_at", decode.string)
  use name <- decode.field("name", decode.string)
  use package_id <- decode.field("package_id", decode.string)
  decode.success(Registration(id, created_at, name, package_id))
}

pub fn fetch_index(client) {
  use registrations <- t.do(get_registrations(client))
  let registrations =
    dict.from_list(
      list.map(registrations, fn(registration) {
        #(registration.name, registration.package_id)
      }),
    )

  use releases <- t.do(get_releases(client))
  let releases =
    list.group(releases, fn(release) { release.package_id })
    |> dict.map_values(fn(_, releases) {
      list.map(releases, fn(release) { #(release.version, release) })
      |> dict.from_list
    })

  t.done(Index(registrations, releases))
}

pub type Release {
  Release(package_id: String, version: Int, created_at: String, hash: String)
}

pub type Index {
  Index(
    registry: Dict(String, String),
    packages: Dict(String, Dict(Int, Release)),
  )
}
