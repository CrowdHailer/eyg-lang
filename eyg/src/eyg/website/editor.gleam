import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eyg/website/page
import eygir/decode
import eygir/expression
import eygir/tree
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{Some}
import gleam/result
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/editable
import morph/lustre/components/key
import plinth/browser/file_system as fs
import plinth/browser/storage
import remote_data
import snag.{type Snag}

pub fn page(bundle) {
  page.app(Some("editor"), "eyg/website/editor", "client", bundle)
}

pub fn client() {
  let app = lustre.application(init, update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// When I visit the editor page with no project name it should load immediatly
// active: String
// dirty: Bool
// Ready(String,snippet,List(String,Module))
// othermodules: Loaded([])
// other_projects: Loading

// When I visit the editor with a key
// active: String
// 
// project = List(#(String, List(Module)))

pub type Module =
  #(String, expression.Expression)

pub type Project =
  #(String, List(Module))

pub type RemoteData(t) =
  remote_data.RemoteData(t, snag.Snag)

pub type CurrentProject {
  CurrentProject(
    dirty: Bool,
    module_name: String,
    edited_name: String,
    snippet: snippet.Snippet,
    other_modules: List(Module),
  )
}

pub type State {
  State(
    project_name: String,
    edited_name: String,
    project_content: RemoteData(CurrentProject),
    other_projects: RemoteData(List(Project)),
    cache: sync.Sync,
    // source: snippet.Snippet,
    display_help: Bool,
  )
}

// not ordered if using for active
// pub type NonEmpty(t) = #(t,List(t))

// TODO remove this just start with vacant
const blank = "{\"0\":\"z\",\"c\":\"\"}"

fn await_or(p, map, k) {
  use result <- promise.await(p)
  case result {
    Ok(value) -> k(value)
    Error(reason) -> promise.resolve(Error(map(reason)))
  }
}

fn get_projects_dir() {
  use storage <- await_or(promise.resolve(storage.get()), fn(_) {
    snag.new("unable to access the navigator.storage")
    |> snag.layer("accessing storage in browser")
  })
  use root <- await_or(storage.get_directory(storage), fn(r) {
    r
    |> snag.new
    |> snag.layer("accessing storage in browser")
  })
  use dir <- await_or(fs.get_directory_handle(root, "projects", True), fn(r) {
    r
    |> snag.new
    |> snag.layer("reading root file in OPFS")
  })
  promise.resolve(Ok(dir))
}

fn do_load() {
  use dir <- promise.try_await(get_projects_dir())
  use #(projects, _) <- await_or(fs.all_entries(dir), fn(r) {
    r
    |> snag.new
    |> snag.layer("reading directories in projects")
  })
  let projects = array.to_list(projects)
  use projects <- promise.await(
    promisex.sequential(projects, fn(dir) {
      let project = fs.name(dir)
      use modules <- await_or(promise.resolve(Ok([])), snag.layer(
        _,
        "accessing storage in browser",
      ))
      promise.resolve(Ok(#(project, modules)))
    }),
  )
  promise.resolve(Ok(projects))
}

fn load_workspace(d) {
  promise.map(do_load(), fn(result) { d(LoadedProjects(result)) })
  Nil
}

// TODO move to workspace
fn do_rename(old, new) {
  use dir <- promise.try_await(get_projects_dir())
  use dir <- await_or(fs.get_directory_handle(dir, new, True), fn(r) {
    r
    |> snag.new
    |> snag.layer("creating project dir")
  })
  promise.resolve(Ok(dir))
}

fn rename_project(old, new) {
  fn(d) {
    promise.map(do_rename(old, new), fn(result) { io.debug(result) })
    Nil
  }
}

pub fn init(_) {
  // let query or me
  // active project is blank go for ready
  let active_project = "me"
  let cache = sync.init(browser.get_origin())
  let assert Ok(source) = decode.from_json(blank)
  let source =
    editable.from_expression(source)
    |> editable.open_all
  let snippet = snippet.init(source, [], [], cache)
  let references = snippet.references(snippet)
  // let #(cache, tasks) = sync.fetch_missing(cache, references)

  let state =
    State(
      project_name: "",
      edited_name: "",
      project_content: remote_data.Success(
        CurrentProject(
          dirty: True,
          module_name: "main",
          edited_name: "main",
          snippet: snippet,
          other_modules: [],
        ),
      ),
      other_projects: remote_data.Loading,
      cache: cache,
      display_help: False,
    )
  #(
    state,
    // effect.from(browser.do_sync(tasks, SyncMessage))
    effect.from(load_workspace),
  )
}

pub type Message {
  LoadedProjects(Result(List(Result(Project, Snag)), Snag))
  UserEditedModuleName(String)
  UserBlurredModuleName
  UserSelectedProject(String)
  SnippetMessage(snippet.Message)
  SyncMessage(sync.Message)
}

fn dispatch_to_snippet(promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(SnippetMessage(message)) })
  })
}

fn dispatch_nothing(_promise) {
  effect.none()
}

// put all projects in memory as that's best way to lookup "/" workspace references
pub fn update(state: State, message) {
  case message {
    LoadedProjects(response) ->
      case response {
        Ok(projects) -> {
          let #(projects, _) = result.partition(projects)
          // TODO log errors
          let state =
            State(..state, other_projects: remote_data.Success(projects))
          // TODO load if waiting
          #(state, effect.none())
        }
        Error(reason) -> {
          let state =
            State(..state, other_projects: remote_data.Failure(reason))
          // TODO load if waiting
          #(state, effect.none())
        }
      }
    UserEditedModuleName(new) -> {
      let state = State(..state, edited_name: new)
      #(state, effect.none())
    }
    UserBlurredModuleName -> {
      #(
        state,
        effect.from(rename_project(state.project_name, state.edited_name)),
      )
    }
    UserSelectedProject(new) -> {
      let assert remote_data.Success(others) = state.other_projects
      let old = state.project_name
      case new {
        "" -> todo
        n if n == old -> #(state, effect.none())
        "+" -> todo
        _ -> {
          case list.key_find(others, new) {
            Ok(value) -> {
              io.debug(value)
              todo
            }
            Error(Nil) -> panic as "it shouldn't be possible to select this"
          }
        }
      }
    }
    SnippetMessage(message) -> {
      let assert remote_data.Success(project) = state.project_content
      let #(snippet, eff) = snippet.update(project.snippet, message)
      let State(display_help: display_help, ..) = state
      let #(display_help, snippet_effect) = case eff {
        snippet.Nothing -> #(display_help, effect.none())
        snippet.AwaitRunningEffect(p) -> #(
          display_help,
          dispatch_to_snippet(snippet.await_running_effect(p)),
        )
        snippet.FocusOnCode -> #(
          display_help,
          dispatch_nothing(snippet.focus_on_buffer()),
        )
        snippet.FocusOnInput -> #(
          display_help,
          dispatch_nothing(snippet.focus_on_input()),
        )
        snippet.ToggleHelp -> #(!display_help, effect.none())
        snippet.MoveAbove -> #(display_help, effect.none())
        snippet.MoveBelow -> #(display_help, effect.none())
        snippet.ReadFromClipboard -> #(
          display_help,
          dispatch_to_snippet(snippet.read_from_clipboard()),
        )
        snippet.WriteToClipboard(text) -> #(
          display_help,
          dispatch_to_snippet(snippet.write_to_clipboard(text)),
        )
        snippet.Conclude(_, _) -> #(display_help, effect.none())
      }
      let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      let project = CurrentProject(..project, dirty: True, snippet: snippet)
      let state =
        State(
          ..state,
          project_content: remote_data.Success(project),
          cache: cache,
        )
      #(state, effect.batch([snippet_effect, sync_effect]))
    }
    SyncMessage(message) -> {
      let cache = sync.task_finish(state.cache, message)
      let #(cache, tasks) = sync.fetch_all_missing(cache)
      todo as "sync message"
      // let snippet = snippet.set_references(state.source, cache)
      // #(
      //   State(..state, source: snippet, cache: cache),
      //   effect.from(browser.do_sync(tasks, SyncMessage)),
      // )
    }
  }
}

fn modal() {
  h.div([a.class("fixed inset-0 bg-gray-100 vstack")], [
    h.div([a.class("w-full vstack")], [
      h.div(
        [
          a.class(
            "w-full max-w-sm bg-white p-6 neo-shadow border-2 border-black",
          ),
        ],
        [element.text("Preparing ...")],
      ),
    ]),
  ])
}

fn project_selector(others) {
  let others = case others {
    remote_data.Success(others) ->
      list.map(others, fn(other) {
        let #(name, _modules) = other
        #(name, name, False)
      })
    remote_data.Loading -> []
    remote_data.Failure(snag) -> []
    remote_data.NotAsked -> panic as "we always ask"
  }
  let projects =
    // TODO shouldn't be here if has a choice
    list.append(others, [#("", "", True), #("+", "create new project", False)])

  h.select(
    [event.on_input(UserSelectedProject)],
    list.map(projects, fn(p) {
      let #(key, name, selected) = p
      h.option([a.value(key), a.selected(selected)], name)
    }),
  )
}

pub fn render(state: State) {
  h.div([a.class("flex flex-col h-screen")], case state.project_content {
    remote_data.Success(CurrentProject(snippet: s, ..)) -> [
      h.div([a.class("w-full py-2 px-6 text-xl text-gray-500")], [
        h.a([a.href("/"), a.class("font-bold")], [element.text("EYG")]),
        h.span([a.class("")], [element.text(" - Editor")]),
      ]),
      h.div([a.class("w-full py-2 px-4 bg-gray-500")], [
        h.input([
          a.value(state.edited_name),
          event.on_input(UserEditedModuleName),
          event.on_blur(UserBlurredModuleName),
        ]),
        case state.project_name {
          "" -> element.text("give it a name to save")
          _ -> element.none()
        },
        project_selector(state.other_projects),
        h.span([], [element.text("unpublished")]),
      ]),
      h.div([a.class("grid grid-cols-2 h-full")], [
        h.div(
          [
            a.class(
              "flex-grow flex flex-col justify-center w-full max-w-3xl font-mono px-6",
            ),
          ],
          [snippet.render_editor(s)],
        ),
        h.div([a.class("leading-none p-4 text-gray-500")], [
          h.pre(
            [],
            list.map(
              tree.lines(editable.to_expression(snippet.source(s))),
              fn(x) { h.div([], [h.pre([], [element.text(x)])]) },
            ),
          ),
        ]),
      ])
        |> element.map(SnippetMessage),
      case state.display_help {
        True ->
          h.div(
            [
              a.class(
                "bottom-0 fixed flex flex-col justify-around mr-10 right-0 top-0",
              ),
            ],
            [h.div([a.class("bg-indigo-100 p-4 rounded-2xl")], [key.render()])],
          )
        False -> element.none()
      },
    ]
    _ -> [modal()]
  })
}
