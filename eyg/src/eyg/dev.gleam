import eyg/package
import eyg/sync/cid
import eyg/sync/sync
import eyg/website/components
import eyg/website/documentation
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

fn drafting_page(bundle) {
  use script <- t.do(t.bundle("drafting/app", "run"))
  let content =
    doc(
      "Eyg - drafting",
      "eyg.run",
      [
        stylesheet(mysig.tailwind_2_2_11),
        mysig.resource(layout.css, bundle),
        mysig.resource(neo.css, bundle),
        mysig.resource(mysig.js("drafting", script), bundle),
      ],
      [h.div([], [empty_lustre()])],
    )
    |> element.to_document_string()
    |> bit_array.from_string()
  t.done(#("/drafting/index.html", content))
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

fn spotless_page(bundle) {
  use script <- t.do(t.bundle("spotless/app", "run"))
  let content =
    doc(
      "Spotless",
      "eyg.run",
      [
        stylesheet(mysig.tailwind_2_2_11),
        mysig.resource(layout.css, bundle),
        mysig.resource(neo.css, bundle),
        h.script([a.src("/vendor/zip.js")], ""),
        mysig.resource(mysig.js("examine", script), bundle),
      ],
      [h.div([], [empty_lustre()])],
    )
    |> element.to_document_string()
    |> bit_array.from_string()
  t.done(#("/terminal/index.html", content))
}

fn build_spotless(bundle) {
  use page <- t.do(spotless_page(bundle))
  use prompt <- t.do(t.read("saved/prompt.json"))

  t.done([page, #("/prompt.json", prompt)])
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
        h.script([a.src("/vendor/zip.min.js")], ""),
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
  use zip_src <- t.do(t.read("vendor/zip.min.js"))
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
      #("/vendor/zip.min.js", zip_src),
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

pub fn preview(args) {
  case args {
    ["home"] -> {
      let bundle = mysig.new_bundle("/assets")
      use documentation <- t.do(documentation.page(bundle))
      // use home <- t.do(home.page(bundle))

      t.done([
        #("/home/index.html", root_page("", home_page(), bundle)),
        #("/documentation/index.html", documentation),
        // #("/index.html", home),
        ..mysig.to_files(bundle)
      ])
    }
    _ -> {
      let bundle = mysig.new_bundle("/assets")
      use drafting <- t.do(drafting_page(bundle))
      use examine <- t.do(examine_page(bundle))
      use spotless <- t.do(build_spotless(bundle))
      use shell <- t.do(shell_page(bundle))
      use intro <- t.do(build_intro(True, bundle))
      use news <- t.do(news.build())
      use datalog <- t.do(build_datalog(bundle))

      let files =
        list.flatten([
          [drafting],
          [examine],
          spotless,
          [shell],
          intro,
          news,
          datalog,
          mysig.to_files(bundle),
        ])
      t.done(files)
    }
  }
}

import lustre/element.{text} as _
import lustre/element/svg

fn lump() {
  h.div([a.class("vstack wrap")], [
    h.header([a.class("yellow-gradient drop w-full overflow-hidden")], [
      h.div([a.class("hstack max-w-3xl mx-auto")], [
        h.div([a.class("expand leading-relaxed")], [
          h.div([a.class("text-pink-4 border-l-8 border-white pl-2 -ml-2")], [
            text("There is no "),
            h.strong([a.class("font-bold")], [text("syntax")]),
            text(
              "...
            ",
            ),
          ]),
          h.ul([a.class("underline text-black pl-2")], [
            h.li([], [h.a([a.href("/documentation")], [text("Documentation")])]),
            h.li([], [
              h.a([a.href("/documentation/effects")], [text("Effects")]),
            ]),
          ]),
        ]),
        h.div(
          [
            a.class(
              "border-2 border-black bg-purple-3 my-10 rounded-xl neo-shadow -mr-20",
            ),
          ],
          [
            h.div([a.class("ml-5 mr-24")], [
              h.h3([a.class("font-bold text-white")], [text("Eat Your Greens")]),
              h.h1([a.class("text-4xl sm:text-6xl font-bold")], [text("EYG")]),
            ]),
          ],
        ),
      ]),
      h.div([a.class("max-w-3xl mx-auto px-4 my-4 text-xl hstack wrap")], [
        h.div([], [
          h.p([a.class("")], [
            text("Create programs that run "),
            h.strong([], [text("everywhere")]),
          ]),
          h.p([a.class("")], [
            text("and "),
            h.strong([], [text("never")]),
            text("crash."),
          ]),
        ]),
        h.div([a.class("expand")], []),
        h.a([a.href("https://github.com/crowdhailer/eyg-lang"), a.class("")], [
          svg.svg(
            [
              a.attribute("xmlns", "http://www.w3.org/2000/svg"),
              a.attribute("viewBox", "0 0 98 96"),
              a.class("w-8 flex-no-shrink fill-current text-gray-700"),
            ],
            [
              svg.path([
                a.attribute(
                  "d",
                  "M48.854 0C21.839 0 0 22 0 49.217c0 21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052-.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448-3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427-5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897-.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 22 75.788 0 48.854 0z",
                ),
                a.attribute("clip-rule", "evenodd"),
                a.attribute("fill-rule", "evenodd"),
              ]),
            ],
          ),
        ]),
      ]),
    ]),
    h.div([a.class("expand w-full blue-gradient drop")], [
      h.div([a.class("max-w-3xl w-full mx-auto")], [
        h.div(
          [
            a.class(
              "wrap bg-white neo-shadow border-black border-2 mb-2 rounded-xl overflow-hidden",
            ),
          ],
          [
            h.pre(
              [
                a.attribute("spellcheck", "false"),
                a.class("overflow-auto outline-none my-1 px-4"),
                a.attribute("data-easel", "#hello"),
              ],
              [],
            ),
            h.div([a.class("bg-purple-1 px-4 font-mono font-bold")], [
              text(
                "click to edit & run
            ",
              ),
            ]),
          ],
        ),
      ]),
      h.div([a.class("max-w-3xl mx-auto px-4 text-xl")], [
        h.p([], [
          text(
            "Read the section on
            ",
          ),
          h.strong([], [
            h.a([a.href("#structural-editing")], [text("Structural editing")]),
          ]),
          text(
            "to learn how to edit the code.
          ",
          ),
        ]),
        h.h2([a.id("run-everywhere"), a.class("text-3xl")], [
          text("Run everywhere"),
        ]),
        h.p([], [
          text(
            "Eyg programs can be run everywhere, on client and server as well as
            build scripts and embedded. The Eyg language makes no assumptions
            about the runtime or platform a program will be run on. All
            requirements a program has to the outside world are explicit and
            tracked using effect types.
          ",
          ),
        ]),
        h.h2([a.class("text-3xl")], [text("Universal apps")]),
        h.p([], [
          text(
            "Every expression of an Eyg program is serializable and can be
            transmitted. The ability to send functions over the wire allow the
            full lifecycle of an application to exist in a single program.
          ",
          ),
        ]),
      ]),
      h.div([a.class("max-w-3xl mx-auto px-4 text-xl")], [
        h.h2([a.class("text-3xl")], [text("Syntax is optional")]),
        h.p([], [
          text(
            "There are less than 20 different kinds of node in Eyg's abstract
            syntax tree (AST). Unusually for a language this data structure is
            canonical format of an Eyg program, Syntaxes are optional.
          ",
          ),
        ]),
        h.p([], [
          text(
            "A simple AST makes implementing new platforms for Eyg very easy.
          ",
          ),
        ]),
        h.div([a.class("py-4")], []),
      ]),
    ]),
    h.div([a.class("expand w-full purple-gradient")], [
      h.div([a.class("max-w-3xl w-full mx-auto")], [
        h.div(
          [
            a.class(
              "wrap bg-white neo-shadow border-black border-2 mb-2 rounded-xl overflow-hidden",
            ),
          ],
          [
            h.pre(
              [
                a.attribute("spellcheck", "false"),
                a.class("overflow-auto outline-none my-1 px-4"),
                a.attribute("data-easel", "#infer"),
              ],
              [],
            ),
            h.div([a.class("bg-purple-1 px-4 font-mono font-bold")], [
              text(
                "click to edit & run
            ",
              ),
            ]),
          ],
        ),
      ]),
      h.div([a.class("max-w-3xl mx-auto px-4 text-xl")], [
        h.h2([a.id("never-crash"), a.class("text-3xl")], [text("Never crash")]),
        h.p([], [
          text(
            "Guarantee that a program will never crash by running the Eyg type
            checker. The Eyg type checker covers all features of the language,
            are no zero division errors or missing cases.
          ",
          ),
        ]),
        h.p([], [
          text("Holes are part of the language all features are suggestable"),
        ]),
      ]),
      h.div([a.class("max-w-3xl w-full mx-auto")], [
        h.div(
          [
            a.class(
              "wrap bg-white neo-shadow border-black border-2 mb-2 rounded-xl overflow-hidden",
            ),
          ],
          [
            h.pre(
              [
                a.attribute("spellcheck", "false"),
                a.class("overflow-auto outline-none my-1 px-4"),
                a.attribute("data-easel", "#holes"),
              ],
              [],
            ),
            h.div([a.class("bg-purple-1 px-4 font-mono font-bold")], [
              text(
                "click to edit & run
            ",
              ),
            ]),
          ],
        ),
      ]),
      h.div([a.class("max-w-3xl mx-auto px-4 text-xl")], [
        h.h2([a.class("text-3xl")], [text("No type declaration")]),
      ]),
      h.div([a.class("max-w-3xl w-full mx-auto")], [
        h.div(
          [
            a.class(
              "wrap bg-white neo-shadow border-black border-2 mb-2 rounded-xl overflow-hidden",
            ),
          ],
          [
            h.pre(
              [
                a.attribute("spellcheck", "false"),
                a.class("overflow-auto outline-none my-1 px-4"),
                a.attribute("data-easel", "#match"),
              ],
              [],
            ),
            h.div([a.class("bg-purple-1 px-4 font-mono font-bold")], [
              text(
                "click to edit & run
            ",
              ),
            ]),
          ],
        ),
      ]),
      h.div([a.class("max-w-3xl mx-auto px-4 text-xl")], [
        h.h2([a.class("text-3xl")], [text("Effect types")]),
        h.p([a.class("max-w-lg")], [
          text(
            "All side effects are captured in the type system
          ",
          ),
        ]),
        h.h2([a.id("structural-editing"), a.class("text-3xl")], [
          text("Structural editor"),
        ]),
        h.p([], [
          text(
            "Editing with the Eyg code editor is always in
            ",
          ),
          h.strong([], [text("command")]),
          text("or "),
          h.strong([], [text("insert")]),
          text(
            "mode.
          ",
          ),
        ]),
        h.h3([a.class("font-bold mt-2")], [text("Insert mode")]),
        h.p([], [
          text(
            "Insert mode allows you to edit all variables, strings, numbers and
            label in the program. To enter insert mode press
            ",
          ),
          h.strong(
            [
              a.class(
                "bg-gray-100 border border-black rounded w-6 inline-block text-center",
              ),
            ],
            [text("i")],
          ),
          text(
            ". To exit press
            ",
          ),
          h.strong(
            [
              a.class(
                "bg-gray-100 border border-black rounded w-10 inline-block text-center",
              ),
            ],
            [text("Esc")],
          ),
        ]),
        h.h3([a.class("font-bold mt-2")], [text("Command mode")]),
        h.p([], [
          text(
            "The more powerful is command mode and allows you to create new
            sections of program faster. In this mode each key press will take
            the currently targeted element. The target is the item under your
            cursor and transform it. ",
          ),
          h.em([], [text("This list is incomplete.")]),
        ]),
        h.ul([a.class("my-2")], [
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("w")],
            ),
            text(
              "wrap the current expression as the arguments to a function call
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("e")],
            ),
            text(
              "assign the current expression to a variable
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("r")],
            ),
            text(
              "Extend a record or create a new one
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("t")],
            ),
            text(
              "Tag the current expression
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("y")],
            ),
            text(
              "Copy to clip board current selection
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("e")],
            ),
            text(
              "Replace current selection with contents of clipboard
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("o")],
            ),
            text(
              "Overwrite a field in a record
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("i")],
            ),
            text(
              "enter insert mode
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("p")],
            ),
            text(
              "Perform an effect with the current expression
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("s")],
            ),
            text(
              "Insert a string in place of the current expression
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("d")],
            ),
            text(
              "delete the current expression
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("f")],
            ),
            text(
              "wrap the current expression as the body of a function
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("g")],
            ),
            text(
              "select a record field from the expression
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("h")],
            ),
            text(
              "Wrap the current expression as an effect handler
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("x")],
            ),
            text(
              "wrap the current expression as the element of list
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [],
            ),
            text(
              "Add another list element at the position of the cursor
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("z")],
            ),
            text(
              "undo the last transformation
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("Z")],
            ),
            text(
              "redo any undone transform
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("c")],
            ),
            text(
              "call the current expression as a function
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("n")],
            ),
            text(
              "Insert a number in place of the current expression
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("m")],
            ),
            text(
              "Insert a match statement with the current expression as first
              branch
            ",
            ),
          ]),
          h.li([], [
            h.strong(
              [
                a.class(
                  "bg-gray-100 border border-black rounded w-6 inline-block text-center",
                ),
              ],
              [text("M")],
            ),
            text(
              "Close the current match expression
            ",
            ),
          ]),
        ]),
        h.p([], []),
        h.h2([a.class("text-3xl")], [text("Features")]),
        text(
          "All the features
          ",
        ),
        h.p([], [text("Pages to learn about the implementation")]),
      ]),
    ]),
    h.footer([a.class("yellow-gradient w-full")], [
      h.div([a.class("hstack max-w-3xl mx-auto")], [
        h.span([a.class("text-3xl")], [text("EYG")]),
        h.span([a.class("expand")], []),
        h.span([], [
          h.a(
            [
              a.href("https://github.com/CrowdHailer/eyg-lang"),
              a.class("font-bold"),
            ],
            [text("github.com")],
          ),
        ]),
      ]),
    ]),
  ])
}

fn home_page() {
  [
    h.div([a.class("")], [
      h.header([a.class("max-w-6xl mx-auto p-10")], [
        h.h1([], [
          h.span([a.class("text-2xl")], [element.text("EYG")]),
          element.text(" - a better way to program"),
        ]),
      ]),
    ]),
    h.div([a.class("bg-gradient-to-b from-green-100 to-white")], [
      h.div([a.class("hstack w-full max-w-6xl mx-auto p-10")], [
        h.div([a.class("expand cover w-full p-1")], [
          h.div([], [element.text("lorem")]),
          h.div([a.class("py-2")], [
            components.card([
              h.div([a.class("bg-green-200 p-2")], [element.text("card")]),
              h.div([a.class("p-2")], [element.text("foo")]),
            ]),
          ]),
          h.div([a.class("py-2")], [
            components.card([
              h.div([a.class("bg-green-200 p-2")], [element.text("card")]),
              h.div([a.class("p-2")], [element.text("foo")]),
            ]),
          ]),
          h.div([a.class("py-2")], [
            components.card([
              h.div([a.class("bg-green-200 p-2")], [element.text("card")]),
              h.div([a.class("p-2")], [element.text("foo")]),
            ]),
          ]),
        ]),
        h.div([a.class("expand cover w-full p-1")], [
          h.div([], [element.text("ipsum")]),
          h.div(
            [a.class("bg-white cover p-2 rounded-lg shadow-lg sticky top-10")],
            [element.text("output program")],
          ),
        ]),
      ]),
    ]),
    element.text("hello"),
    lump(),
  ]
}

fn root_page(name, body, bundle) {
  doc(
    "EYG - " <> name,
    "eyg.run",
    [
      stylesheet(mysig.tailwind_2_2_11),
      mysig.resource(layout.css, bundle),
      mysig.resource(neo.css, bundle),
    ],
    body,
  )
  |> element.to_document_string()
  |> bit_array.from_string()
}
// can't move easil page without updating bundle process
// fn easil_page(bundle) {
//   let content =
//     [
//       h.html([], [
//         h.head([], []),
//         h.body([a.class("green-gradient")], [
//           h.div(
//             [
//               a.class(
//                 "flex flex-col max-h-screen min-h-screen max-w-5xl mx-auto p-2",
//               ),
//             ],
//             [
//               h.div(
//                 [
//                   a.attribute("data-ready", "editor"),
//                   a.class(
//                     "flex-1 vstack wrap bg-white neo-shadow border-black border-2 mb-2 mr-2 rounded-xl overflow-hidden",
//                   ),
//                 ],
//                 [],
//               ),
//             ],
//           ),
//         ]),
//       ]),
//     ]
//     |> root_page("easil", _, bundle)
// }
