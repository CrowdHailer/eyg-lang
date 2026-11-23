import cigogne
import cigogne/config as cc
import gleam/option.{None, Some}

pub fn apply_all(conn) {
  let assert Ok(engine) = cigogne.create_engine(config(conn))
  let assert Ok(_) = cigogne.apply_all(engine)
  Nil
}

pub fn rollback_n(conn, count) {
  let assert Ok(engine) = cigogne.create_engine(config(conn))
  let assert Ok(_) = cigogne.rollback_n(engine, count)
  Nil
}

fn config(conn) {
  cc.Config(
    ..cc.default_config,
    database: cc.ConnectionDbConfig(conn),
    migrations: cc.MigrationsConfig(
      application_name: "cloud",
      migration_folder: None,
      dependencies: [],
      no_hash_check: Some(True),
    ),
  )
}
