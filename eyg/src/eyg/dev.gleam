import eyg/package
import eyg/sync/cid
import eyg/sync/sync
import eyg/website/documentation
import eyg/website/editor
import eyg/website/home
import eyg/website/news
import eygir/decode
import eygir/encode
import eygir/expression
import gleam/bit_array
import gleam/dict
import gleam/http
import gleam/io
import gleam/list
import gleam/listx
import gleam/option.{None}
import gleam/string
import intro/content
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import midas/task as t
import mysig
import mysig/layout
import mysig/neo

pub fn doc(title, domain, head, body) {
  h.html([a.attribute("lang", "en")], [
    h.head([], list.append(common_head_tags(title, domain), head)),
    h.body([], body),
  ])
}

fn common_head_tags(title, domain) {
  [
    h.meta([a.attribute("charset", "UTF-8")]),
    h.meta([
      a.attribute("http-equiv", "X-UA-Compatible"),
      a.attribute("content", "IE=edge"),
    ]),
    h.meta([a.attribute("viewport", "width=device-width, initial-scale=1.0")]),
    h.title([], title),
    h.script(
      [
        a.attribute("defer", ""),
        a.attribute("data-domain", domain),
        a.src("https://plausible.io/js/script.js"),
      ],
      "",
    ),
  ]
}

pub fn stylesheet(reference) {
  h.link([a.rel("stylesheet"), a.href(reference)])
}

pub fn empty_lustre() {
  h.div([a.id("app")], [])
}

pub fn app_script(src) {
  h.script([a.attribute("defer", ""), a.attribute("async", ""), a.src(src)], "")
}

fn examine_page(bundle) {
  use script <- t.do(t.bundle("examine/app", "run"))
  let content =
    doc(
      "Eyg - examiner",
      "eyg.run",
      [
        stylesheet(mysig.tailwind_2_2_11),
        mysig.resource(layout.css, bundle),
        mysig.resource(neo.css, bundle),
        mysig.resource(mysig.js("examine", script), bundle),
      ],
      [h.div([], [empty_lustre()])],
    )
    |> element.to_document_string()
    |> bit_array.from_string()
  t.done(#("/examine/index.html", content))
}

fn shell_page(bundle) {
  use script <- t.do(t.bundle("eyg/shell/app", "run"))

  let content =
    doc(
      "Eyg - shell",
      "eyg.run",
      [
        stylesheet(mysig.tailwind_2_2_11),
        mysig.resource(layout.css, bundle),
        mysig.resource(neo.css, bundle),
        mysig.resource(mysig.js("shell", script), bundle),
      ],
      [h.div([], [empty_lustre()])],
    )
    |> element.to_document_string()
    |> bit_array.from_string()
  t.done(#("/shell/index.html", content))
}

const redirects = "
/packages/* /packages/index.html 200
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
  doc(
    "Eyg - shell",
    "eyg.run",
    [
      stylesheet(mysig.tailwind_2_2_11),
      mysig.resource(layout.css, bundle),
      mysig.resource(neo.css, bundle),
      mysig.resource(script_asset, bundle),
    ],
    [h.div([], [empty_lustre()])],
  )
  |> element.to_document_string()
  |> bit_array.from_string()
}

// TODO remove an make remotes optional in sync
const origin = sync.Origin(http.Https, "", None)

fn build_intro(preview, bundle) {
  use script <- t.do(t.bundle("intro/intro", "run"))
  let package_asset = mysig.js("package", script)
  // TODO remove stdlib soon should be caught be seed
  use stdlib <- t.do(t.read("seed/eyg/std.json"))

  let assert Ok(expression) =
    decode.from_json({
      let assert Ok(stdlib) = bit_array.to_string(stdlib)
      stdlib
    })
  let std_hash = cid.for_expression(expression)
  use Nil <- t.do(t.log(std_hash))

  let content =
    list.flat_map(content.pages(), fn(page) {
      let #(name, content) = page
      let #(cache, _before, _public, _ref) =
        package.load_guide_from_content(content, sync.init(origin))
      let references = cache_to_references_files(cache)

      let page = #(
        "/packages/eyg/" <> name <> "/index.html",
        package_page(package_asset, bundle),
      )
      case preview {
        True -> [page, ..references]
        False -> references
      }
    })

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
        let page = #(
          "/packages/" <> group <> "/" <> name <> "/index.html",
          package_page(package_asset, bundle),
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

  t.done(
    [
      #("/_redirects", <<redirects:utf8>>),
      #("/packages/index.html", package_page(package_asset, bundle)),
      // 
      #(
        "/guide/" <> "intro" <> "/index.html",
        package_page(package_asset, bundle),
      ),
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
  doc(
    "Datalog notebook",
    "eyg.run",
    [
      stylesheet(mysig.tailwind_2_2_11),
      mysig.resource(layout.css, bundle),
      mysig.resource(neo.css, bundle),
      mysig.resource(mysig.js("datalog", script), bundle),
    ],
    [h.div([], [empty_lustre()])],
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

// This is not needed as intro is working
pub fn dep_file(expression) {
  let content = encode.to_json(expression)
  let bytes = <<content:utf8>>
  let cid = "h" <> cid.hash_code(content)
  #(cid, bytes)
}

// ordered graph of seedpages
pub fn dependency(group, name) {
  let file = name <> ".json"
  use bytes <- t.do(t.read("seed/" <> group <> "/" <> file))
  use src <- t.try(sync.decode_bytes(bytes))
  let #(ref, bytes) = dep_file(src)
  let path = "/references/" <> ref <> ".json"
  let file = #(path, bytes)
  // annotated.list_references(src)
  t.done(#(ref, file))
  // todo
}

pub fn build(bundle) {
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

// Remember to only add mysig at the top level
pub fn preview(args) {
  case args {
    ["home"] -> {
      let bundle = mysig.new_bundle("/assets")
      use v1_site <- t.do(build(bundle))
      use intro <- t.do(build_intro(True, bundle))

      t.done(
        [v1_site, intro, mysig.to_files(bundle)]
        |> list.flatten(),
      )
    }
    _ -> {
      let bundle = mysig.new_bundle("/assets")
      use v1_site <- t.do(build(bundle))
      use examine <- t.do(examine_page(bundle))
      use shell <- t.do(shell_page(bundle))
      use intro <- t.do(build_intro(True, bundle))
      // Note news puts pea image into assets without hashing
      use news <- t.do(news.build())
      use datalog <- t.do(build_datalog(bundle))

      let files =
        list.flatten([
          v1_site,
          [examine],
          [shell],
          intro,
          news,
          datalog,
          mysig.to_files(bundle),
        ])
      io.debug(listx.keys(files))
      t.done(files)
    }
  }
}
