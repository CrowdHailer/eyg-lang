import gleam/option.{Some}
import hub/config
import pog

pub fn start(postgres_pool_name, postgres) {
  build_config(postgres_pool_name, postgres)
  |> pog.start()
}

pub fn supervised(postgres_pool_name, postgres) {
  build_config(postgres_pool_name, postgres)
  |> pog.supervised()
}

pub fn build_config(postgres_pool_name, postgres) {
  let config.Postgres(host:, password:) = postgres
  pog.default_config(postgres_pool_name)
  |> pog.host(host)
  |> pog.password(Some(password))
  |> pog.pool_size(2)
}
