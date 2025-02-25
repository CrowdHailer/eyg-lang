import eyg/ir/cid
import eyg/ir/dag_json
import gleam/dict
import gleam/dictx
import gleam/io
import gleam/javascript/promise
import gleeunit/should
import midas/node
import morph/editable as e
import website/components/snippet
import website/sync/cache
import website/sync/client
import website/sync/supabase
import website/sync/sync

// TODO test a fragment that doesn't work, i.e. it's effectful
import eyg/ir/tree as ir

fn foo_src() {
  ir.record([#("foo", ir.string("My value"))])
}

fn foo_cid() {
  cid.from_tree(foo_src())
}

fn index() {
  let foo_id = "foo_some_id"
  let foo_release = cache.Release(foo_id, 1, "time", foo_cid())
  cache.Index(
    registry: dictx.singleton("foo", foo_id),
    packages: dictx.singleton(foo_id, dictx.singleton(1, foo_release)),
  )
}

pub fn example_loads_index_and_fragment_test() {
  let source = ir.release("foo", 1, foo_cid())
  let client = client.init()
  let state = snippet.init(e.from_annotated(source), [], [], client.cache)
  snippet.type_errors(state)
  |> should.equal([#([], snippet.ReleaseNotFetched("foo", 1, 0))])

  let #(client, eff) = client.update(client, client.IndexFetched(Ok(index())))
  should.equal(eff, client.Nothing)
  let state = snippet.set_references(state, client.cache)

  snippet.type_errors(state)
  |> should.equal([
    #([], snippet.ReleaseFragmentNotFetched("foo", 1, foo_cid())),
  ])

  let message =
    client.FragmentFetched(foo_cid(), Ok(dag_json.to_block(foo_src())))
  let #(client, eff) = client.update(client, message)
  should.equal(eff, client.Nothing)

  let state = snippet.set_references(state, client.cache)
  snippet.type_errors(state)
  |> should.equal([])
}
// pub fn a_new_snippet_requests_release_test() {

//   use index <- promise.await(node.run(supabase.fetch_index(), ""))
//   let _ = should.be_ok(index)

//   use block <- promise.await(node.run(supabase.fetch_fragment(cid), ""))
//   let _ = should.be_ok(block)
//   let #(client, eff) = client.update(client, client.FragmentFetched(cid, block))
//   should.equal(eff, client.RequireFragments([]))

//   io.debug("===========!!!")
//   io.debug(snippet.type_errors(state))
//   // io.debug(state.evaluated)

//   todo
//   //   let state = init(e.Vacant)
//   //   // snippet.update(state, snippet.ClipboardReadCompleted(Ok("")))
//   //   // |> io.debug
//   //   todo as "paste ref"
// }

// pub fn a_new_snippet_request_internal_reference() -> Nil {
//   todo
// }
// TODO test special is no longer here
// TODO test that a returned value still has type errors
