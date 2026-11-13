//// The Glasshouse debugger, recorded sessions explored one moment at a time.
////
//// A moment is an effect, a prompt, a generation or a tool result.
//// The files known at a moment are those known after the last effect before it.
//// Several traces can be open, a recorded session and its evaluated variants, to compare them.

import glasshouse/archive.{type Archive}
import glasshouse/cohort
import glasshouse/rerun
import glasshouse/run
import glasshouse/session.{type Generation}
import glasshouse/timeline.{type Frame, type Node}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import plinth/browser/file.{type File}

pub type Demo {
  Demo(name: String, slug: String)
}

/// The demo session and the variants evaluated from it, served with the site.
pub const demos = [
  Demo("Recorded session", "session"),
  Demo("same", "same"),
  Demo("with totals", "with-totals"),
  Demo("blog only", "blog-only"),
  Demo("check the website", "check-the-website"),
]

pub const sandbox_demos = [
  Demo("Sealed session", "sandbox"),
  Demo("Unchanged fork", "sandbox-same"),
  Demo("Changed skill", "sandbox-totals"),
  Demo("Changed prompt", "sandbox-blog"),
  Demo("Refused host", "sandbox-stopped"),
]

pub fn demo_path(demo: Demo) -> String {
  "/glasshouse/demo/" <> demo.slug <> ".json"
}

pub type Moment {
  Effect(frame: Frame)
  Prompted(event: Int, at: Int, text: String)
  Completed(event: Int, generation: Generation)
  Returned(event: Int, at: Int, call_id: String, text: String)
}

pub type Trace {
  Trace(
    name: String,
    slug: String,
    archive: Archive,
    moments: List(Moment),
    replay: Option(List(rerun.Report)),
  )
}

pub type Panel {
  Step
  Replay
  Compare
}

pub type Model {
  Model(
    traces: List(Trace),
    /// Demo traces still loading.
    loading: List(Demo),
    demo_order: List(Demo),
    /// The slug of the trace being explored, the first trace when none was chosen.
    active: Option(String),
    moment: Int,
    file: Option(String),
    panel: Panel,
    error: Option(String),
    /// The trace and moment asked for in the URL, applied once it loads.
    wanted: Option(#(String, Int)),
  )
}

pub type Message {
  ArchiveFetched(demo: Demo, result: Result(String, String))
  ArchiveUploaded(name: String, result: Result(String, String))
  UserSelectedTrace(index: Int)
  UserSelectedMoment(index: Int)
  UserMovedScrubber(value: String)
  UserPressedKey(key: String)
  UserSelectedFile(path: String)
  UserClosedFile
  UserOpenedPanel(panel: Panel)
  UserClickedReplay
  UserClickedDownload
  UserChoseFile(file: File)
}

/// Work for the browser, the results come back as messages.
pub type Action {
  FetchArchive(demo: Demo)
  ReadUpload(file: File)
  DownloadArchive(name: String, text: String)
}

/// Start loading the demo traces, the query can pick a trace and moment, i.e. `trace=with-totals&step=12`.
pub fn init(query: String) -> #(Model, List(Action)) {
  let params = uri.parse_query(query) |> result.unwrap([])
  let selected = case list.key_find(params, "demo") {
    Ok("sandbox") -> sandbox_demos
    _ -> demos
  }
  let wanted = case list.key_find(params, "trace") {
    Ok(slug) -> {
      let step =
        list.key_find(params, "step")
        |> result.try(int.parse)
        |> result.unwrap(0)
      Some(#(slug, step))
    }
    Error(Nil) -> None
  }
  let model =
    Model(
      traces: [],
      loading: selected,
      demo_order: selected,
      active: None,
      moment: 0,
      file: None,
      panel: Step,
      error: None,
      wanted:,
    )
  #(model, list.map(selected, FetchArchive))
}

pub fn update(model: Model, message: Message) -> #(Model, List(Action)) {
  case message {
    ArchiveFetched(demo:, result:) -> {
      let model =
        Model(..model, loading: list.filter(model.loading, fn(d) { d != demo }))
      case result |> result.try(archive.from_string) {
        Ok(archive) -> #(add(model, demo.name, demo.slug, archive), [])
        Error(reason) -> #(
          Model(..model, error: Some(demo.name <> ": " <> reason)),
          [],
        )
      }
    }
    ArchiveUploaded(name:, result:) ->
      case result |> result.try(archive.from_string) {
        Ok(archive) -> {
          let model = add(model, name, name, archive)
          #(
            Model(
              ..model,
              active: Some(name),
              moment: 0,
              file: None,
              panel: Step,
              error: None,
            ),
            [],
          )
        }
        Error(reason) -> #(
          Model(..model, error: Some(name <> ": " <> reason)),
          [],
        )
      }
    UserSelectedTrace(index:) -> #(select_trace(model, index), [])
    UserSelectedMoment(index:) -> #(go_to(model, index), [])
    UserMovedScrubber(value:) ->
      case int.parse(value) {
        Ok(index) -> #(go_to(model, index), [])
        Error(Nil) -> #(model, [])
      }
    UserPressedKey(key:) ->
      case key {
        "ArrowRight" | "ArrowDown" | "j" -> #(
          go_to(model, model.moment + 1),
          [],
        )
        "ArrowLeft" | "ArrowUp" | "k" -> #(go_to(model, model.moment - 1), [])
        "Home" -> #(go_to(model, 0), [])
        "End" -> #(go_to(model, moment_count(model) - 1), [])
        "Escape" -> #(Model(..model, file: None), [])
        _ -> #(model, [])
      }
    UserSelectedFile(path:) -> #(Model(..model, file: Some(path)), [])
    UserClosedFile -> #(Model(..model, file: None), [])
    UserOpenedPanel(panel:) -> #(Model(..model, panel:), [])
    UserClickedReplay -> #(replay(model), [])
    UserClickedDownload ->
      case active(model) {
        Ok(trace) -> #(model, [
          DownloadArchive(
            trace.archive.session.id <> ".json",
            archive.to_string(trace.archive),
          ),
        ])
        Error(Nil) -> #(model, [])
      }
    UserChoseFile(file:) -> #(model, [ReadUpload(file)])
  }
}

fn add(model: Model, name, slug, archive: Archive) -> Model {
  let trace =
    Trace(
      name:,
      slug:,
      archive:,
      moments: moments(archive.session, archive.store),
      replay: None,
    )
  // Demo traces keep their order however they arrive, uploads go last.
  let order = fn(trace: Trace) {
    list.index_fold(
      model.demo_order,
      list.length(model.demo_order),
      fn(found, demo, i) {
        case demo.slug == trace.slug {
          True -> i
          False -> found
        }
      },
    )
  }
  let traces =
    model.traces
    |> list.filter(fn(t) { t.slug != slug })
    |> list.append([trace])
    |> list.sort(fn(a, b) { int.compare(order(a), order(b)) })
  let model = Model(..model, traces:)
  case model.wanted {
    Some(#(wanted, step)) if wanted == slug ->
      go_to(Model(..model, active: Some(slug), wanted: None), step)
    _ -> model
  }
}

fn select_trace(model: Model, index: Int) -> Model {
  case list.drop(model.traces, index) {
    [trace, ..] -> {
      let model = Model(..model, active: Some(trace.slug), file: None)
      // Stay at the same moment when the other trace is as long, variants line up with the session.
      go_to(model, model.moment)
    }
    [] -> model
  }
}

fn go_to(model: Model, index: Int) -> Model {
  let count = moment_count(model)
  let index = int.clamp(index, 0, int.max(count - 1, 0))
  Model(..model, moment: index)
}

pub fn active(model: Model) -> Result(Trace, Nil) {
  let chosen = case model.active {
    Some(slug) -> list.find(model.traces, fn(t) { t.slug == slug })
    None -> Error(Nil)
  }
  result.lazy_or(chosen, fn() { list.first(model.traces) })
}

/// The position of the active trace in the open traces.
pub fn active_index(model: Model) -> Int {
  case active(model) {
    Ok(trace) ->
      list.index_fold(model.traces, 0, fn(found, t, i) {
        case t.slug == trace.slug {
          True -> i
          False -> found
        }
      })
    Error(Nil) -> 0
  }
}

fn moment_count(model: Model) -> Int {
  case active(model) {
    Ok(trace) -> list.length(trace.moments)
    Error(Nil) -> 0
  }
}

pub fn current(model: Model) -> Result(#(Trace, Moment), Nil) {
  use trace <- result.try(active(model))
  use moment <- result.map(list.drop(trace.moments, model.moment) |> list.first)
  #(trace, moment)
}

fn replay(model: Model) -> Model {
  let current = active(model) |> result.map(fn(t) { t.slug })
  let traces =
    list.map(model.traces, fn(trace) {
      case Ok(trace.slug) == current {
        True -> {
          let reports =
            rerun.session(trace.archive.session, trace.archive.store)
          Trace(..trace, replay: Some(reports))
        }
        False -> trace
      }
    })
  Model(..model, traces:, panel: Replay)
}

/// Every moment of a session in order.
pub fn moments(session: session.Session, store) -> List(Moment) {
  let frames = timeline.frames(session, store)
  list.index_map(session.events, fn(event, i) {
    case event {
      session.Execution(..) ->
        list.filter_map(frames, fn(frame) {
          case frame.event == i {
            True -> Ok(Effect(frame))
            False -> Error(Nil)
          }
        })
      session.Prompt(at:, text:) -> [Prompted(i, at, text)]
      session.Generated(generation:) -> [Completed(i, generation)]
      session.ToolResult(at:, call_id:, text:) -> [
        Returned(i, at, call_id, text),
      ]
    }
  })
  |> list.flatten
}

/// The files known at the current moment.
pub fn files(model: Model) -> Dict(String, Node) {
  case active(model) {
    Ok(trace) ->
      list.take(trace.moments, model.moment + 1)
      |> list.fold(dict.new(), fn(files, moment) {
        case moment {
          Effect(frame) -> frame.files
          _ -> files
        }
      })
    Error(Nil) -> dict.new()
  }
}

/// The frame of the current moment, if it is an effect.
pub fn frame(model: Model) -> Option(Frame) {
  case current(model) {
    Ok(#(_, Effect(frame))) -> Some(frame)
    _ -> None
  }
}

/// The path changed at the current moment.
pub fn changed(model: Model) -> Option(String) {
  case frame(model) {
    Some(timeline.Frame(change: Some(change), ..)) ->
      case timeline.is_modification(change) {
        True -> Some(timeline.change_path(change))
        False -> None
      }
    _ -> None
  }
}

/// Paths changed at any moment up to the current one.
pub fn written(model: Model) -> List(String) {
  case active(model) {
    Ok(trace) ->
      list.take(trace.moments, model.moment + 1)
      |> list.filter_map(fn(moment) {
        case moment {
          Effect(timeline.Frame(change: Some(change), ..)) ->
            case timeline.is_modification(change) {
              True -> Ok(timeline.change_path(change))
              False -> Error(Nil)
            }
          _ -> Error(Nil)
        }
      })
      |> list.unique
    Error(Nil) -> []
  }
}

/// Summaries of every open trace, the first is the baseline.
pub fn cohort(model: Model) -> List(cohort.Summary) {
  list.map(model.traces, fn(trace) {
    cohort.summarize(trace.name, trace.archive.session, trace.archive.store)
  })
}

/// The index of the first moment of each event, to jump to a generation or tool call.
pub fn first_moment(trace: Trace, event: Int) -> Option(Int) {
  list.index_fold(trace.moments, None, fn(found, moment, i) {
    case found, event_of(moment) == event {
      None, True -> Some(i)
      _, _ -> found
    }
  })
}

pub fn event_of(moment: Moment) -> Int {
  case moment {
    Effect(frame) -> frame.event
    Prompted(event:, ..) | Completed(event:, ..) | Returned(event:, ..) -> event
  }
}

/// A short label for the run an effect belongs to.
pub fn run_label(trace: Trace, frame: Frame) -> String {
  let runs = session.runs(trace.archive.session)
  case list.find(runs, fn(recorded) { recorded.id == frame.run }) {
    Ok(recorded) ->
      case recorded.kind {
        run.Config -> "configuration"
        run.Tool(call_id) -> "tool call " <> call_id
        run.Script(..) -> "script"
        run.Block -> "run"
        run.Cell -> "shell input " <> recorded.id
      }
    Error(Nil) -> frame.run
  }
}

/// The name of a file relative to the session's directory.
pub fn display_path(trace: Trace, path: String) -> String {
  timeline.relative(path, trace.archive.session.cwd)
}
