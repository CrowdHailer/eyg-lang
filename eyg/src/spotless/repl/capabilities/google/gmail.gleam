import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/dynamic
import gleam/fetch
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result.{try}
import gleam/string
import plinth/javascript/console
import spotless/repl/capabilities/google

const api_host = "gmail.googleapis.com"

fn messages_path(account) {
  string.concat(["/gmail/v1/users/", account, "/messages"])
}

// calendar_id can be an account identified by email address
fn messages_request(token, account_id) {
  request.new()
  |> request.set_host(api_host)
  |> request.set_path(messages_path(account_id))
  |> request.prepend_header("Authorization", string.append("Bearer ", token))
}

fn do_list_messages(token, account_id) {
  let request = messages_request(token, account_id)
  use response <- promise.try_await(fetch.send(request))
  use response <- promise.try_await(fetch.read_json_body(response))
  console.log(response.body)
  promise.resolve(
    message_decoder()(response.body)
    |> result.map_error(fn(_) { todo as "what should list_messages error be" }),
  )
}

pub fn list_messages(_) {
  Ok(
    v.Promise({
      use token <- promise.await(google.do_auth())
      let assert Ok(token) = token
      let account_id = "peterhsaxton@gmail.com"
      use response <- promise.map(do_list_messages(token, account_id))
      case response {
        Ok(messages) ->
          v.ok(
            v.LinkedList(
              list.map(messages, fn(message) {
                let Message(id, thread_id) = message
                v.Record([#("id", v.Str(id)), #("thread_id", v.Str(thread_id))])
              }),
            ),
          )
        Error(reason) -> v.error(v.Str(string.inspect(reason)))
      }
    }),
  )
}

fn message_decoder() {
  dynamic.field(
    "messages",
    dynamic.list(dynamic.decode2(
      Message,
      dynamic.field("id", dynamic.string),
      dynamic.field("threadId", dynamic.string),
    )),
  )
}

pub type Message {
  Message(id: String, thread_id: String)
}
