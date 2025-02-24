import gleam/io
import gleam/javascript/promise
import gleeunit/should
import midas/node
import morph/editable as e
import website/components/snippet
import website/sync/client
import website/sync/supabase
import website/sync/sync

// TODO test a fragment that doesn't work, i.e. it's effectful

// pub fn a_new_snippet_requests_release_test() {
//   // {"0":"@","l":{"/":"baguqeeralt3s7yi53wf6hhlbtppwo4ebzgshdd7nr2onw7jlr3e2zkl4bxda"},"p":"std","r":1}
//   let client = client.init()
//   let cid = "baguqeeralt3s7yi53wf6hhlbtppwo4ebzgshdd7nr2onw7jlr3e2zkl4bxda"
//   let source = e.Release("std", 1, cid)
//   let state = snippet.init(source, [], [], client.cache)

//   use index <- promise.await(node.run(supabase.fetch_index(), ""))
//   let _ = should.be_ok(index)
//   let #(client, eff) = client.update(client, client.IndexFetched(index))
//   io.debug("=-====")
//   io.debug(client.cache.index.registry)
//   should.equal(eff, client.Nothing)

//   use block <- promise.await(node.run(supabase.fetch_fragment(cid), ""))
//   let _ = should.be_ok(block)
//   let #(client, eff) = client.update(client, client.FragmentFetched(cid, block))
//   should.equal(eff, client.RequireFragments([]))

//   let state = snippet.set_references(state, client.cache)
//   io.debug("===========!!!")
//   io.debug(snippet.type_errors(state))
//   // io.debug(state.evaluated)

//   todo
//   //   let state = init(e.Vacant)
//   //   // snippet.update(state, snippet.ClipboardReadCompleted(Ok("")))
//   //   // |> io.debug
//   //   todo as "paste ref"
// }

pub fn a_new_snippet_request_internal_reference() -> Nil {
  todo
}
