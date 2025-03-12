import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import gleam/option.{type Option}
import morph/analysis

// created with source that is the current value in the bottom of the shell
// 
pub type Mount {
  // dont need the source 
  Mount(run: Return)
}

type Scope =
  List(#(String, analysis.Value))

type Return =
  Result(#(Option(analysis.Value), Scope), istate.Debug(analysis.Path))

pub fn init(source, effects, cache) {
  todo
}

pub type Message {
  Message
}

pub fn update(state, message) {
  todo
}
