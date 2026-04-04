import gleam/option.{Some}
import pog

pub fn start(postgres_pool_name, postgres_password) {
  build_config(postgres_pool_name, postgres_password)
  |> pog.start()
}

pub fn supervised(postgres_pool_name, postgres_password) {
  build_config(postgres_pool_name, postgres_password)
  |> pog.supervised()
}

pub fn build_config(postgres_pool_name, postgres_password) {
  pog.default_config(postgres_pool_name)
  // TODO real host
  |> pog.host("localhost")
  |> pog.password(Some(postgres_password))
  |> pog.pool_size(2)
}
