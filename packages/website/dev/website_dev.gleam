import argv
import filepath
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import mysig/build
import mysig/dev
import mysig/route.{Route}
import simplifile
import snag
import website/routes/documentation
import website/routes/home
import website/routes/news
import website/routes/roadmap
import website/routes/workspace

pub fn main() {
  do_main(argv.load().arguments)
}

fn do_main(args) {
  use result <- promise.map(case args {
    [] as args | ["develop", ..args] -> develop(args)
    ["build"] -> build()

    _ ->
      promise.resolve(snag.error("no runner for: " <> args |> string.join(" ")))
  })
  case result {
    Ok(Nil) -> Nil
    Error(reason) -> io.println(snag.pretty_print(reason))
  }
}

fn develop(_args) {
  dev.serve(routes())
  promise.resolve(Ok(Nil))
}

fn build() {
  use files <- promise.try_await(build.to_files(routes()))
  list.try_each(files, fn(file) {
    let #(path, bytes) = file

    use Nil <- result.try(
      simplifile.create_directory_all(filepath.directory_name("./dist" <> path)),
    )
    simplifile.write_bits("./dist" <> path, bytes)
  })
  |> snag.map_error(simplifile.describe_error)
  |> promise.resolve
}

fn routes() {
  let assert Ok(share) = simplifile.read_bits("src/website/share.png")
  let assert Ok(pea) = simplifile.read_bits("src/website/images/pea.webp")

  Route(index: route.Page(home.page()), items: [
    #("share.png", Route(route.Static(share), [])),
    // Keep for old emails
    #("pea.webp", Route(route.Static(pea), [])),
    #(
      "documentation",
      Route(index: route.Page(documentation.page()), items: []),
    ),
    // This old editor was a shell only
    // #("editor", Route(index: route.Page(editor.page()), items: [])),
    #("editor", Route(index: route.Page(workspace.page()), items: [])),
    #("news", news.route()),
    #("roadmap", Route(index: route.Page(roadmap.page()), items: [])),
  ])
}
