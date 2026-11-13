import eyg/hub/cache
import eyg/hub/schema
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{None}
import oas/generator/utils
import overlay/llm/tool
import overlay/web/artifact as a
import overlay/web/context
import overlay/web/tools
import overlay/web/trace

fn bundle(text) {
  [a.File("index.html", "text/html", bit_array.from_string(text))]
}

fn panel(item) {
  a.Placement(item, a.Point(0, 0), a.Point(1000, 1000))
}

pub fn history_retains_complete_snapshots_and_independent_names_test() {
  let assert Ok(#(store, 1)) = a.save(a.new(), "map", bundle("first"))
  let assert Ok(#(store, 2)) = a.save(store, "map", bundle("second"))
  let assert Ok(#(store, 3)) = a.save(store, "map", bundle("second"))
  let assert Ok(#(store, 1)) = a.save(store, "bus", bundle("other"))
  assert Ok(bundle("first")) == a.revision(store, "map", 1)
  assert Ok(bundle("second")) == a.latest(store, "map")
  assert 3 == list.length(a.history(store, "map"))
  let assert Error(_) = a.revision(store, "map", 0)
  let assert Error(_) = a.revision(store, "map", 4)
}

pub fn invalid_bundles_do_not_create_revisions_test() {
  let invalid = [
    [],
    [a.File("index.html", "text/plain", <<>>)],
    [a.File("index.html", "text/html", <<255>>)],
    list.append(bundle("a"), bundle("b")),
    list.append(bundle("a"), [a.File("../secret", "text/plain", <<>>)]),
    list.append(bundle("a"), [a.File("/secret", "text/plain", <<>>)]),
    list.append(bundle("a"), [a.File("a/./b", "text/plain", <<>>)]),
    list.append(bundle("a"), [a.File("a%2fb", "text/plain", <<>>)]),
    list.append(bundle("a"), [a.File("a.txt", "text", <<>>)]),
    list.append(bundle("a"), [a.File("a.txt", "text/plain;charset=utf-8", <<>>)]),
    list.append(bundle("a"), [a.File("a.txt", "text/plain,<script>", <<>>)]),
  ]
  list.each(invalid, fn(bundle) {
    let assert Error(_) = a.save(a.new(), "bad", bundle)
  })
  let assert Error(_) = a.save(a.new(), " ", bundle("a"))
}

pub fn a_share_follows_the_latest_earlier_shared_version_test() {
  let store =
    a.new()
    |> a.share("map", 1, a.Shared("one", "s1"))
    |> a.share("map", 2, a.ShareFailed("too big"))
    |> a.share("map", 3, a.Shared("three", "s3"))
    |> a.share("map", 4, a.Sharing)
    |> a.share("bus", 2, a.Shared("bus", "s"))
  assert Error(Nil) == a.previous_share(store, "map", 1)
  assert Ok(schema.SharedArtifact("one", "s1"))
    == a.previous_share(store, "map", 3)
  assert Ok(schema.SharedArtifact("three", "s3"))
    == a.previous_share(store, "map", 5)
  assert Error(Nil) == a.previous_share(store, "bus", 2)
}

pub fn show_validates_references_and_rectangles_and_upserts_test() {
  let assert Ok(#(store, _)) = a.save(a.new(), "map", bundle("a"))
  let assert Ok(store) = a.show(store, panel(a.Artifact("map")))
  let moved =
    a.Placement(a.Artifact("map"), a.Point(500, 0), a.Point(500, 1000))
  let assert Ok(store) = a.show(store, moved)
  assert [moved] == store.panels
  let assert Ok(store) = a.show(store, panel(a.History("map")))
  let assert Ok(store) = a.show(store, panel(a.Revision("map", 1)))
  let assert Ok(store) = a.show(store, panel(a.Diff("map", 1, 1)))
  assert 4 == list.length(store.panels)
  let assert Error(_) = a.show(store, panel(a.Artifact("missing")))
  let assert Error(_) = a.show(store, panel(a.Revision("map", 2)))
  let assert Error(_) = a.show(store, panel(a.Diff("map", 1, 2)))
  list.each(
    [
      #(a.Point(-1, 0), a.Point(1, 1)),
      #(a.Point(0, 0), a.Point(0, 1)),
      #(a.Point(500, 0), a.Point(501, 1)),
      #(a.Point(0, 999), a.Point(1, 2)),
    ],
    fn(rect) {
      let assert Error(_) =
        a.show(store, a.Placement(a.Artifact("map"), rect.0, rect.1))
    },
  )
  let store = a.close(store, a.Artifact("map"))
  assert 3 == list.length(store.panels)
  assert Ok(bundle("a")) == a.latest(store, "map")
}

pub fn diff_reports_add_remove_content_and_media_type_changes_test() {
  let old = a.File("a.txt", "text/plain", <<1>>)
  let changed = a.File("a.txt", "text/plain", <<2>>)
  let removed = a.File("b.png", "image/png", <<255>>)
  let added = a.File("c.txt", "text/plain", <<3>>)
  assert [a.Changed(old, changed), a.Removed(removed), a.Added(added)]
    == a.diff([old, removed], [changed, added])
  assert [] == a.diff([old], [old])
  let mime = a.File(..old, media_type: "application/octet-stream")
  assert [a.Changed(old, mime)] == a.diff([old], [mime])
}

fn run(ctx, code) {
  tools.execute_all(ctx, [
    tool.Call(
      "test",
      tool.FunctionCall("run", dict.from_list([#("code", utils.String(code))])),
    ),
  ])
}

fn fresh() {
  tools.Context(
    trace: trace.new_session(0),
    cache: cache.ready(),
    counter: 0,
    effects: [],
    context: context.default(),
    artifacts: a.new(),
    policy: None,
    workspace: None,
  )
}

pub fn effects_typecheck_and_persist_between_calls_test() {
  let code =
    "perform Artifact({name: \"map\", bundle: [{path: \"index.html\", media_type: \"text/html\", content: !string_to_binary(\"<h1>map</h1>\")}]})"
  let #(ctx, calls) = run(fresh(), code)
  let assert [tools.Progress(call: tools.Successful(value), ..)] = calls
  assert v.ok(v.Integer(1)) == value
  let #(ctx, calls) = run(ctx, code)
  let assert [tools.Progress(call: tools.Successful(value), ..)] = calls
  assert v.ok(v.Integer(2)) == value
  let #(ctx, calls) =
    run(
      ctx,
      "perform Show({item: Diff({name: \"map\", from: 1, to: 2}), origin: {x:0,y:0}, size: {x:1000,y:1000}})",
    )
  let assert [tools.Progress(call: tools.Successful(value), ..)] = calls
  assert v.ok(v.unit()) == value
  assert 1 == list.length(ctx.artifacts.panels)
  let #(_, calls) = run(ctx, "perform Artifact({name: 1, bundle: []})")
  let assert [tools.Progress(call: tools.Errored(_), ..)] = calls
}

pub fn save_before_async_effect_and_show_after_resuming_test() {
  let code =
    "let _ = perform Artifact({name: \"map\", bundle: [{path: \"index.html\", media_type: \"text/html\", content: !string_to_binary(\"map\")}]}) let _ = perform Alert(\"wait\") perform Show({item: Artifact(\"map\"),origin:{x:0,y:0},size:{x:1000,y:1000}})"
  let #(ctx, calls) = run(fresh(), code)
  let assert [tools.Progress(call: tools.Handling(id, ..), ..)] = calls
  assert 1 == list.length(a.history(ctx.artifacts, "map"))
  let #(ctx, calls) = tools.effect_handled(ctx, calls, id, v.unit())
  let assert [tools.Progress(call: tools.Successful(_), ..)] = calls
  assert [panel(a.Artifact("map"))] == ctx.artifacts.panels
}
