import cloud/helpers
import gleam/dynamic/decode
import pog

pub fn conn_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(pog.Returned(rows:, ..)) =
    pog.query("SELECT 42")
    |> pog.returning({
      use number <- decode.field(0, decode.int)
      decode.success(number)
    })
    |> pog.execute(conn)
  assert [42] == rows
}
