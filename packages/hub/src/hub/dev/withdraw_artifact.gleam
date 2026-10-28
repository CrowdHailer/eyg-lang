//// Stop serving a shared artifact, for example one reported as abusive.
////
//// Requires the same env as the server.
////
////     gleam run -m hub/dev/withdraw_artifact <id>
////
//// A withdrawn artifact is not found at any of its URLs.
//// Its files stay in the database until it is removed by hand.

import argv
import eyg/hub/artifact as rules
import gleam/erlang/process
import gleam/io
import gleam/string
import hub/artifacts/data
import hub/config
import hub/db/pool
import pog

pub fn main() -> Nil {
  case argv.load().arguments {
    [id] ->
      case rules.valid_id(id) {
        True -> withdraw(id)
        False -> io.println("error: artifact ids are lowercase UUIDs")
      }
    _ -> io.println("usage: gleam run -m hub/dev/withdraw_artifact <id>")
  }
}

fn withdraw(id: String) -> Nil {
  let assert Ok(config) = config.from_env()
  let name = process.new_name("withdraw_artifact_pool")
  let assert Ok(_) = pool.start(name, config.postgres)
  let conn = pog.named_connection(name)

  case pog.execute(data.withdraw(id), conn) {
    Ok(pog.Returned(rows: [id], ..)) -> io.println("withdrew artifact " <> id)
    Ok(_) -> io.println("error: no artifact " <> id <> " is being served")
    Error(reason) -> {
      io.println("error: failed to withdraw artifact")
      io.println(string.inspect(reason))
    }
  }
}
