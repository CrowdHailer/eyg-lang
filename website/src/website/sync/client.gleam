import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/fetch
import gleam/http
import gleam/http/request.{Request}
import gleam/http/response.{type Response, Response}
import gleam/int
import gleam/javascript/promise
import gleam/list
import lustre/effect
import spotless/origin
import website/sync/cache
import website/sync/protocol

// initialize and start pull
pub type Client {
  Client(origin: origin.Origin, cursor: Int, cache: cache.Cache)
}

/// Actions are always returned as a list of actions,
/// this is easier than working with Option when we might want to compose output from multiple calls to the sync.client
pub type Action {
  SyncFrom(origin: origin.Origin, since: Int)
  FetchFragments(origin: origin.Origin, cids: List(String))
  Share(origin: origin.Origin, block: BitArray)
}

pub fn init(origin) -> #(Client, _) {
  let cache = cache.init()
  let cursor = 0
  let client = Client(origin:, cursor:, cache:)
  #(client, [SyncFrom(origin:, since: cursor)])
}

pub fn fetch_fragments(client, cids) {
  let Client(origin:, ..) = client
  #(client, [FetchFragments(origin:, cids:)])
}

pub fn share(client, source) {
  let block = dag_json.to_block(source)
  let Client(origin:, ..) = client
  #(client, [Share(origin:, block:)])
}

pub type Message {
  ReleasesFetched(Result(Response(BitArray), fetch.FetchError))
  FragmentFetched(Result(Response(BitArray), fetch.FetchError))
  FragmentShared(Result(Response(BitArray), fetch.FetchError))
}

pub type SyncError {
  FetchError(fetch.FetchError)
  ProtocolError(decode.DecodeError)
}

pub fn update(client, message) -> #(Client, _) {
  case message {
    ReleasesFetched(result) -> {
      case result {
        Ok(response) ->
          case protocol.pull_events_response(response) {
            Ok(protocol.PullEventsResponse(events:, cursor:)) -> {
              // Check out of order pulls
              echo #("sync events", events)
              #(client, [])
            }
            Error(reason) -> {
              echo #("protocol error", reason)
              #(client, [])
            }
          }
        // TODO I can test network error by restarting and not accepting certificate warning
        Error(reason) -> {
          echo #("network error", reason)
          #(client, [])
        }
      }
    }
    FragmentFetched(result) -> {
      case result {
        Ok(Response(status: 200, ..)) -> todo
        Ok(Response(status: 404, ..)) -> {
          echo #("no fragment found")
          #(client, [])
        }
        Ok(Response(status: _, ..)) -> todo
        Error(reason) -> {
          echo #("network error", reason)
          #(client, [])
        }
      }
    }
    FragmentShared(result) -> {
      case result {
        Ok(Response(status: 200, ..)) -> todo

        Ok(Response(status:, ..)) -> {
          echo #("share failed", status)
          #(client, [])
        }
        Error(reason) -> {
          echo #("network error", reason)
          #(client, [])
        }
      }
    }
  }
}

pub fn lustre_run(tasks: List(Action), wrapper: fn(Message) -> t) {
  effect.from(fn(dispatch) {
    list.each(tasks, do_run(_, fn(return) { dispatch(wrapper(return)) }))
  })
}

fn do_run(task, dispatch: fn(Message) -> Nil) {
  case task {
    SyncFrom(origin:, since:) -> {
      let request =
        origin_to_request(origin)
        |> request.set_path("/registry/events")
        |> request.set_query([#("since", int.to_string(since))])
        |> request.set_body(<<>>)

      promise.map(fetch(request), fn(response) {
        [dispatch(ReleasesFetched(response))]
      })
    }
    FetchFragments(origin:, cids:) -> {
      promise.await_list(
        list.map(cids, fn(cid) {
          let request =
            origin_to_request(origin)
            |> request.set_path("/registry/f/" <> cid)
            |> request.set_body(<<>>)
          promise.map(fetch(request), fn(response) {
            dispatch(FragmentFetched(response))
          })
        }),
      )
    }
    Share(origin:, block:) -> {
      let request =
        origin_to_request(origin)
        |> request.set_method(http.Post)
        |> request.set_path("/registry/share")
        |> request.set_header("content-type", "application/json")
        |> request.set_body(block)

      promise.map(fetch(request), fn(response) {
        [dispatch(FragmentShared(response))]
      })
    }
  }
}

fn origin_to_request(origin) {
  let origin.Origin(scheme:, host:, port:) = origin

  Request(..request.new(), scheme:, host:, port:)
}

fn fetch(request) {
  use response <- promise.try_await(fetch.send_bits(request))
  fetch.read_bytes_body(response)
}
