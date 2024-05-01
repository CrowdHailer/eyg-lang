import gleam/javascript
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/string
import platforms/browser/windows
import plinth/browser/service_worker
import plinth/browser/window
import plinth/javascript/console

pub fn run() {
  promise.map(service_worker.register("/local_dev.js"), fn(registration) {
    case registration {
      Ok(_registration) -> {
        window.add_event_listener("click", fn(_event) {
          let assert Ok(_) = windows.open("/capture", #(800, 800))
          Nil
        })
        // later open sandbox it should be caught
      }
      Error(_) -> {
        let captured = javascript.make_reference([])
        let assert Ok(sw) = service_worker.self()
        service_worker.skip_waiting(sw)

        service_worker.add_fetch_listener(sw, fn(event) {
          let id = service_worker.client_id(event)

          // also check that the path is /captured
          console.log(event)
          let do_capture =
            event
            |> service_worker.request()
            |> service_worker.request_url()
            |> string.contains("capture")

          case id, do_capture {
            "", True -> {
              let new_id = service_worker.resulting_client_id(event)
              console.log(#("new id", new_id))
              javascript.update_reference(captured, fn(ids) { [new_id, ..ids] })
              // let assert Ok(_) =
              console.log("responding")
              service_worker.respond_with(
                event,
                service_worker.redirect_response("/"),
              )
              |> console.log()
              console.log("responded")
              Nil
            }
            _, _ -> {
              let nid = service_worker.resulting_client_id(event)
              let matchers = javascript.dereference(captured)
              console.log(#("client_id", id, nid, array.from_list(matchers)))
              // First load only on resulting
              case list.contains(matchers, id) || list.contains(matchers, nid) {
                True -> {
                  // console.log(service_worker.request(event))
                  // let assert Ok(_) =
                  service_worker.respond_with(
                    event,
                    service_worker.ok_response("hello22"),
                  )
                  |> console.log
                  Nil
                }
                False -> {
                  console.log("not captured")
                  Nil
                }
              }
            }
          }
        })
        console.log("listener added")
      }
    }
  })
}
