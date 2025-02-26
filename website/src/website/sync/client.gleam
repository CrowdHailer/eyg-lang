import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/list
import lustre/effect
import midas/browser
import snag
import website/components/snippet
import website/sync/cache
import website/sync/supabase

pub type Client {
  Client(cache: cache.Cache)
}

pub type Effect {
  Nothing
  RequireFragments(cids: List(String))
}

pub fn init() {
  Client(cache.init())
}

pub fn fetch_index(then) {
  use index <- promise.map(browser.run(supabase.fetch_index()))
  then(IndexFetched(index))
}

pub fn fetch_fragment(cid, then) {
  use result <- promise.map(browser.run(supabase.fetch_fragment(cid)))
  then(FragmentFetched(cid, result))
}

pub type Message {
  IndexFetched(Result(cache.Index, snag.Snag))
  FragmentFetched(cid: String, result: Result(BitArray, snag.Snag))
}

pub fn update(state, message) {
  let Client(cache) = state
  case message {
    IndexFetched(Ok(index)) -> {
      let state = Client(cache.set_index(cache, index))
      #(state, Nothing)
    }
    IndexFetched(Error(_)) ->
      todo as "show error. To the side or in state, probably to the side"
    FragmentFetched(cid, Ok(bytes)) ->
      case cache.install_fragment(cache, cid, bytes) {
        Ok(#(cache, required)) -> {
          let state = Client(cache)
          #(state, case required {
            [] -> Nothing
            _ -> RequireFragments(required)
          })
        }
        Error(_) -> todo as "why did this fail"
      }
    FragmentFetched(cid, Error(reason)) -> {
      io.debug(reason)
      todo
    }
  }
}

// -------------------
// lustre code below

pub fn fetch_index_effect(wrapper) {
  effect.from(fn(d) {
    fetch_index(fn(m) { d(wrapper(m)) })
    Nil
  })
}

pub fn fetch_missing(snippets, wrapper) {
  let cids =
    dict.fold(snippets, [], fn(acc, _key, snippet) {
      snippet.references(snippet)
      |> list.append(acc)
      |> list.unique
    })
  fetch_fragments_effect(cids, wrapper)
}

pub fn fetch_list_missing(snippets, wrapper) {
  let cids =
    list.fold(snippets, [], fn(acc, snippet) {
      snippet.references(snippet)
      |> list.append(acc)
      |> list.unique
    })
  fetch_fragments_effect(cids, wrapper)
}

pub fn fetch_fragments_effect(cids, wrapper) {
  effect.from(fn(d) {
    list.map(cids, fn(cid) { fetch_fragment(cid, fn(m) { d(wrapper(m)) }) })
    Nil
  })
}

pub fn do(effect, wrapper) {
  case effect {
    RequireFragments([_, ..] as cids) -> fetch_fragments_effect(cids, wrapper)
    _ -> effect.none()
  }
}
