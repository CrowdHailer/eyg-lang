import gleam/option.{Some}
import pog

pub type Postgres {
  Postgres(host: String, password: String)
}

pub fn start(name, postgres) {
  let Postgres(host:, password:) = postgres
  pog.default_config(name)
  |> pog.host(host)
  |> pog.password(Some(password))
  |> pog.pool_size(2)
  |> pog.start
}
