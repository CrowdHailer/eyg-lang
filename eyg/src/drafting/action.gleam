import gleam/result.{try}
import morph/projection
import morph/navigation
import morph/transformation
import drafting/session.{type Session}

// The return value of actions is one-one with the mode of the session
// this is not perfect because all actions that haven't yet changed the projection have to return a projection
// The navigate mode could be Done(projection) but the state would loose the projection reference so can't build overlays

// I don't want actions to return a reference to bindings so they cannot create a full session object

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

pub fn variable(projection) {
  use rebuild <- try(transformation.variable(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}

pub fn function(projection) {
  use rebuild <- try(transformation.function(projection))
  Ok(#(projection, session.EditString("", rebuild)))
}
//     #(
//       "function",
//       fn(zip) {
//         let assert Ok(rebuild) = transformation.function(zip)
//         update_focus()
//         State(zip, RequireString("", rebuild))
//       },
//       Some("f"),
//     ),
//     #(
//       "variable",
//       fn(zip) {
//         
//         update_focus()
//         State(zip, RequireString("", rebuild))
//       },
//       Some("v"),
//     ),
