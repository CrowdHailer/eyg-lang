import eyg/analysis/inference/levels_j/contextual as infer
import eyg/ir/cid
import eyg/ir/promise
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/set
import morph/action
import morph/editable as e
import morph/navigation
import morph/projection as p
import morph/transformation as t
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

/// Need to repass in context as it might have changed, i.e. new references could have loaded.
pub fn undo(buffer) {
  let Buffer(history:, projection:, ..) = buffer

  case history.undo {
    [first, ..rest] -> {
      let redo = [projection, ..history.redo]
      let history = snippet.History(undo: rest, redo:)
      Ok(fn(context) {
        Buffer(history:, projection: first, analysis: analyse(first, context))
      })
    }
    [] -> Error(Nil)
  }
}

pub fn redo(buffer) {
  let Buffer(history:, projection:, ..) = buffer
  case history.redo {
    [first, ..rest] -> {
      let undo = [projection, ..history.undo]
      let history = snippet.History(undo:, redo: rest)
      Ok(fn(context) {
        Buffer(history:, projection: first, analysis: analyse(first, context))
      })
    }
    [] -> Error(Nil)
  }
}

pub fn cid(buffer) {
  let Buffer(projection:, ..) = buffer
  let source = e.to_annotated(p.rebuild(projection), [])
  // let assert Ok(current) = cid.from_tree(source)
  use result <- promise.map(cid.from_tree_async(source))
  let assert Ok(cid) = result
  cid
}

fn analyse(projection, context: infer.Context) -> infer.Analysis(List(Int)) {
  let source = e.to_annotated(p.rebuild(projection), [])

  context
  |> infer.check(source)
}

pub fn empty(context) {
  from_projection(p.empty, context)
}

pub fn from_source(source, context) {
  source
  |> e.from_annotated
  |> p.all()
  |> from_projection(context)
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
  infer.type_at(analysis, path)
}

pub fn target_scope(buffer) {
  let Buffer(projection:, analysis:, ..) = buffer
  let path = p.path(projection)
  infer.scope_at(analysis, path)
}

pub fn target_arity(buffer) {
  let Buffer(projection:, analysis:, ..) = buffer
  let path = p.path(projection)
  infer.arity_at(analysis, path)
}

// ------------------------- Navigations
fn navigate(buffer: Buffer, navigation) {
  use projection <- result.map(navigation(buffer.projection))
  update_position(buffer, projection)
}

fn always_navigate(state, navigation) {
  navigate(state, fn(p) { Ok(navigation(p)) })
}

pub fn next(state) {
  always_navigate(state, navigation.next)
}

pub fn previous(state) {
  always_navigate(state, navigation.previous)
}

pub fn up(state) {
  navigate(state, navigation.move_up)
}

pub fn down(state) {
  navigate(state, navigation.move_down)
}

pub fn increase(buffer: Buffer) {
  navigate(buffer, navigation.increase)
}

pub fn next_vacant(buffer) {
  navigate(buffer, snippet.go_to_next_vacant)
}

pub fn toggle_open(buffer) {
  navigate(buffer, navigation.toggle_open)
}

pub fn focus_at(buffer: Buffer, path) {
  navigate(buffer, navigate_focus_at(_, path))
}

fn navigate_focus_at(projection, path) {
  Ok(p.focus_at(p.rebuild(projection), path))
}

pub fn focus_at_reversed(buffer: Buffer, reversed) {
  focus_at(buffer, list.reverse(reversed))
}

// ------------------------- Transformations

pub type Continue {
  Done(fn(infer.Context) -> Buffer)
  WithString(fn(String, infer.Context) -> Buffer)
}

pub fn set_expression(buffer: Buffer) {
  case buffer.projection {
    #(p.Exp(_old), zoom) ->
      Ok(fn(new, context) { update_code(buffer, #(p.Exp(new), zoom), context) })
    _ -> Error(Nil)
  }
}

pub fn insert(buffer: Buffer) {
  use #(value, rebuild) <- result.map(case buffer.projection {
    #(p.Exp(e.String(value)), zoom) -> {
      Ok(#(value, fn(value) { #(p.Exp(e.String(value)), zoom) }))
    }
    _ -> p.text(buffer.projection)
  })
  #(value, fn(new, context) { update_code(buffer, rebuild(new), context) })
}

pub fn insert_before(buffer: Buffer) {
  use new <- result.map(action.extend_before(buffer.projection))
  case new {
    action.Updated(new) ->
      Done(fn(context) { update_code(buffer, new, context) })
    action.Choose(rebuild:, ..) ->
      WithString(fn(label, context) {
        update_code(buffer, rebuild(label), context)
      })
  }
}

pub fn insert_after(buffer: Buffer) {
  use new <- result.map(action.extend_after(buffer.projection))
  case new {
    action.Updated(new) ->
      Done(fn(context) { update_code(buffer, new, context) })
    action.Choose(rebuild:, ..) ->
      WithString(fn(label, context) {
        update_code(buffer, rebuild(label), context)
      })
  }
}

pub fn assign(buffer: Buffer) {
  use rebuild <- result.map(t.assign(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(e.Bind(new)), context) }
}

pub fn assign_before(buffer: Buffer) {
  use rebuild <- result.map(t.assign_before(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(e.Bind(new)), context) }
}

pub fn insert_variable(buffer: Buffer) {
  use rebuild <- result.map(t.variable(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn insert_function(buffer: Buffer) {
  use rebuild <- result.map(t.function(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn call_once(buffer: Buffer) {
  use new <- result.map(t.call(buffer.projection))
  fn(context) { update_code(buffer, new, context) }
}

pub fn call_many(buffer: Buffer) {
  use rebuild <- result.map(t.call_many(buffer.projection))
  fn(count, context) { update_code(buffer, rebuild(count), context) }
}

pub fn call_with(buffer: Buffer) {
  use new <- result.map(t.call_with(buffer.projection))
  fn(context) { update_code(buffer, new, context) }
}

pub fn insert_integer(buffer: Buffer) {
  use #(value, rebuild) <- result.map(t.integer(buffer.projection))
  #(value, fn(new, context) { update_code(buffer, rebuild(new), context) })
}

pub fn insert_string(buffer: Buffer) {
  use #(value, rebuild) <- result.map(t.string(buffer.projection))
  #(value, fn(new, context) { update_code(buffer, rebuild(new), context) })
}

pub fn insert_binary(buffer: Buffer) {
  use rebuild <- result.map(set_expression(buffer))
  rebuild(e.Binary(<<>>), _)
}

pub fn create_list(buffer: Buffer) {
  use new <- result.map(t.list(buffer.projection))
  fn(context) { update_code(buffer, new, context) }
}

pub fn create_empty_list(buffer: Buffer) {
  case buffer.projection {
    #(p.Exp(_old), zoom) -> {
      let new = #(p.Exp(e.List([], None)), zoom)
      Ok(fn(context) { update_code(buffer, new, context) })
    }
    _ -> Error(Nil)
  }
}

pub fn spread(buffer: Buffer) {
  use new <- result.map(t.spread_list(buffer.projection))
  fn(context) { update_code(buffer, new, context) }
}

pub fn create_record(buffer: Buffer) {
  use rebuild <- result.map(t.record(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn create_empty_record(buffer: Buffer) {
  use rebuild <- result.map(set_expression(buffer))
  rebuild(e.Record([], None), _)
}

pub fn overwrite(buffer: Buffer) {
  use rebuild <- result.map(t.overwrite(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn select_field(buffer: Buffer) {
  use rebuild <- result.map(t.select_field(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn tag(buffer: Buffer) {
  use rebuild <- result.map(t.tag(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn perform(buffer: Buffer) {
  use rebuild <- result.map(t.perform(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn insert_handle(buffer: Buffer) {
  use rebuild <- result.map(t.handle(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn insert_builtin(buffer: Buffer) {
  use #(_, rebuild) <- result.map(t.builtin(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn insert_reference(buffer: Buffer) {
  use #(_, rebuild) <- result.map(t.insert_reference(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn insert_release(buffer: Buffer) {
  use #(_, rebuild) <- result.map(t.insert_release(buffer.projection))
  fn(new, context) { update_code(buffer, rebuild(new), context) }
}

pub fn delete(buffer: Buffer) {
  use new <- result.map(t.delete(buffer.projection))
  fn(context) { update_code(buffer, new, context) }
}
