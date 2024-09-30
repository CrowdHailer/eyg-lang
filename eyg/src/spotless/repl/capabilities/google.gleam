import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/uri.{Uri}
import platforms/browser/windows
import plinth/browser/window

const auth_host = "accounts.google.com"

const auth_path = "/o/oauth2/auth"

const client_id = "419853920596-v2vh33r5h796q8fjvdu5f4ve16t91rkd.apps.googleusercontent.com"

const redirect_uri = "http://localhost:8080"

const scopes = [
  "https://www.googleapis.com/auth/calendar.events.readonly",
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/gmail.readonly",
]

fn auth_url(state, scopes) {
  let query = [
    #("client_id", client_id),
    #("response_type", "token"),
    #("redirect_uri", redirect_uri),
    #("state", state),
    #("scope", string.join(scopes, " ")),
  ]
  let query = Some(uri.query_to_string(query))
  Uri(Some("https"), None, Some(auth_host), None, auth_path, query, None)
  |> uri.to_string
}

pub fn do_auth() {
  let state =
    int.random(1_000_000_000)
    |> int.to_string
  let assert Ok(popup) = windows.open(auth_url(state, scopes), #(600, 700))
  monitor_auth(popup, 500)
}

fn monitor_auth(popup, wait) {
  use Nil <- promise.await(promise.wait(wait))
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
