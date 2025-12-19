import gleam/dynamic/decode
import gleam/fetch
import gleam/http/request.{Request}
import gleam/http/response.{type Response}
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

pub type Message {
  ReleasesFetched(Result(Response(BitArray), fetch.FetchError))
  FragmentFetched(Result(Response(BitArray), fetch.FetchError))
}

pub type SyncError {
  FetchError(fetch.FetchError)
  ProtocolError(decode.DecodeError)
}

pub fn update(client, message) -> #(Client, _) {
  case message {
    ReleasesFetched(result) -> {
      echo "releaes"
      todo
    }
    FragmentFetched(result) -> {
      echo "fragment"
      todo
    }
  }
  // case response {
  //   Ok(response) ->
  //     // case protocol.pull_events_response(response) {
  //     //   Ok(out) -> {
  //     //     echo out
  //     //     todo
  //     //   }
  //     //   Error(reason) -> Error(ProtocolError(reason))
  //     // }
  //   Error(reason) -> Error(FetchError(reason))
  // }
  // }
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
          promise.map(fetch(request), fn(response) {
            dispatch(FragmentFetched(response))
          })
        }),
      )
    }
  }
}

fn origin_to_request(origin) {
  let origin.Origin(scheme:, host:, port:) = origin

  Request(..request.new(), scheme:, host:, port:)
}

fn fetch(request) {
  use response <- promise.try_await(fetch.send(request))
  fetch.read_bytes_body(response)
}
