import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/option.{type Option, None}
import gleam/javascript/promise
import lustre/effect
import gleam/javascript/promisex
import plinth/javascript/global
import plinth/javascript/date.{type Date}
import plinth/javascript/storage
import plinth/browser/document
import plinth/browser/element
import facilities/accu_weather/client as accu_weather
import facilities/accu_weather/daily_forecast
import facilities/trafiklab/realtidsinformation_4 as rt4
import repl/runner.{type Value}

pub type State {
  State(
    scope: Dict(String, runner.Value),
    statement: String,
    execute_error: Option(runner.Reason),
    history: List(#(String, String)),
  )
}

pub fn init(_) {
  let state = State(dict.new(), "", None, [])
  #(state, effect.batch([]))
}

pub type Wrap {
  Wrap(fn(State) -> #(State, effect.Effect(Wrap)))
}

pub fn update(state, msg) {
  let Wrap(msg) = msg
  msg(state)
}
// tasks
