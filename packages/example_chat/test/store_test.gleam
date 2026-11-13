import example_chat/store
import gleam/list
import gleam/option.{None, Some}

fn alice() {
  store.Author("U1", "alice", False)
}

fn post(chat, thread, text) {
  let assert Ok(message) =
    store.call(chat, store.Post("C1", thread, alice(), text, _))
  message
}

pub fn replies_join_the_root_thread_test() {
  let assert Ok(chat) = store.start(["general"])
  let root = post(chat, None, "root")
  let reply = post(chat, Some(root.id), "reply")
  let nested = post(chat, Some(reply.id), "reply to reply")
  assert nested.thread == Some(root.id)
}

pub fn reactions_count_each_person_once_test() {
  let assert Ok(chat) = store.start(["general"])
  let message = post(chat, None, "hi")
  let assert Ok(_) =
    store.call(chat, store.React(message.id, "books", alice(), _))
  let assert Ok(message) =
    store.call(chat, store.React(message.id, "books", alice(), _))
  assert message.reactions == [store.Reaction("books", ["alice"])]
}

pub fn events_after_a_sequence_number_test() {
  let assert Ok(chat) = store.start(["general"])
  let _ = post(chat, None, "one")
  let _ = post(chat, None, "two")
  let events = store.call(chat, store.Events(1, _))
  assert list.map(events, fn(e) { e.seq }) == [2]
}

pub fn unknown_channel_test() {
  let assert Ok(chat) = store.start(["general"])
  let assert Error(_) =
    store.call(chat, store.Post("C9", None, alice(), "hi", _))
}
