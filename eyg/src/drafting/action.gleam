import gleam/result.{try}
import morph/editable as e
import morph/projection
import morph/navigation
import morph/transformation
import drafting/session

// The return value of actions is one-one with the mode of the session
// this is not perfect because all actions that haven't yet changed the projection have to return a projection
// The navigate mode could be Done(projection) but the state would loose the projection reference so can't build overlays

// I don't want actions to return a reference to bindings so they cannot create a full session object

pub fn move_up(projection) {
  use projection <- try(navigation.move_up(projection))
  Ok(#(projection, session.Navigate))
}

pub fn move_down(projection) {
  use projection <- try(navigation.move_down(projection))
  Ok(#(projection, session.Navigate))
}

pub fn move_left(projection) {
  use projection <- try(navigation.move_left(projection))
  Ok(#(projection, session.Navigate))
}

pub fn move_right(projection) {
  use projection <- try(navigation.move_right(projection))
  Ok(#(projection, session.Navigate))
}

pub fn increase(projection) {
  Ok(#(navigation.increase(projection), session.Navigate))
}

pub fn decrease(projection) {
  Ok(#(navigation.decrease(projection), session.Navigate))
}

pub fn delete(projection) {
  let projection = transformation.delete(projection)
  Ok(#(projection, session.Navigate))
}

pub fn edit(projection) {
  use #(value, rebuild) <- try(projection.text(projection))
  Ok(#(projection, session.EditString(value, rebuild)))
}

pub fn variable(projection) {
  use rebuild <- try(transformation.variable(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn function(projection) {
  use rebuild <- try(transformation.function(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn call(projection) {
  use projection <- try(transformation.call(projection))
  Ok(#(projection, session.Navigate))
}

pub fn assign(projection) {
  use rebuild <- try(transformation.assign(projection))
  let rebuild = fn(new) { rebuild(e.Bind(new)) }
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn assign_before(projection) {
  use rebuild <- try(transformation.assign_before(projection))
  let rebuild = fn(new) { rebuild(e.Bind(new)) }
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn string(projection) {
  use #(value, rebuild) <- try(transformation.string(projection))
  Ok(#(projection, session.EditString(value, rebuild)))
}

pub fn list(projection) {
  use projection <- try(transformation.list(projection))
  Ok(#(projection, session.Navigate))
}

pub fn record(projection) {
  use next <- try(transformation.record(projection))
  case next {
    transformation.NeedString(rebuild) -> #(
      projection,
      session.EditString("", rebuild),
    )
    transformation.NoString(projection) -> #(projection, session.Navigate)
  }
  |> Ok
}

pub fn select(projection) {
  use rebuild <- try(transformation.select(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn overwrite(projection) {
  use rebuild <- try(transformation.overwrite(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn tag(projection) {
  use rebuild <- try(transformation.tag(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn match(projection) {
  use rebuild <- try(transformation.match(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn perform(projection) {
  use rebuild <- try(transformation.perform(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

// transformation does not say anything about Builtins but we know that it must be a builtin we are looking for
pub fn builtin(projection) {
  use #(value, rebuild) <- try(transformation.builtin(projection))
  Ok(#(projection, session.SelectBuiltin(value, [], 0, rebuild)))
}

pub fn extend(projection) {
  use next <- try(transformation.extend(projection))
  case next {
    transformation.NeedString(rebuild) -> #(
      projection,
      session.EditString("", rebuild),
    )
    transformation.NoString(projection) -> #(projection, session.Navigate)
  }
  |> Ok
}

pub fn spread_list(projection) {
  use projection <- try(transformation.spread_list(projection))
  Ok(#(projection, session.Navigate))
}

pub fn open_match(projection) {
  use projection <- try(transformation.open_match(projection))
  Ok(#(projection, session.Navigate))
}
