import gleam/dynamic/decode
import hub/helpers.{with_transaction}
import pog

pub fn access_db_test() {
  use conn <- with_transaction()
  let query =
    pog.query("SELECT 42;")
    |> pog.returning({
      use number <- decode.field(0, decode.int)
      decode.success(number)
    })
  let assert Ok(returned) = pog.execute(query, conn)
  assert [42] == returned.rows
}
