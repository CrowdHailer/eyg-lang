import cigogne
import cigogne/config as cc
import gleam/option.{None, Some}

pub fn apply_all(conn) {
  let config = config(conn)
  let assert Ok(engine) = cigogne.create_engine(config)
  let assert Ok(_) = cigogne.apply_all(engine)
  Nil
}

pub fn rollback_n(connection_with_schema, count) {
  let config = config(connection_with_schema)
  let assert Ok(engine) = cigogne.create_engine(config)
  let assert Ok(_) = cigogne.rollback_n(engine, count)
  Nil
}

pub fn config(conn) {
  cc.Config(
    ..cc.default_config,
    database: cc.ConnectionDbConfig(conn),
    migrations: cc.MigrationsConfig(
      application_name: "hub",
      migration_folder: None,
      dependencies: [],
      no_hash_check: Some(True),
    ),
  )
}
