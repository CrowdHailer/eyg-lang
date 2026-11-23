//// A database connection that knows if it is already in a transaction.
////
//// Tests run inside a transaction that is rolled back, so code under test cannot start its own.
//// A transaction on a connection that is already in one is a savepoint instead,
//// it is committed or rolled back with the outer transaction.

import gleam/result
import pog

pub type Db {
  Pool(pog.Connection)
  InTransaction(pog.Connection)
}

pub fn execute(query: pog.Query(t), db: Db) {
  case db {
    Pool(connection) | InTransaction(connection) ->
      pog.execute(query, connection)
  }
}

/// All the writes in `then` are kept, or none of them are.
pub fn transaction(
  db: Db,
  then: fn(Db) -> Result(t, e),
) -> Result(t, pog.TransactionError(e)) {
  case db {
    Pool(connection) ->
      pog.transaction(connection, fn(connection) {
        then(InTransaction(connection))
      })
    InTransaction(connection) -> {
      let run = fn(sql) {
        pog.execute(pog.query(sql), connection)
        |> result.map_error(pog.TransactionQueryError)
      }
      use _ <- result.try(run("SAVEPOINT nested"))
      case then(db) {
        Ok(value) -> {
          use _ <- result.map(run("RELEASE SAVEPOINT nested"))
          value
        }
        Error(reason) -> {
          use _ <- result.try(run("ROLLBACK TO SAVEPOINT nested"))
          Error(pog.TransactionRolledBack(reason))
        }
      }
    }
  }
}
