//// Grant a signatory permission to publish releases under a package name.
////
//// Access is granted manually by an administrator running this task and requires the same env as the server.
////
////     gleam run -m hub/dev/grant_owner <package> <entity_id>
////
//// `<entity_id>` is the signatory entity CID.

import argv
import gleam/erlang/process
import gleam/io
import gleam/string
import hub/config
import hub/db/pool
import hub/packages/data
import hub/packages/name
import pog

pub fn main() -> Nil {
  case argv.load().arguments {
    [package, entity_id] -> grant(package, entity_id)
    _ -> {
      io.println(
        "usage: gleam run -m hub/dev/grant_owner <package> <entity_id>",
      )
      io.println(
        "grants signatory <entity_id> permission to publish under <package>",
      )
    }
  }
}

fn grant(package: String, entity_id: String) -> Nil {
  case name.valid(package) {
    False ->
      io.println(
        "error: invalid package name; use 1-64 chars of lowercase letters, "
        <> "digits and single hyphens, starting with a letter",
      )
    True -> do_grant(package, entity_id)
  }
}

fn do_grant(package: String, entity_id: String) -> Nil {
  let assert Ok(config) = config.from_env()
  let name = process.new_name("grant_owner_pool")
  let assert Ok(_) = pool.start(name, config.postgres)
  let conn = pog.named_connection(name)

  case pog.execute(data.record_owner(package, entity_id), conn) {
    Ok(pog.Returned(rows: [owner], ..)) ->
      io.println(
        "granted " <> owner.entity_id <> " ownership of " <> owner.package,
      )
    Ok(_) -> io.println("error: ownership row was not written")
    Error(reason) -> {
      io.println("error: failed to grant ownership")
      io.println(string.inspect(reason))
    }
  }
}
