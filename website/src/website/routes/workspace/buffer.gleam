import eyg/analysis/inference/levels_j/contextual as infer
import eyg/ir/cid
import gleam/list
import gleam/set
import morph/editable as e
import morph/projection as p
import website/components/snippet

pub type Buffer {
  Buffer(
    history: snippet.History,
    projection: p.Projection,
    analysis: infer.Analysis(List(Int)),
  )
}

fn history_new_entry(old, history) {
  let snippet.History(undo: undo, ..) = history
  let undo = [old, ..undo]
  snippet.History(undo: undo, redo: [])
}

pub fn undo(buffer, context) {
  let Buffer(history:, projection:, ..) = buffer

  case history.undo {
    [first, ..rest] -> {
      let redo = [projection, ..history.redo]
      let history = snippet.History(undo: rest, redo:)
      Ok(Buffer(history:, projection: first, analysis: analyse(first, context)))
    }
    [] -> Error(Nil)
  }
}

pub fn redo(buffer, context) {
  let Buffer(history:, projection:, ..) = buffer
  case history.redo {
    [first, ..rest] -> {
      let undo = [projection, ..history.undo]
      let history = snippet.History(undo:, redo: rest)
      Ok(Buffer(history:, projection: first, analysis: analyse(first, context)))
    }
    [] -> Error(Nil)
  }
}

pub fn cid(buffer) {
  let Buffer(projection:, ..) = buffer
  let source = e.to_annotated(p.rebuild(projection), [])
  let assert Ok(current) = cid.from_tree(source)
  current
}

fn analyse(projection, context: infer.Context) -> infer.Analysis(List(Int)) {
  let source = e.to_annotated(p.rebuild(projection), [])

  context
  |> infer.check(source)
}

pub fn empty(context) {
  from_projection(p.empty, context)
}

pub fn from_projection(projection, context) {
  Buffer(
    history: snippet.empty_history,
    projection:,
    analysis: analyse(projection, context),
  )
}

pub fn update_code(buffer, new, context) {
  let Buffer(history:, projection: old, ..) = buffer
  let history = history_new_entry(old, history)
  Buffer(history:, projection: new, analysis: analyse(new, context))
}

pub fn update_position(buffer, projection) {
  Buffer(..buffer, projection:)
}

pub fn add_references(buffer, new, context) {
  let Buffer(analysis:, ..) = buffer
  case list.any(infer.missing_references(analysis), set.contains(new, _)) {
    True -> Buffer(..buffer, analysis: analyse(buffer.projection, context))
    False -> buffer
  }
}

/// public for testing as a helper
pub fn target_type(buffer) {
  let Buffer(projection:, analysis:, ..) = buffer

  let path = p.path(projection)

  // multi pick is what we really want here
  infer.type_at(analysis, path)
}

pub fn target_scope(buffer) {
  let Buffer(projection:, analysis:, ..) = buffer

  let path = p.path(projection)

  // multi pick is what we really want here
  infer.scope_at(analysis, path)
}
