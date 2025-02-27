import eyg/ir/cid
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import lustre/effect
import midas/browser
import website/sync/cache
import website/sync/supabase

pub type Failure {
  CommunicationFailure
  PayloadInvalid
  DigestIncorrect
}

pub type Remote {
  Remote(
    fetch_index: fn() -> Promise(Result(cache.Index, Failure)),
    fetch_fragment: fn(String) -> Promise(Result(BitArray, Failure)),
  )
}

pub type Client {
  Client(remote: Remote, cache: cache.Cache)
}

pub fn init(remote) {
  #(Client(remote, cache.init()), [RequireIndex(remote)])
}

pub fn default() {
  init(
    Remote(
      fn() {
        browser.run(supabase.fetch_index())
        |> promise.map(result.replace_error(_, CommunicationFailure))
      },
      fn(cid) {
        browser.run(supabase.fetch_fragment(cid))
        |> promise.map(result.replace_error(_, CommunicationFailure))
      },
    ),
  )
}

// The client trivially always starts a new request
pub fn fetch_fragments(client, cids) {
  let Client(remote:, ..) = client
  #(client, [RequireFragments(remote, cids)])
}

pub type Effect {
  RequireIndex(remote: Remote)
  RequireFragments(remote: Remote, cids: List(String))
}

pub fn run(effects) {
  list.flat_map(effects, fn(e) {
    case e {
      RequireIndex(remote) -> [
        {
          use index <- promise.map(remote.fetch_index())
          IndexFetched(index)
        },
      ]
      RequireFragments(remote, cids) ->
        list.map(cids, fn(asked) {
          use result <- promise.await(remote.fetch_fragment(asked))

          case result {
            Ok(bytes) -> {
              use got <- promise.map(cid.from_block(bytes))
              case asked == got {
                True -> FragmentFetched(asked, Ok(bytes))
                False -> FragmentFetched(asked, Error(DigestIncorrect))
              }
            }
            Error(reason) ->
              promise.resolve(FragmentFetched(asked, Error(reason)))
          }
        })
    }
  })
}

pub type Message {
  IndexFetched(Result(cache.Index, Failure))
  FragmentFetched(cid: String, result: Result(BitArray, Failure))
}

pub fn update(state, message) {
  let Client(remote:, cache:) = state
  case message {
    IndexFetched(Ok(index)) -> {
      let state = Client(..state, cache: cache.set_index(cache, index))
      #(state, [])
    }
    IndexFetched(Error(reason)) -> {
      // It's possible to try again later
      io.debug(reason)
      #(state, [])
    }
    FragmentFetched(cid, Ok(bytes)) ->
      case cache.install_fragment(cache, cid, bytes) {
        Ok(#(cache, required)) -> {
          let state = Client(..state, cache:)
          #(state, case required {
            [] -> []
            _ -> [RequireFragments(remote, required)]
          })
        }
        Error(_) -> {
          io.println("failed to install cid: " <> cid)
          #(state, [])
        }
      }
    FragmentFetched(_cid, Error(reason)) -> {
      // It's possible to try again later
      io.debug(reason)
      #(state, [])
    }
  }
}

// -------------------
// lustre code below

pub fn lustre_run(tasks, wrapper) {
  effect.from(fn(d) {
    list.map(run(tasks), fn(p) { promise.map(p, fn(r) { d(wrapper(r)) }) })
    Nil
  })
}
