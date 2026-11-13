import example_chat/store
import example_chat/view
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element

pub fn messages_threads_reactions_and_channel_switches_test() {
  let assert Ok(store) = store.start(["general", "other"])
  let #(model, _) = view.init(view.Args(store, "alice", "general"))
  let #(model, _) = view.update(model, view.Send(False, "hello"))
  let assert [root] = model.messages
  assert root.author.name == "alice"
  assert root.thread == None
  assert model.input == ""
  let #(model, _) = view.update(model, view.OpenThread(root.id))
  let #(model, _) = view.update(model, view.Send(True, "reply"))
  let assert [_, reply] = model.messages
  assert reply.thread == Some(root.id)
  let #(model, _) = view.update(model, view.React(root.id, "books"))
  let assert [root, _] = model.messages
  assert root.reactions == [store.Reaction("books", ["alice"])]
  let #(model, _) = view.update(model, view.ChooseChannel("C2"))
  assert model.messages == []
  assert model.thread == None
}

pub fn live_refresh_keeps_drafts_and_renders_external_posts_safely_test() {
  let assert Ok(store) = store.start(["general"])
  let #(model, _) = view.init(view.Args(store, "alice", "general"))
  let #(model, _) = view.update(model, view.Typed(False, "unfinished"))
  let author = store.Author("bot", "<script>bad()</script>", True)
  let assert Ok(_) =
    store.call(store, store.Post(
      "C1",
      None,
      author,
      "**Hello** `code`\n```eyg\n42\n```\n<script>bad()</script>",
      _,
    ))
  let #(model, _) = view.update(model, view.Poll)
  assert model.input == "unfinished"
  assert list.length(model.messages) == 1
  let html = element.to_string(view.view(model))
  assert string.contains(html, "<b>Hello</b>")
  assert string.contains(html, "<code>code</code>")
  assert string.contains(html, "&lt;script&gt;")
  assert !string.contains(html, "<script>bad()")
}
