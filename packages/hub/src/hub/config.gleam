import envoy
import gleam/int
import gleam/result.{try}

pub type Config {
  Config(secret_key_base: String, postgres: Postgres, port: Int)
}

pub type Postgres {
  Postgres(host: String, port: Int, password: String)
}

pub fn from_env() {
  use secret_key_base <- try(envoy.get("SECRET_KEY_BASE"))
  use postgres_host <- try(envoy.get("POSTGRES_HOST"))
  use postgres_password <- try(envoy.get("POSTGRES_PASSWORD"))
  let postgres_port =
    envoy.get("POSTGRES_PORT") |> try(int.parse) |> result.unwrap(5432)
  let postgres =
    Postgres(
      host: postgres_host,
      port: postgres_port,
      password: postgres_password,
    )
  // Running more than one hub locally needs a free port.
  let port = envoy.get("PORT") |> try(int.parse) |> result.unwrap(8080)
  Ok(Config(secret_key_base:, postgres:, port:))
}
