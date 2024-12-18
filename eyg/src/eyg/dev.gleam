import eyg/editor/v1
import eyg/package
import eyg/sync/cid
import eyg/sync/seed
import eyg/sync/sync
import eyg/website/documentation
import eyg/website/editor
import eyg/website/home
import eyg/website/news
import eyg/website/social
import eygir/decode
import eygir/encode
import eygir/expression
import gleam/bit_array
import gleam/dict
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/string
import intro/content
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import midas/node
import midas/task as t
import mysig/asset
import mysig/html
import mysig/layout
import mysig/local
import mysig/neo

pub fn app_script(src) {
  h.script([a.attribute("defer", ""), a.attribute("async", ""), a.src(src)], "")
}

fn examine_page(bundle) {
  use script <- t.do(t.bundle("examine/app", "run"))
  use script <- t.do(asset.resource(asset.js("examine", script), bundle))
  use layout <- t.do(asset.resource(layout.css, bundle))
  use neo <- t.do(asset.resource(neo.css, bundle))
  let head = [
    html.stylesheet(asset.tailwind_2_2_11),
    layout,
    neo,
    script,
    html.plausible("eyg.run"),
  ]
  let content =
    html.doc(head, [h.div([], [html.empty_lustre()])])
    |> element.to_document_string()
    |> bit_array.from_string()
  t.done(#("/examine/index.html", content))
}

fn shell_page(bundle) {
  use spec <- t.do(t.read("../../midas_sdk/priv/netlify.openapi.json"))
  let assert Ok(spec) = bit_array.to_string(spec)
  use script <- t.do(t.bundle("eyg/shell/app", "run"))
  use script <- t.do(asset.resource(asset.js("shell", script), bundle))
  use layout <- t.do(asset.resource(layout.css, bundle))
  use neo <- t.do(asset.resource(neo.css, bundle))

  let content =
    html.doc(
      [
        html.stylesheet(asset.tailwind_2_2_11),
        layout,
        neo,
        script,
        html.plausible("eyg.run"),
      ],
      [
        h.div([], [html.empty_lustre()]),
        h.script(
          [a.type_("application/json"), a.id("netlify.openapi.json")],
          spec,
        ),
      ],
    )
    |> element.to_document_string()
    |> bit_array.from_string()
  t.done(#("/shell/index.html", content))
}

const redirects = "
/packages/* /packages/index.html 200
/auth/* https://eyg-backend.fly.dev/auth/:splat 200
/api/dnsimple/* https://eyg-backend.fly.dev/dnsimple/:splat 200
/api/twitter/* https://eyg-backend.fly.dev/twitter/:splat 200
/api/netlify/* https://eyg-backend.fly.dev/netlify/:splat 200
/api/github/* https://eyg-backend.fly.dev/github/:splat 200
"

fn ref_file(ref, exp) {
  let data = <<encode.to_json(exp):utf8>>
  let path = "/references/" <> ref <> ".json"
  [#(path, data)]
}

fn cache_to_references_files(cache) {
  let sync.Sync(loaded: loaded, ..) = cache
  loaded
  |> dict.to_list()
  |> list.flat_map(fn(entry) {
    let #(ref, sync.Computed(expression: exp, ..)) = entry
    ref_file(ref, exp)
  })
}

fn package_page(script_asset, bundle) {
  use script <- t.do(asset.resource(script_asset, bundle))
  use layout <- t.do(asset.resource(layout.css, bundle))
  use neo <- t.do(asset.resource(neo.css, bundle))
  html.doc(
    [
      html.stylesheet(asset.tailwind_2_2_11),
      layout,
      neo,
      script,
      html.plausible("eyg.run"),
    ],
    [h.div([], [html.empty_lustre()])],
  )
  |> element.to_document_string()
  |> bit_array.from_string()
  |> t.done()
}

// TODO remove an make remotes optional in sync
const origin = sync.Origin(http.Https, "", None)

fn build_intro(preview, bundle) {
  use script <- t.do(t.bundle("intro/intro", "run"))
  let package_asset = asset.js("package", script)
  // TODO remove stdlib soon should be caught be seed
  use stdlib <- t.do(t.read("seed/eyg/std.json"))

  let assert Ok(expression) =
    decode.from_json({
      let assert Ok(stdlib) = bit_array.to_string(stdlib)
      stdlib
    })
  let std_hash = cid.for_expression(expression)
  use Nil <- t.do(t.log(std_hash))

  use content <- t.do(
    t.each(content.pages(), fn(page) {
      let #(name, content) = page
      let #(cache, _before, _public, _ref) =
        package.load_guide_from_content(content, sync.init(origin))
      let references = cache_to_references_files(cache)

      use page <- t.do(package_page(package_asset, bundle))
      let page = #("/packages/eyg/" <> name <> "/index.html", page)
      case preview {
        True -> [page, ..references]
        False -> references
      }
      |> t.done()
    }),
  )
  let content = list.flatten(content)

  use groups <- t.do(t.list("seed"))
  use packages <- t.do(
    t.each(groups, fn(group) {
      use files <- t.do(t.list("seed/" <> group))
      t.each(files, fn(file) {
        use bytes <- t.do(t.read("seed/" <> group <> "/" <> file))
        let assert Ok(#(name, "json")) = string.split_once(file, ".")
        let assert Ok(#(cache, _before, _public, _ref)) =
          package.load_guide_from_bytes(
            bytes,
            sync.init(sync.Origin(http.Https, "", None)),
          )
        let references = case sync.fetch_all_missing(cache).1 {
          [] -> {
            let references = cache_to_references_files(cache)

            io.debug(#(file, listx.keys(references)))
            references
          }
          tasks -> {
            io.debug(
              "---- Needs dependencies so we can't check yet need a treee load approach for "
              <> file,
            )
            io.debug(listx.keys(tasks))
            let assert Ok(source) = sync.decode_bytes(bytes)
            let #(assigns, _) = expression.expression_to_block(source)
            let exports =
              list.fold(listx.keys(assigns), expression.Empty, fn(rest, key) {
                expression.Apply(
                  expression.Apply(
                    expression.Extend(key),
                    expression.Variable(key),
                  ),
                  rest,
                )
              })
            let source = expression.block_to_expression(assigns, exports)

            let ref = cid.for_expression(source)
            io.debug(#(name, "===", ref))
            ref_file(ref, source)
          }
        }
        let package = #("/packages/" <> group <> "/" <> file, bytes)
        use page <- t.do(package_page(package_asset, bundle))
        let page = #(
          "/packages/" <> group <> "/" <> name <> "/index.html",
          page,
        )
        let files = case preview {
          True -> {
            [page, package, ..references]
          }
          False -> [package, ..references]
        }

        t.done(files)
      })
    }),
  )
  let packages = list.flatten(list.flatten(packages))
  // let seed = list.map()

  // needs to use the cli or CI for functions

  use pak_page <- t.do(package_page(package_asset, bundle))
  t.done(
    [
      #("/packages/index.html", pak_page),
      #("/guide/" <> "intro" <> "/index.html", pak_page),
      #("/references/" <> std_hash <> ".json", stdlib),
    ]
    |> list.append(packages)
    |> list.append(content)
    // make unique by key
    |> dict.from_list()
    |> dict.to_list(),
  )
}

fn datalog_page(bundle) {
  use script <- t.do(t.bundle("datalog/browser/app", "run"))
  use script <- t.do(asset.resource(asset.js("datalog", script), bundle))
  use layout <- t.do(asset.resource(layout.css, bundle))
  use neo <- t.do(asset.resource(neo.css, bundle))
  html.doc(
    [
      html.stylesheet(asset.tailwind_2_2_11),
      layout,
      neo,
      script,
      html.plausible("eyg.run"),
    ],
    [h.div([], [html.empty_lustre()])],
  )
  |> element.to_document_string()
  |> bit_array.from_string()
  |> t.done()
}

fn build_datalog(bundle) {
  use page <- t.do(datalog_page(bundle))
  use movies <- t.do(t.read("src/datalog/examples/movies.csv"))
  let files = [#("/examples/movies.csv", movies)]

  t.done([#("/datalog/index.html", page), ..files])
}

pub fn build(bundle) -> t.Effect(List(#(String, BitArray))) {
  use documentation <- t.do(documentation.page(bundle))
  use home <- t.do(home.page(bundle))
  use editor <- t.do(editor.page(bundle))

  // relies on intro
  t.done([
    #("/documentation/index.html", documentation),
    #("/editor/index.html", editor),
    #("/index.html", home),
  ])
}

pub fn develop(args) {
  let bundle = asset.new_bundle("/assets")
  use pages <- t.do(case args {
    ["home"] -> {
      use home <- t.do(home.page(bundle))
      t.done([#("/index.html", home)])
    }
    ["social"] -> {
      t.done([#("/index.html", social.render())])
    }
    _ -> {
      // TODO bring closer togeher
      use editor <- t.do(case False {
        True -> editor.page(bundle)
        False -> v1.page(bundle)
      })
      [#("/editor/index.html", editor)]
      |> t.done()
    }
  })
  let pages = list.append(pages, asset.to_files(bundle))

  // task for handler as it does hashing
  // This code is not reloaded
  use static <- t.do(local.handler(pages))
  let handler = fn(req) {
    case request.path_segments(req) {
      // can write to file in promise as long as async
      ["publish"] -> {
        let task = {
          use Nil <- t.do(t.write("priv/db.json", <<"{}">>))
          t.log("written")
        }
        promise.map(node.run(task, ""), io.debug)
        response.new(201)
        |> response.set_body(<<>>)
      }
      _ -> static(req)
    }
  }

  use Nil <- t.do(t.serve(Some(8080), handler))
  use Nil <- t.do(t.log("serving on 8080"))
  t.done(Nil)
}

// Remember to only add mysig at the top level
pub fn preview(args) {
  case args {
    ["home"] -> {
      let bundle = asset.new_bundle("/assets")
      use v1_site <- t.do(build(bundle))
      use intro <- t.do(build_intro(True, bundle))

      t.done(
        [v1_site, intro, asset.to_files(bundle)]
        |> list.flatten(),
      )
    }
    _ -> {
      let bundle = asset.new_bundle("/assets")
      use v1_site <- t.do(build(bundle))
      use seeds <- t.do(seed.from_dir("seed"))
      // use examine <- t.do(examine_page(bundle))
      use shell <- t.do(shell_page(bundle))
      // use intro <- t.do(build_intro(True, bundle))
      // Note news puts pea image into assets without hashing
      use news <- t.do(news.build())
      // use datalog <- t.do(build_datalog(bundle))
      use share <- t.do(t.read("/share.png"))

      let files =
        list.flatten([
          v1_site,
          // Need moving so that project name and top module name match.
          // midas assumes that this is the case when looking for the module
          // [examine],
          // intro,
          // datalog,
          [shell],
          seeds,
          news,
          asset.to_files(bundle),
          [#("/_redirects", <<redirects:utf8>>), #("/share.png", share)],
        ])
      io.debug(listx.keys(files))
      t.done(files)
    }
  }
}
