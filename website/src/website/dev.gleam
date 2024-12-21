import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/string
import midas/node
import midas/task as t
import mysig/asset
import mysig/local
import mysig/route.{Route}
import plinth/node/process
import snag
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
    _ -> {
      io.println("no runner for: " <> args |> string.join(" "))
      process.exit(1)
      promise.resolve(1)
    }
  }
}

fn develop(args) {
  let task = {
    use static <- t.do(build(args))
    use Nil <- t.do(local.serve(Some(8080), static))
    use Nil <- t.do(t.log("serving on 8080"))
    t.done(Nil)
  }
  use _ <- promise.map(
    node.watch(task, ".", fn(result) {
      case result {
        Ok(Nil) -> Nil
        Error(reason) -> io.println(snag.pretty_print(reason))
      }
    }),
  )
  0
}

pub fn build(args) {
  let bundle = asset.new_bundle("/assets")
  // TODO lazy Route takes task
  case args {
    ["home"] -> {
      use home <- t.do(home.page(bundle))
      let routes = Route(index: home, items: [])
      let pages = list.append(route.to_files(routes), asset.to_files(bundle))
      t.done(pages)
    }
    ["editor"] -> {
      use editor <- t.do(editor.page(bundle))
      let routes = Route(index: editor, items: [])
      let pages = list.append(route.to_files(routes), asset.to_files(bundle))
      t.done(pages)
    }
    _ -> {
      use home <- t.do(home.page(bundle))
      use documentation <- t.do(documentation.page(bundle))
      use editor <- t.do(editor.page(bundle))
      use news <- t.do(news.route(bundle))

      let routes =
        Route(index: home, items: [
          #("documentation", Route(index: documentation, items: [])),
          #("editor", Route(index: editor, items: [])),
          #("news", news),
        ])
      let pages = list.append(route.to_files(routes), asset.to_files(bundle))
      t.done(pages)
    }
  }
}
