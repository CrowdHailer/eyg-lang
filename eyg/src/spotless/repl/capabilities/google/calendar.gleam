import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/dynamic
import gleam/fetch
import gleam/http/request
import gleam/javascript/promise
import gleam/list
import gleam/result.{try}
import gleam/string
import spotless/repl/capabilities/google

const api_host = "www.googleapis.com"

fn events_path(account) {
  string.concat(["/calendar/v3/calendars/", account, "/events"])
}

// calendar_id can be an account identified by email address
fn events_request(token, calendar_id, from) {
  let query = [
    #("timeMin", from),
    #("orderBy", "startTime"),
    #("singleEvents", "true"),
  ]
  request.new()
  |> request.set_host(api_host)
  |> request.set_path(events_path(calendar_id))
  |> request.set_query(query)
  |> request.prepend_header("Authorization", string.append("Bearer ", token))
}

fn do_list_events(token, calendar_id, from) {
  let request = events_request(token, calendar_id, from)
  use response <- promise.try_await(fetch.send(request))
  use response <- promise.try_await(fetch.read_json_body(response))
  promise.resolve(
    event_decoder()(response.body)
    |> result.map_error(fn(_) { todo as "what should list_events error be" }),
  )
}

pub fn list_events(from) {
  use from <- try(cast.as_string(from))
  Ok(
    v.Promise({
      use token <- promise.await(google.do_auth())
      let assert Ok(token) = token
      let account_id = "peterhsaxton@gmail.com"
      use response <- promise.map(do_list_events(token, account_id, from))
      case response {
        Ok(events) ->
          v.ok(
            v.LinkedList(
              list.map(events, fn(event) {
                let Event(summary, start) = event
                v.Record([
                  #("summary", v.Str(summary)),
                  #("start", v.Str(start)),
                ])
              }),
            ),
          )
        Error(reason) -> v.error(v.Str(string.inspect(reason)))
      }
    }),
  )
}

fn event_decoder() {
  dynamic.field(
    "items",
    dynamic.list(dynamic.decode2(
      Event,
      dynamic.field("summary", dynamic.string),
      dynamic.field("start", fn(x) { Ok(string.inspect(x)) }),
    )),
  )
}

pub type Event {
  Event(summary: String, start: String)
}
