//// Print-ready assets through Chrome's native command-line interface.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import gleam/string
import gleam/uri
import otel
import simplifile
import tracing/host

fn chrome(arguments, input) {
  let binary = otel.env_value(otel.environment(), "CHROME_BIN", "google-chrome")
  use output <- promise.map(
    host.command(
      [
        binary,
        "--headless",
        "--no-sandbox",
        "--disable-gpu",
        "--hide-scrollbars",
        ..list.append(arguments, [input])
      ],
      ".",
      [],
    ),
  )
  use output <- result.try(output)
  case output.status {
    0 -> Ok(Nil)
    _ -> Error(output.stderr)
  }
}

pub fn run(directory: String) -> Promise(Result(Nil, String)) {
  let assert Ok(cwd) = simplifile.current_directory()
  let path = case string.starts_with(directory, "/") {
    True -> directory
    False -> cwd <> "/" <> directory
  }
  let url =
    "file://"
    <> {
      string.split(path, "/")
      |> list.map(uri.percent_encode)
      |> string.join("/")
    }
  use _ <- promise.try_await(chrome(
    ["--no-pdf-header-footer", "--print-to-pdf=" <> path <> "/otel-in-eyg.pdf"],
    url <> "/index.html",
  ))
  let names = [
    "01-paced-workflow",
    "02-http-workflow",
    "03-retry",
    "04-recovered-error",
    "05-failed-run",
    "profile-elapsed",
    "profile-active",
  ]
  use _ <- promise.try_await(images(names, path, url))
  use _ <- promise.try_await(chrome(
    ["--window-size=1600,1050", "--screenshot=" <> path <> "/profile-view.png"],
    url <> "/profile.html",
  ))
  use _ <- promise.try_await(chrome(
    [
      "--window-size=1600,1050",
      "--screenshot=" <> path <> "/profile-view-active.png",
    ],
    url <> "/profile.html#active",
  ))
  chrome(
    ["--window-size=1440,800", "--screenshot=" <> path <> "/timeline.png"],
    url <> "/timeline.html",
  )
}

fn images(names, path, url) {
  case names {
    [] -> promise.resolve(Ok(Nil))
    [name, ..rest] ->
      case simplifile.read(path <> "/" <> name <> ".svg") {
        Error(simplifile.Enoent) -> images(rest, path, url)
        Error(reason) ->
          promise.resolve(Error(simplifile.describe_error(reason)))
        Ok(svg) -> {
          let height =
            string.split(svg, "height=\"")
            |> list.drop(1)
            |> list.first
            |> result.unwrap("800")
            |> string.split("\"")
            |> list.first
            |> result.unwrap("800")
            |> int.parse
            |> result.unwrap(800)
          use _ <- promise.try_await(chrome(
            [
              "--window-size=1400," <> int.to_string(height),
              "--screenshot=" <> path <> "/" <> name <> ".png",
            ],
            url <> "/" <> name <> ".svg",
          ))
          images(rest, path, url)
        }
      }
  }
}
