import dag_json as dag_json_lib
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/dynamic/decode
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/result
import gleam/string
import midas/task as t
import snag
import supa/client
import website/sync/cache

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
      case dag_json_lib.decode(response.body) {
        Ok(dyn) ->
          decode.run(dyn, decoder)
          |> result.map_error(fn(reason) { snag.new(string.inspect(reason)) })
        Error(reason) -> snag.error(string.inspect(reason))
      }
    _ -> panic
  }
}

pub fn get_fragments() {
  let request =
    base()
    |> request.set_path("/rest/v1/fragments")
    |> request.set_query([#("select", "*")])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, decode.list(fragment_decoder())))
  t.done(data)
}

pub fn fetch_fragment(cid) {
  let request =
    base()
    |> request.set_path("/rest/v1/fragments")
    |> request.set_query([#("select", "*"), #("hash", "eq." <> cid)])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, decode.list(fragment_decoder())))
  case data {
    [Fragment(hash: h, code:, ..) as f] if h == cid ->
      // Ideally I'd download bytes but we trust supabase
      t.done(dag_json.to_block(code))
    _ -> t.abort(snag.new("no hash with cid"))
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

pub fn get_releases() {
  let request =
    base()
    |> request.set_path("/rest/v1/releases")
    |> request.set_query([#("select", "*")])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, decode.list(release_decoder())))
  t.done(data)
}

fn release_decoder() {
  use package_id <- decode.field("package_id", decode.string)
  use version <- decode.field("version", decode.int)
  use created_at <- decode.field("created_at", decode.string)
  use hash <- decode.field("hash", decode.string)
  decode.success(cache.Release(package_id, version, created_at, hash))
}

pub fn get_registrations() {
  let request =
    base()
    |> request.set_path("/rest/v1/registrations")
    |> request.set_query([#("select", "*")])
  use response <- t.do(t.fetch(request))
  use data <- t.try(decode(response, decode.list(registration_decoder())))
  t.done(data)
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

pub fn fetch_index() {
  use registrations <- t.do(get_registrations())
  let registrations =
    dict.from_list(
      list.map(registrations, fn(registration) {
        #(registration.name, registration.package_id)
      }),
    )

  use releases <- t.do(get_releases())
  let releases =
    list.group(releases, fn(release) { release.package_id })
    |> dict.map_values(fn(_, releases) {
      list.map(releases, fn(release) { #(release.version, release) })
      |> dict.from_list
    })

  t.done(cache.Index(registrations, releases))
}
