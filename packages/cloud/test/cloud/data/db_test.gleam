import cloud/data/db
import cloud/helpers
import gleam/dynamic/decode
import pog

fn count(db) {
  let assert Ok(pog.Returned(rows: [count], ..)) =
    pog.query("SELECT count(*)::INT FROM numbers")
    |> pog.returning(decode.at([0], decode.int))
    |> db.execute(db)
  count
}

fn insert(db) {
  let assert Ok(_) =
    pog.query("INSERT INTO numbers VALUES (1)") |> db.execute(db)
  Nil
}

pub fn nested_transaction_test() {
  use db <- helpers.with_transaction()
  let assert Ok(_) =
    pog.query("CREATE TEMP TABLE numbers (x INT)") |> db.execute(db)

  let assert Ok(Nil) =
    db.transaction(db, fn(db) {
      insert(db)
      Ok(Nil)
    })
  assert 1 == count(db)

  let assert Error(pog.TransactionRolledBack("no")) =
    db.transaction(db, fn(db) {
      insert(db)
      Error("no")
    })
  assert 1 == count(db)

  // Savepoints can be nested.
  let assert Ok(Nil) =
    db.transaction(db, fn(db) {
      insert(db)
      let assert Error(_) =
        db.transaction(db, fn(db) {
          insert(db)
          Error(Nil)
        })
      Ok(Nil)
    })
  assert 2 == count(db)
}
