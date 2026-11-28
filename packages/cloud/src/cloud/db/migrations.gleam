import cigogne
import cigogne/config
import gleam/option.{None, Some}
import gleam/result
import pog

// TODO this approach requires API changes in the library
// pub fn main(conn: pog.Connection, args: List(String)) {
//   let outcome =
//     cli.get_action("cloud", args)
//     |> result.map_error(fn(_) { cigogne.UnmatchedCommandError })
//     |> result.try(cigogne.run_command(_, cigogne_config))

//   case outcome {
//     Ok(_) -> Nil
//     Error(UnmatchedCommandError) -> {
//       // the CLI library already prints a helpful message.
//       halt(2)
//     }
//     Error(ExecutionError(error)) -> {
//       print_error(error)
//       halt(1)
//     }
//   }
// }
pub fn apply_all(conn: pog.Connection) -> Result(Nil, cigogne.CigogneError) {
  let config = config(conn)
  use engine <- result.try(cigogne.create_engine(config))
  cigogne.apply_all(engine)
}

pub fn apply_n(
  conn: pog.Connection,
  count,
) -> Result(Nil, cigogne.CigogneError) {
  let config = config(conn)
  use engine <- result.try(cigogne.create_engine(config))
  cigogne.apply_n(engine, count)
}

pub fn rollback_n(connection, count) {
  let config = config(connection)
  use engine <- result.try(cigogne.create_engine(config))
  cigogne.rollback_n(engine, count)
}

fn config(conn) {
  config.Config(
    database: config.ConnectionDbConfig(conn),
    migrations: config.MigrationsConfig(
      application_name: "cloud",
      migration_folder: None,
      dependencies: [],
      no_hash_check: Some(False),
    ),
    migration_table: config.default_mig_table_config,
  )
}
