import eyg/analysis/type_/binding/error
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dictx
import gleeunit/should
import morph/analysis
import website/components/example
import website/components/runner
import website/components/snippet
import website/sync/cache
import website/sync/client

pub fn foo_src() {
  ir.record([#("foo", ir.string("My value"))])
}

pub fn foo_cid() {
  "baguqeera5ot4b6mgodu27ckwty7eyr25lsqjke44drztct4w7cwvs77vkmca"
}

fn index() {
  let foo_id = "foo_some_id"
  let foo_release = cache.Release(foo_id, 1, "time", foo_cid())
  cache.Index(
    registry: dictx.singleton("foo", foo_id),
    packages: dictx.singleton(foo_id, dictx.singleton(1, foo_release)),
  )
}

pub fn analyse_for_cache_update_test() {
  let source = ir.release("foo", 1, foo_cid())
  let #(client, _) = client.default()
  let example = example.init(source, client.cache, [])
  example.snippet.analysis
  |> should.be_some
  |> analysis.type_errors()
  |> should.equal([#([], error.UndefinedRelease("foo", 1, foo_cid()))])

  let #(client, action) =
    client.update(client, client.IndexFetched(Ok(index())))
  should.equal(action, [])
  let #(example, action) = example.update_cache(example, client.cache)
  action
  |> should.equal(runner.Nothing)

  example.snippet.analysis
  |> should.be_some
  // currently the error doesn't change but maybe it should or maybe this is part of the view logic
  // |> analysis.type_errors()
  // |> should.equal([#([], error.UndefinedRelease("foo", 1, foo_cid()))])

  let message =
    client.FragmentFetched(foo_cid(), Ok(dag_json.to_block(foo_src())))
  let #(client, action) = client.update(client, message)
  should.equal(action, [])

  let #(example, action) = example.update_cache(example, client.cache)
  action
  |> should.equal(runner.Nothing)

  example.snippet.analysis
  |> should.be_some
  |> analysis.type_errors()
  |> should.equal([])
}

pub fn suggestions_for_packages_test() {
  let #(client, _) = client.default()
  let #(client, action) =
    client.update(client, client.IndexFetched(Ok(index())))
  should.equal(action, [])
  let source = ir.vacant()
  let example = example.init(source, client.cache, [])
  let #(example, action) =
    example.update(example, example.SnippetMessage(snippet.UserFocusedOnCode))
  action
  |> should.equal(example.Nothing)
  let #(example, action) =
    example.update(
      example,
      example.SnippetMessage(snippet.UserPressedCommandKey("@")),
    )
  action
  |> should.equal(example.FocusOnInput)
  let assert snippet.Editing(snippet.SelectRelease(autocomplete, _)) =
    example.snippet.status

  autocomplete.items
  |> should.equal([#("foo", 1, foo_cid())])
}
