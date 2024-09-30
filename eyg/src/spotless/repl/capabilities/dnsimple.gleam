import eyg/runtime/value as v
import gleam/dynamic
import gleam/fetch
import gleam/http
import gleam/http/request
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri.{Uri}
import platforms/browser/windows
import plinth/browser/window

const auth_host = "dnsimple.com"

const auth_path = "/oauth/authorize"

pub const client_id = "fe1232c4c0169284"

const redirect_uri = "http://localhost:8080/"

fn auth_url(state) {
  let query = [
    #("client_id", client_id),
    #("response_type", "code"),
    #("redirect_uri", redirect_uri),
    #("state", state),
  ]
  let query = Some(uri.query_to_string(query))
  Uri(Some("https"), None, Some(auth_host), None, auth_path, query, None)
  |> uri.to_string
}

pub const api_host = "localhost:8081"

const token_path = "/v2/oauth/access_token"

pub fn token_request(code, state) {
  let query = [
    #("grant_type", "authorization_code"),
    #("client_id", client_id),
    // #("client_secret", client_secret),
    #("code", code),
    #("redirect_uri", redirect_uri),
    #("state", state),
  ]

  request.new()
  |> request.set_scheme(http.Http)
  |> request.set_method(http.Post)
  |> request.set_host(api_host)
  |> request.set_path(token_path)
  |> request.prepend_header("content-type", "application/x-www-form-urlencoded")
  |> request.set_body(uri.query_to_string(query))
}

fn do_get_token(_) {
  let state =
    int.random(1_000_000_000)
    |> int.to_string
  let assert Ok(popup) = windows.open(auth_url(state), #(600, 700))
  let p =
    promise.await(monitor_auth(popup, 500), fn(r) {
      case r {
        Ok(code) -> {
          io.debug("sendingrequest")
          io.debug(token_request(code, state))
          use response <- promise.await(fetch.send(token_request(code, state)))
          case response {
            Ok(response) -> {
              use response <- promise.await(fetch.read_json_body(response))
              case response {
                Ok(response) -> {
                  let data = token_decoder()(response.body)
                  case data {
                    Ok(#(token, account)) -> {
                      //   let value =
                      //     v.LinkedList(
                      //       list.map(sites, fn(site: Site) {
                      //         v.Record([
                      //           #("id", v.Str(site.id)),
                      //           #("state", v.Str(site.state)),
                      //           #("name", v.Str(site.name)),
                      //           #("url", v.Str(site.url)),
                      //         ])
                      //       }),
                      //     )

                      promise.resolve(Ok(#(token, account)))
                      // todo as "needs proper eyg value"
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
        Error(_) -> panic as "something bad"
      }
    })
  p
}

fn token_decoder() {
  dynamic.decode2(
    fn(a, b) { #(a, b) },
    dynamic.field("access_token", dynamic.string),
    dynamic.field("account_id", dynamic.int),
  )
}

fn monitor_auth(popup, wait) {
  use Nil <- promise.await(promise.wait(wait))
  // TODO can error on cross origin object
  case
    window.location_of(popup)
    |> io.debug
  {
    Ok(location) ->
      case uri.parse(location) {
        // NOTE query when requesting code -> Netlify lambda but how to run locally
        Ok(Uri(query: Some(fragment), ..)) -> {
          let assert Ok(parts) = uri.parse_query(fragment)
          let assert Ok(access_token) = list.key_find(parts, "code")
          window.close(popup)
          promise.resolve(Ok(access_token))
        }
        _ -> monitor_auth(popup, wait)
      }
    Error(_) -> monitor_auth(popup, wait)
  }
}

fn base_request(token) {
  request.new()
  |> request.set_scheme(http.Http)
  |> request.set_host(api_host)
  |> request.prepend_header("Authorization", string.append("Bearer ", token))
}

fn to_error(any) {
  v.Str(string.inspect(any))
}

pub fn list_domains(_) {
  Ok(
    v.Promise({
      use tokens <- promise.await(do_get_token(Nil))
      let assert Ok(#(token, account)) = tokens
      use response <- promise.map(do_list_domains(token, account))
      case response {
        Ok(domains) ->
          v.ok(
            v.LinkedList(
              list.map(domains, fn(domain) {
                let Domain(id, name) = domain
                v.Record([#("id", v.Integer(id)), #("name", v.Str(name))])
              }),
            ),
          )
        Error(reason) -> v.error(reason)
      }
    }),
  )
}

fn do_list_domains(token, account) {
  let account = int.to_string(account)
  let request =
    base_request(token)
    |> request.set_path(string.concat(["/v2/", account, "/domains"]))

  use response <- promise.try_await(
    fetch.send(request)
    |> promise.map(result.map_error(_, to_error)),
  )
  use response <- promise.map(
    fetch.read_json_body(response)
    |> promise.map(result.map_error(_, to_error)),
  )
  use response <- result.try(
    response
    |> result.map_error(to_error),
  )

  use data <- result.map(
    domain_decoders()(response.body)
    |> result.map_error(to_error),
  )
  data
}

pub type Domain {
  Domain(id: Int, name: String)
}

fn domain_decoders() {
  dynamic.field(
    "data",
    dynamic.list(dynamic.decode2(
      Domain,
      dynamic.field("id", dynamic.int),
      dynamic.field("name", dynamic.string),
    )),
  )
}
