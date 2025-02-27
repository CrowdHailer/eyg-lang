import eyg/ir/cid
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import lustre/effect
import midas/browser
import snag
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
  #(Client(remote, cache.init()), Nothing)
}

pub fn default() {
  init(
    Remote(fn() { todo }, fn(cid) {
      browser.run(supabase.fetch_fragment(cid))
      |> promise.map(result.replace_error(_, CommunicationFailure))
    }),
  ).0
}

// The client trivially always starts a new request
pub fn fetch_fragments(client, cids) {
  let Client(remote:, ..) = client
  #(client, RequireFragments(remote, cids))
}

pub type Effect {
  Nothing
  RequireFragments(remote: Remote, cids: List(String))
}

pub fn run(effect) {
  case effect {
    Nothing -> []
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
          _ -> todo as "handle this error"
        }
      })
  }
}

fn do_fetch_index(then) {
  use index <- promise.map(browser.run(supabase.fetch_index()))
  then(IndexFetched(index))
}

pub type Message {
  IndexFetched(Result(cache.Index, snag.Snag))
  FragmentFetched(cid: String, result: Result(BitArray, Failure))
}

pub fn update(state, message) {
  let Client(remote:, cache:) = state
  case message {
    IndexFetched(Ok(index)) -> {
      let state = Client(..state, cache: cache.set_index(cache, index))
      #(state, Nothing)
    }
    IndexFetched(Error(_)) ->
      todo as "show error. To the side or in state, probably to the side"
    FragmentFetched(cid, Ok(bytes)) ->
      case cache.install_fragment(cache, cid, bytes) {
        Ok(#(cache, required)) -> {
          let state = Client(..state, cache:)
          #(state, case required {
            [] -> Nothing
            _ -> RequireFragments(remote, required)
          })
        }
        Error(_) -> todo as "why did this fail"
      }
    FragmentFetched(_cid, Error(reason)) -> {
      // It's possible to try again later
      io.debug(reason)
      #(state, Nothing)
    }
  }
}

// -------------------
// lustre code below

pub fn fetch_index_effect(wrapper) {
  effect.from(fn(d) {
    do_fetch_index(fn(m) { d(wrapper(m)) })
    Nil
  })
}

pub fn lustre_run(task, wrapper) {
  effect.from(fn(d) {
    list.map(run(task), fn(p) { promise.map(p, fn(r) { d(wrapper(r)) }) })
    Nil
  })
}
