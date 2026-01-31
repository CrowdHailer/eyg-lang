import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/fetch
import gleam/fetchx
import gleam/http/response.{type Response, Response}
import gleam/javascript/promise
import gleam/list
import lustre/effect
import multiformats/cid/v1
import spotless/origin
import untethered/ledger/schema
import untethered/protocol/registry/publisher
import website/sync/cache

pub type Client {
  Client(status: Status, origin: origin.Origin, cursor: Int, cache: cache.Cache)
}

/// Status is related to the current index synching in progress.
/// Fragment pulls are tracked separatly
pub type Status {
  Idle
  Syncing
  Disconnected
}

/// Actions are always returned as a list of actions,
/// this is easier than working with Option when we might want to compose output from multiple calls to the sync.client
pub type Action {
  SyncFrom(origin: origin.Origin, since: Int)
  FetchFragments(origin: origin.Origin, cids: List(String))
  Share(origin: origin.Origin, block: BitArray)
}

pub fn new(origin) {
  Client(status: Idle, origin:, cursor: 0, cache: cache.init())
}

pub fn syncing(client: Client) {
  client.status == Syncing
}

/// Starts or restarts sync if client Idle/Disconnected
pub fn sync(client) {
  let Client(status:, origin:, cursor:, ..) = client
  case status {
    Syncing -> #(client, [])
    _ -> #(Client(..client, status: Syncing), [SyncFrom(origin:, since: cursor)])
  }
}

// initialize and start pull
pub fn init(origin) -> #(Client, _) {
  new(origin)
  |> sync()
}

pub fn fetch_fragments(client, cids) {
  let Client(origin:, ..) = client
  let actions = case cids {
    [] -> []
    _ -> [FetchFragments(origin:, cids:)]
  }
  #(client, actions)
}

pub fn share(client, source) {
  let block = dag_json.to_block(source)
  let Client(origin:, ..) = client
  #(client, [Share(origin:, block:)])
}

pub type Message {
  ReleasesFetched(Result(List(#(Int, publisher.Event)), fetch.FetchError))
  FragmentFetched(
    cid: String,
    result: Result(Response(BitArray), fetch.FetchError),
  )
  FragmentShared(Result(Response(BitArray), fetch.FetchError))
}

pub type SyncError {
  FetchError(fetch.FetchError)
  ProtocolError(decode.DecodeError)
}

pub fn update(client: Client, message) -> #(Client, _) {
  case message {
    ReleasesFetched(result) -> {
      case result {
        Ok(entries) -> {
          let #(cache, cursor, new) =
            list.fold(entries, #(client.cache, client.cursor, []), fn(acc, e) {
              let #(cache, _, new) = acc
              let #(cursor, event) = e
              let cache = cache.apply(cache, event)
              let assert Ok(cid) = v1.to_string(event.module)
              let new = case cache.has_fragment(cache, cid) {
                True -> new
                False -> [cid, ..new]
              }
              #(cache, cursor, new)
            })

          let actions = case new {
            [] -> []
            _ -> [FetchFragments(client.origin, new)]
          }
          let client = Client(..client, cursor:, cache:)
          #(client, actions)
        }
        // TODO I can test network error by restarting and not accepting certificate warning
        Error(reason) -> {
          echo #("network error", reason)
          #(client, [])
        }
      }
    }
    FragmentFetched(cid:, result:) -> {
      case result {
        Ok(Response(status: 200, body:, ..)) -> {
          let cache = cache.add(client.cache, cid, body)
          let client = Client(..client, cache:)
          #(client, [])
        }
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

pub fn lustre_run_single(task: Action, wrapper: fn(Message) -> t) {
  effect.from(fn(dispatch) {
    do_run(task, fn(return) { dispatch(wrapper(return)) })
    // effect from needs to return Nil (not promise of Nil)
    Nil
  })
}

fn do_run(task, dispatch: fn(Message) -> Nil) {
  case task {
    SyncFrom(origin:, since:) -> {
      let parameters = schema.PullParameters(since:, limit: 1000, entities: [])
      let request = publisher.entries_request(origin, parameters)
      promise.map(fetchx.send_bits(request), fn(response) {
        let assert Ok(response) = response
        let assert Ok(response) = publisher.entries_response(response)
        [dispatch(ReleasesFetched(Ok(response)))]
      })
    }
    FetchFragments(origin:, cids:) -> {
      promise.await_list(
        list.map(cids, fn(cid) {
          let request = publisher.fetch_fragment_request(origin, cid)
          promise.map(fetchx.send_bits(request), fn(result) {
            dispatch(FragmentFetched(cid:, result:))
          })
        }),
      )
    }
    Share(origin:, block:) -> {
      let request = publisher.share_request(origin, block)

      promise.map(fetchx.send_bits(request), fn(response) {
        [dispatch(FragmentShared(response))]
      })
    }
  }
}
