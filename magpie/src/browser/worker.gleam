import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/http.{Get}
import gleam/http/request
import gleam/json
import gleam/fetch
import gleam/javascript/promise.{try_await}
import magpie/query
import magpie/store/in_memory
import browser/serialize

// move to plinth
pub external type Worker

pub external fn start_worker(String) -> Worker =
  "../browser_ffi.mjs" "startWorker"

pub external fn post_message(Worker, json.Json) -> Nil =
  "../browser_ffi.mjs" "postMessage"

pub external fn on_message(Worker, fn(Dynamic) -> a) -> Nil =
  "../browser_ffi.mjs" "onMessage"

pub external fn log(a) -> Nil =
  "" "console.log"

pub fn run(self: Worker) {
  on_message(
    self,
    fn(data) {
      io.debug(data)
      case serialize.query().decode(data) {
        Ok(serialize.Query(from, patterns)) -> {
          io.debug(#(from, patterns))
          let result = query.run(from, patterns, in_memory.create_db([]))
          io.debug(result)
          post_message(self, serialize.relations().encode(result))
        }
        Error(_) -> todo("couldn't decode")
      }
    },
  )

// TODO plinth
// TODO can also use single code build with db in in worker
// Loaded is useful for the front end
// if I can solve worker in static file should be ok
// Just put React on window for worker? there is no window. need and optional if thing.
  let request =
    request.new()
    |> request.set_method(Get)
    |> request.set_scheme(http.Http)
    |> request.set_host("localhost:8080")
    |> request.set_path("/db.json")
    |> request.prepend_header("accept", "application/json")

  use response <- try_await(fetch.send(request))
  use response <- try_await(fetch.read_text_body(response))

  // We get a response record back
  //   assert Response(status: 200, ..) = response
  //   assert Ok("text/html; charset=utf-8") =
  //     http.get_resp_header(resp, "content-type")
  response.body
  |> io.debug
  Nil
  |> Ok
  |> promise.resolve()
}
