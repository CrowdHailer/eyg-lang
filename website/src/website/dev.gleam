import gleam/bit_array
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import lustre/element
import midas/node
import midas/task as t
import mysig/build
import mysig/dev
import mysig/route.{Route}
import netlify
import plinth/node/process
import simplifile
import snag
import website/routes/documentation
import website/routes/editor
import website/routes/home
import website/routes/news
import website/routes/news/archive
import website/routes/news/edition
import website/routes/roadmap

pub fn main() {
  do_main(list.drop(array.to_list(process.argv()), 2))
}

fn do_main(args) {
  use result <- promise.map(case args {
    [] as args | ["develop", ..args] -> develop(args)
    ["deploy"] -> deploy(args)
    ["email"] -> email()
    ["embed"] -> embed()

    _ ->
      promise.resolve(snag.error("no runner for: " <> args |> string.join(" ")))
  })
  case result {
    Ok(Nil) -> Nil
    Error(reason) -> io.println(snag.pretty_print(reason))
  }
}

// doesn't have client secret
pub const netlify_local_app = netlify.App(
  "cQmYKaFm-2VasrJeeyobXXz5G58Fxy2zQ6DRMPANWow",
  "http://localhost:8080/auth/netlify",
)

const site_id = "eae24b5b-4854-4973-8a9f-8fb3b1c423c0"

fn deploy(_args) {
  use files <- promise.try_await(build.to_files(routes()))
  let task = {
    use token <- t.do(netlify.authenticate(netlify_local_app))
    use _ <- t.do(netlify.deploy_site(token, site_id, files))
    use _ <- t.do(t.log("Deployed"))
    t.done(Nil)
  }
  node.run(task, ".")
}

fn develop(_args) {
  dev.serve(routes())
  promise.resolve(Ok(Nil))
}

const redirects = "
/packages/* /packages/index.html 200
/auth/* https://eyg-backend.fly.dev/auth/:splat 200
/api/dnsimple/* https://eyg-backend.fly.dev/dnsimple/:splat 200
/api/twitter/* https://eyg-backend.fly.dev/twitter/:splat 200
/api/netlify/* https://eyg-backend.fly.dev/netlify/:splat 200
/api/github/* https://eyg-backend.fly.dev/github/:splat 200
"

fn routes() {
  let assert Ok(share) = simplifile.read_bits("src/website/share.png")
  let assert Ok(pea) = simplifile.read_bits("src/website/images/pea.webp")

  Route(index: route.Page(home.page()), items: [
    #("_redirects", Route(route.Static(<<redirects:utf8>>), [])),
    #("share.png", Route(route.Static(share), [])),
    // Keep for old emails
    #("pea.webp", Route(route.Static(pea), [])),
    #(
      "documentation",
      Route(index: route.Page(documentation.page()), items: []),
    ),
    #("editor", Route(index: route.Page(editor.page()), items: [])),
    #("news", news.route()),
    #("roadmap", Route(index: route.Page(roadmap.page()), items: [])),
  ])
}

const replace_string = "!CONTENT!"

fn email() {
  let task = {
    use template <- t.do(t.read("src/website/routes/news/edition/email.html"))
    use template <- t.try(
      bit_array.to_string(template)
      |> result.replace_error(snag.new("not a utf8 string")),
    )
    let assert [latest, ..] = archive.published
    let content =
      element.to_string(edition.render(
        latest,
        list.length(archive.published),
        "https://eyg.run/pea.webp",
      ))
    let output = string.replace(template, replace_string, content)
    t.write("email.html", <<output:utf8>>)
  }

  node.run(task, ".")
}

fn embed() {
  let task = {
    use bundle <- t.do(t.bundle("website/embed", "run"))
    t.write("embed.js", <<bundle:utf8>>)
  }
  node.run(task, ".")
}
