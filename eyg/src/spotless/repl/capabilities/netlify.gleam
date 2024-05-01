import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/dynamic
import gleam/fetch
import gleam/http
import gleam/http/request
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri.{Uri}
import platforms/browser/windows
import plinth/browser/window
import spotless/repl/capabilities/zip

const auth_host = "app.netlify.com"

const auth_path = "/authorize"

const client_id = "cQmYKaFm-2VasrJeeyobXXz5G58Fxy2zQ6DRMPANWow"

const redirect_uri = "http://localhost:8080"

fn auth_url(state) {
  let query = [
    #("client_id", client_id),
    #("response_type", "token"),
    #("redirect_uri", redirect_uri),
    #("state", state),
  ]
  let query = Some(uri.query_to_string(query))
  Uri(Some("https"), None, Some(auth_host), None, auth_path, query, None)
  |> uri.to_string
}

fn do_get_token() {
  let state =
    int.random(1_000_000_000)
    |> int.to_string
  let assert Ok(popup) = windows.open(auth_url(state), #(600, 700))
  monitor_auth(popup, 500)
}

fn monitor_auth(popup, wait) {
  use Nil <- promise.await(promisex.wait(wait))
  // TODO can error on cross origin object
  case window.location_of(popup) {
    Ok(location) ->
      case uri.parse(location) {
        Ok(Uri(fragment: Some(fragment), ..)) -> {
          let assert Ok(parts) = uri.parse_query(fragment)
          let assert Ok(access_token) = list.key_find(parts, "access_token")
          window.close(popup)
          promise.resolve(Ok(access_token))
        }
        _ -> monitor_auth(popup, wait)
      }
    Error(_) -> monitor_auth(popup, wait)
  }
}

const api_host = "api.netlify.com"

fn base_request(token) {
  request.new()
  |> request.set_host(api_host)
  |> request.prepend_header("Authorization", string.append("Bearer ", token))
}

fn post(token, path, mime, content) {
  base_request(token)
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> request.prepend_header("content-type", mime)
  |> request.set_body(content)
}

const sites_path = "/api/v1/sites"

fn sites_request(token) {
  base_request(token)
  |> request.set_path(sites_path)
}

// TODO extract get_token and monitor window
pub fn get_sites(_) {
  let p =
    promise.await(do_get_token(), fn(r) {
      case r {
        Ok(token) -> {
          use response <- promise.await(fetch.send(sites_request(token)))
          case response {
            Ok(response) -> {
              use response <- promise.await(fetch.read_json_body(response))
              case response {
                Ok(response) -> {
                  let sites = site_decoder()(response.body)
                  case sites {
                    Ok(sites) -> {
                      io.debug(sites)
                      let value =
                        v.LinkedList(
                          list.map(sites, fn(site: Site) {
                            v.Record([
                              #("id", v.Str(site.id)),
                              #("state", v.Str(site.state)),
                              #("name", v.Str(site.name)),
                              #("url", v.Str(site.url)),
                            ])
                          }),
                        )

                      promise.resolve(value)
                    }
                    Error(reason) -> {
                      io.debug(reason)
                      panic as "bad decoding"
                    }
                  }
                }
                // TODO try snag
                Error(_) -> panic as "bad json"
              }
            }
            Error(_) -> panic as "bad equest"
          }
        }
        Error(_) -> promise.resolve(v.error(v.unit))
      }
    })
  Ok(v.Promise(p))
}

fn site_decoder() {
  dynamic.list(dynamic.decode4(
    Site,
    dynamic.field("id", dynamic.string),
    dynamic.field("state", dynamic.string),
    dynamic.field("name", dynamic.string),
    dynamic.field("url", dynamic.string),
  ))
}

pub type Site {
  Site(id: String, state: String, name: String, url: String)
}

pub fn deploy_site(value) {
  // Has to be try because error can't be string and cast returns the right type
  use site_id <- result.try(cast.field("site", cast.as_string, value))
  use files <- result.try(cast.field("files", cast.as_list, value))
  use files <- result.try(
    list.try_map(files, fn(f) {
      case cast.field("name", cast.as_string, f) {
        Ok(name) ->
          case cast.field("content", cast.as_binary, f) {
            Ok(content) -> Ok(#(name, content))
            Error(reason) -> Error(reason)
          }
        Error(reason) -> Error(reason)
      }
    }),
  )

  Ok(
    v.Promise({
      use token <- promise.await(do_get_token())
      case token {
        Ok(token) -> {
          use r <- promise.map(do_deploy_site(token, site_id, files))
          v.unit
        }
        Error(Nil) -> todo
      }
    }),
  )
}

fn do_deploy_site(token, site_id, files) {
  use body <- promise.await(zip.zip(files))
  let path = string.concat(["/api/v1/sites/", site_id, "/deploys"])
  let r = post(token, path, "application/zip", body)
  // let r = fetch.bitarray_to_fetch_request(r)

  use response <- strive(fetch.send_bits(r))
  use response <- strive(fetch.read_text_body(response))

  io.debug(response)
  promise.resolve(Ok(Nil))
}

// attempt try await task.await can always fail
fn strive(task, then) {
  promise.await(task, fn(r) { try_but_not_as_returns_a_promise(r, then) })
}

fn try_but_not_as_returns_a_promise(result, then) {
  case result {
    Ok(v) -> then(v)
    Error(reason) -> promise.resolve(Error(string.inspect(reason)))
  }
}
