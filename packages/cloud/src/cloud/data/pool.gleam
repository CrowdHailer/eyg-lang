import gleam/option.{Some}
import gleam/result
import pog

/// The database, by its host and password or by a URL such as `DATABASE_URL`.
pub type Postgres {
  Postgres(host: String, password: String)
  Url(String)
}

pub fn start(name, postgres) {
  let config = case postgres {
    Postgres(host:, password:) ->
      Ok(
        pog.default_config(name)
        |> pog.host(host)
        |> pog.password(Some(password)),
      )
    Url(url) -> pog.url_config(name, url)
  }
  use config <- result.try(result.replace_error(
    config,
    "the database URL is not valid",
  ))
  config
  |> pog.pool_size(5)
  |> pog.start
  |> result.map_error(fn(_) { "the database pool did not start" })
}
