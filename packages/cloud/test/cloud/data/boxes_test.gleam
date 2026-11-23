import cloud/data/boxes.{Box}
import cloud/data/db
import cloud/helpers
import gleam/list
import gleam/option.{None, Some}
import pog
import unixfs/mfs

fn root(contents) {
  mfs.identify(mfs.File(contents)).cid
}

pub fn latest_event_is_the_box_test() {
  use db <- helpers.with_transaction()
  let assert Ok(pog.Returned(rows: [first], ..)) =
    db.execute(boxes.create(Some("home"), root(<<"1">>)), db)
  assert Box(first.id, Some("home"), 1, root(<<"1">>)) == first
  let second = Box(..first, sequence: 2, root: root(<<"2">>))
  let assert Ok(pog.Returned(rows: [_], ..)) =
    db.execute(boxes.record(second), db)

  let assert Ok(pog.Returned(rows: [latest], ..)) =
    db.execute(boxes.latest(first.id), db)
  assert second == latest
  let assert Ok(pog.Returned(rows: [], ..)) =
    db.execute(boxes.latest("other"), db)
}

pub fn sequence_is_recorded_once_test() {
  use db <- helpers.with_transaction()
  let assert Ok(pog.Returned(rows: [first], ..)) =
    db.execute(boxes.create(Some("home"), root(<<"1">>)), db)
  let other = Box(..first, root: root(<<"2">>))
  let assert Ok(pog.Returned(rows: [], ..)) =
    db.execute(boxes.record(other), db)
}

pub fn names_are_unique_test() {
  use db <- helpers.with_transaction()
  let assert Ok(pog.Returned(rows: [_], ..)) =
    db.execute(boxes.create(Some("home"), root(<<"1">>)), db)
  let assert Ok(pog.Returned(rows: [], ..)) =
    db.execute(boxes.create(Some("home"), root(<<"2">>)), db)
}

pub fn only_named_boxes_are_listed_test() {
  use db <- helpers.with_transaction()
  let assert Ok(pog.Returned(rows: [home], ..)) =
    db.execute(boxes.create(Some("home"), root(<<"1">>)), db)
  let assert Ok(pog.Returned(rows: [transient], ..)) =
    db.execute(boxes.create(None, root(<<"1">>)), db)
  let assert Ok(pog.Returned(rows: [_], ..)) =
    db.execute(boxes.create(None, root(<<"1">>)), db)
  assert transient.name == None
  assert transient.id != home.id
  let moved = Box(..home, sequence: 2, root: root(<<"2">>))
  let assert Ok(_) = db.execute(boxes.record(moved), db)

  // Other tests leave named boxes behind.
  let assert Ok(pog.Returned(rows: listed, ..)) = db.execute(boxes.named(), db)
  assert list.contains(listed, moved)
  assert !list.any(listed, fn(box) { box.id == transient.id })
}

// An event that only renames the box keeps the root of the event before it.
pub fn root_is_from_the_latest_event_with_one_test() {
  use db <- helpers.with_transaction()
  let assert Ok(pog.Returned(rows: [home], ..)) =
    db.execute(boxes.create(Some("home"), root(<<"1">>)), db)
  let rename =
    "INSERT INTO box_events (box, seq, name) VALUES ($1, 2, 'house')"
    |> pog.query()
    |> pog.parameter(pog.text(home.id))
  let assert Ok(_) = db.execute(rename, db)
  let assert Ok(pog.Returned(rows: [latest], ..)) =
    db.execute(boxes.latest(home.id), db)
  assert Box(..home, sequence: 2) == latest
}
