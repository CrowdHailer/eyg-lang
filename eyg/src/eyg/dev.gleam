import eyg/package
import eyg/sync/cid
import eyg/sync/sync
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
import midas/task as t

// import intro/content

fn build_drafting() {
  use script <- t.do(t.bundle("drafting/app", "run"))
  let files = [#("/drafting.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/drafting/index.html"))
  t.done([#("/drafting/index.html", index), ..files])
}

fn build_examine() {
  use script <- t.do(t.bundle("examine/app", "run"))
  let files = [#("/examine.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/examine/index.html"))
  t.done([#("/examine/index.html", index), ..files])
}

fn build_spotless() {
  use script <- t.do(t.bundle("spotless/app", "run"))
  let files = [#("/spotless.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/spotless/index.html"))
  use prompt <- t.do(t.read("saved/prompt.json"))

  t.done([#("/terminal/index.html", index), #("/prompt.json", prompt), ..files])
}

fn build_shell() {
  use script <- t.do(t.bundle("eyg/shell/app", "run"))
  let files = [#("/shell/index.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/eyg/shell/index.html"))

  t.done([#("/shell/index.html", index), ..files])
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

// TODO remove an make remotes optional in sync
const origin = sync.Origin(http.Https, "", None)

fn build_intro(preview) {
  use script <- t.do(t.bundle("intro/intro", "run"))

  use index <- t.do(t.read("src/intro/index.html"))
  use zip_src <- t.do(t.read("vendor/zip.min.js"))
  use style <- t.do(t.read("layout2.css"))
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

      let page = #("/packages/eyg/" <> name <> "/index.html", index)
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
          index,
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
      #("/vendor/zip.min.js", zip_src),
      #("/packages/index.html", index),
      #("/packages/index.js", <<script:utf8>>),
      #("/packages/index.css", style),
      // 
      #("/guide/" <> "intro" <> "/index.html", index),
      #("/references/" <> std_hash <> ".json", stdlib),
    ]
    |> list.append(packages)
    |> list.append(content)
    // make unique by key
    |> dict.from_list()
    |> dict.to_list(),
  )
}

pub fn preview(args) {
  case args {
    ["intro"] -> {
      use files <- t.do(build_intro(True))

      t.done(files)
    }
    ["news"] -> {
      news.build()
    }
    _ -> {
      use drafting <- t.do(build_drafting())
      use examine <- t.do(build_examine())
      use spotless <- t.do(build_spotless())
      use shell <- t.do(build_shell())
      use intro <- t.do(build_intro(True))
      use news <- t.do(news.build())

      let files =
        list.flatten([drafting, examine, spotless, shell, intro, news])
      t.done(files)
    }
  }
}
