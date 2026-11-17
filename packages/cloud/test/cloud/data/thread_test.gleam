import cloud/data/db
import cloud/data/thread.{Node}
import cloud/helpers
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import pog

fn history(db, head) {
  let assert Ok(pog.Returned(rows:, ..)) = db.execute(thread.history(head), db)
  list.map(rows, fn(entry: #(Int, thread.Node)) { entry.1 })
}

fn count(db) {
  let assert Ok(pog.Returned(rows: [count], ..)) =
    pog.query("SELECT count(*)::INT FROM thread_events")
    |> pog.returning(decode.at([0], decode.int))
    |> db.execute(db)
  count
}

pub fn keys_identify_the_history_test() {
  let assert [Node(first, None, _), Node(second, Some(parent), _)] =
    thread.nodes(None, ["{\"a\":1}", "{\"b\":2}"])
  assert parent == first
  // The same event after a different history has a different key.
  let assert [Node(other, ..)] = thread.nodes(None, ["{\"b\":2}"])
  assert other != second
  assert thread.nodes(None, ["{\"a\":1}"]) == thread.nodes(None, ["{\"a\":1}"])
}

pub fn append_and_read_history_test() {
  use db <- helpers.with_transaction()
  let before = count(db)
  let nodes = thread.nodes(None, ["{\"a\":1}", "{\"b\":2}"])
  let assert Ok(_) = db.execute(thread.insert(nodes), db)
  let assert Ok(Node(head, ..)) = list.last(nodes)
  assert nodes == history(db, head)
  // A key can be made again from what was stored.
  let assert [Node(key, parent, payload), ..] = history(db, head)
  assert key == thread.key(parent, payload)

  // Appending the same events again adds nothing.
  let assert Ok(_) = db.execute(thread.insert(nodes), db)
  assert before + 2 == count(db)

  // Two branches from the same event share the history before it.
  let assert [Node(one, ..)] as branch =
    thread.nodes(Some(head), ["{\"c\": 3}"])
  let assert Ok(_) = db.execute(thread.insert(branch), db)
  let assert [Node(two, ..)] as branch =
    thread.nodes(Some(head), ["{\"d\": 4}"])
  let assert Ok(_) = db.execute(thread.insert(branch), db)
  let assert [first, second, Node(_, _, "{\"c\": 3}")] = history(db, one)
  assert [first, second] == nodes
  let assert [_, _, Node(_, _, "{\"d\": 4}")] = history(db, two)
  assert before + 4 == count(db)
}
