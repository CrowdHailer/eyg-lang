import eyg/hub/signatory
import gleam/list
import gleam/option.{None, Some}
import hub/helpers
import hub/signatories/data
import multiformats/cid/v1
import pog
import untethered/substrate

pub fn cant_insert_negative_sequence_test() {
  use conn <- helpers.with_transaction()
  let entry =
    substrate.Entry(
      sequence: 0,
      previous: None,
      signatory: Nil,
      key: "boo",
      content: signatory.AddKey("abc"),
    )
  let assert Error(pog.PostgresqlError(message:, ..)) =
    data.insert_entry(helpers.random_cid(), signatory.encode(entry))
    |> pog.execute(conn)

  assert "Root event (no previous) must have sequence 1, got 0" == message
}

pub fn first_sequence_must_be_1_test() {
  use conn <- helpers.with_transaction()
  let entry =
    substrate.Entry(
      sequence: 2,
      previous: None,
      signatory: Nil,
      key: "boo",
      content: signatory.AddKey("abc"),
    )
  let assert Error(pog.PostgresqlError(message:, ..)) =
    data.insert_entry(helpers.random_cid(), signatory.encode(entry))
    |> pog.execute(conn)

  assert "Root event (no previous) must have sequence 1, got 2" == message
}

pub fn insert_first_entry_test() {
  use conn <- helpers.with_transaction()
  let first_cid = helpers.random_cid()
  let entry =
    substrate.Entry(
      sequence: 1,
      previous: None,
      signatory: Nil,
      key: "boo",
      content: signatory.AddKey("abc"),
    )
  let assert Ok(pog.Returned(rows:, ..)) =
    data.insert_entry(first_cid, signatory.encode(entry))
    |> pog.execute(conn)

  assert 1 == list.length(rows)
  let assert [record] = rows
  assert record.cid == record.entity

  let entry =
    substrate.Entry(
      sequence: 2,
      previous: Some(first_cid),
      signatory: Nil,
      key: "boo",
      content: signatory.AddKey("abc"),
    )
  let assert Ok(pog.Returned(rows:, ..)) =
    data.insert_entry(helpers.random_cid(), signatory.encode(entry))
    |> pog.execute(conn)

  assert 1 == list.length(rows)
  let assert [record2] = rows
  assert record2.cid != record.cid
  assert record2.entity == record.entity
}

pub fn cant_insert_orphan_test() {
  use conn <- helpers.with_transaction()
  let cid = helpers.random_cid()
  let entry =
    substrate.Entry(
      sequence: 2,
      previous: Some(cid),
      signatory: Nil,
      key: "boo",
      content: signatory.AddKey("abc"),
    )
  let assert Error(pog.PostgresqlError(message:, ..)) =
    data.insert_entry(helpers.random_cid(), signatory.encode(entry))
    |> pog.execute(conn)
  let cid = v1.to_string(cid)
  assert "Previous event with CID " <> cid <> " not found" == message
}
// // can't insert the same

// pub fn cant_insert_zero_sequence_test() {
//     use conn <- helpers.with_transaction()
//   let entry =
//     substrate.Entry(
// 
//       sequence: 0,
//       previous: None,
//       signatory: substrate.Signatory(entity: "abc", sequence: 0, key: "abc"),
//       content: protocol.AddKey("abc"),
//     )
//   let assert Error(pog.ConstraintViolated(constraint:, ..)) =
//     data.insert_entry(protocol.encode(entry))
//     |> pog.execute(conn)
//   assert "sequence_is_positive" == constraint
// }
