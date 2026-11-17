import cloud/data/boxes.{Box}
import cloud/data/db
import cloud/helpers
import gleam/option.{None}
import pog
import unixfs/mfs

fn root(contents) {
  mfs.identify(mfs.File(contents)).cid
}

pub fn latest_event_is_the_box_test() {
  use db <- helpers.with_transaction()
  let first = Box("home", 1, root(<<"1">>))
  let second = Box("home", 2, root(<<"2">>))
  let assert Ok(pog.Returned(rows: [_], ..)) =
    db.execute(boxes.record(first, None), db)
  let assert Ok(pog.Returned(rows: [_], ..)) =
    db.execute(boxes.record(second, None), db)

  let assert Ok(pog.Returned(rows: [latest], ..)) =
    db.execute(boxes.latest("home"), db)
  assert second == latest
  let assert Ok(pog.Returned(rows: [], ..)) =
    db.execute(boxes.latest("other"), db)
}

pub fn sequence_is_recorded_once_test() {
  use db <- helpers.with_transaction()
  let first = Box("home", 1, root(<<"1">>))
  let assert Ok(pog.Returned(rows: [_], ..)) =
    db.execute(boxes.record(first, None), db)
  let other = Box("home", 1, root(<<"2">>))
  let assert Ok(pog.Returned(rows: [], ..)) =
    db.execute(boxes.record(other, None), db)
}
