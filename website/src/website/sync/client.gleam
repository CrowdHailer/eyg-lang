import gleam/http/request
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/result
import lustre/effect
import midas/browser
import midas/task as t
import website/sync/cache

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

// client init used only in tests
pub fn init(remote) {
  #(Client(remote, cache.init()), [RequireIndex(remote)])
}

pub fn registry() -> #(Client, List(Effect)) {
  init(
    Remote(
      fn() {
        {
          let request =
            request.new()
            |> request.set_host("localhost")
            |> request.set_path("/packages")
            |> request.set_body(<<>>)
          use response <- t.do(t.fetch(request))

          let assert Ok(index) =
            json.parse_bits(response.body, cache.index_decoder())

          t.done(index)
        }
        |> browser.run_task()
        |> promise.map(result.replace_error(_, CommunicationFailure))
      },
      fn(cid) {
        {
          let request =
            request.new()
            |> request.set_host("localhost")
            |> request.set_path("/fragments/" <> cid)
            |> request.set_body(<<>>)
          use response <- t.do(t.fetch(request))
          // echo json.parse_bits(response.body, dag_json.decoder(Nil))
          // promise.map(cid.from_block_async(response.body), fn(x) { echo x })

          t.done(response.body)
        }
        |> browser.run_task()
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
              io.println("skipping cid check, trust server.")
              // use got <- promise.map(cid.from_block_async(bytes))
              // let assert Ok(got) = got
              // case asked == got {
              //   True -> FragmentFetched(asked, Ok(bytes))
              //   False -> FragmentFetched(asked, Error(DigestIncorrect))
              // }
              promise.resolve(FragmentFetched(asked, Ok(bytes)))
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
      echo reason
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
      echo reason
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
