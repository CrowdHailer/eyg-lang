import gleam/dict
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/string
import mysig/build
import mysig/dev
import mysig/route.{Route}
import plinth/node/process
import website/routes/documentation
import website/routes/editor
import website/routes/home
import website/routes/news

pub fn main() {
  do_main(list.drop(array.to_list(process.argv()), 2))
}

fn do_main(args) {
  case args {
    [] as args | ["develop", ..args] -> develop(args)
    ["build"] -> build(args)
    _ -> {
      io.println("no runner for: " <> args |> string.join(" "))
      process.exit(1)
      promise.resolve(1)
    }
  }
}

fn build(_args) {
  use result <- promise.await(build.to_files(routes()))
  case result {
    Ok(files) -> {
      io.debug(dict.keys(dict.from_list(files)))
      todo
    }
    Error(reason) -> promise.resolve(1)
  }
}

fn develop(_args) {
  dev.serve(routes())
  promise.resolve(0)
}

fn routes() {
  Route(index: home.page(), items: [
    #("documentation", Route(index: documentation.page(), items: [])),
    #("editor", Route(index: editor.page(), items: [])),
    #("news", news.route()),
  ])
}
