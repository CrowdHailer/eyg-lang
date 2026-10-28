//// The effects an EYG program can perform on the game, and nothing else.
//// Each one is a `touch_grass` interface: a name, the type of the value lifted
//// out of the program, the type of the reply lowered back in, and a decoder.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/result.{try}
import touch_grass
import touch_grass/interface.{type Harness, Interface}

pub type Point =
  #(Int, Int)

pub type Effect {
  ListIslands
  ListBridges
  AddBridge(from: Point, to: Point)
  RemoveBridge(from: Point, to: Point)
  Undo
  Redo
  IsSolved
  Print(String)
}

pub type Island {
  Island(at: Point, target: Int, bridges: Int)
}

pub type Bridge {
  Bridge(from: Point, to: Point, count: Int)
}

pub type Refusal {
  NoIsland(Point)
  NotReachable
  Full
  NoBridge
  AlreadySolved
}

fn point_type() {
  t.record([#("x", t.Integer), #("y", t.Integer)])
}

fn move_type() {
  t.record([#("from", point_type()), #("to", point_type())])
}

fn island_type() {
  t.record([
    #("x", t.Integer),
    #("y", t.Integer),
    #("target", t.Integer),
    #("bridges", t.Integer),
  ])
}

fn bridge_type() {
  t.record([
    #("from", point_type()),
    #("to", point_type()),
    #("count", t.Integer),
  ])
}

fn refusal_type() {
  t.union([
    #("NoIsland", point_type()),
    #("NotReachable", t.unit),
    #("Full", t.unit),
    #("NoBridge", t.unit),
    #("AlreadySolved", t.unit),
  ])
}

pub fn harness() -> Harness(Effect, a) {
  [
    Interface("ListIslands", t.unit, t.List(island_type()), cast.as_unit(
      _,
      ListIslands,
    )),
    Interface("ListBridges", t.unit, t.List(bridge_type()), cast.as_unit(
      _,
      ListBridges,
    )),
    Interface(
      "AddBridge",
      move_type(),
      t.result(t.unit, refusal_type()),
      decode_move(_, AddBridge),
    ),
    Interface(
      "RemoveBridge",
      move_type(),
      t.result(t.unit, refusal_type()),
      decode_move(_, RemoveBridge),
    ),
    Interface("Undo", t.unit, t.boolean, cast.as_unit(_, Undo)),
    Interface("Redo", t.unit, t.boolean, cast.as_unit(_, Redo)),
    Interface("IsSolved", t.unit, t.boolean, cast.as_unit(_, IsSolved)),
    touch_grass.print() |> touch_grass.map(Print),
  ]
}

fn decode_move(value, constructor) {
  use from <- try(cast.field("from", decode_point, value))
  use to <- try(cast.field("to", decode_point, value))
  Ok(constructor(from, to))
}

fn decode_point(value) {
  use x <- try(cast.field("x", cast.as_integer, value))
  use y <- try(cast.field("y", cast.as_integer, value))
  Ok(#(x, y))
}

fn point(point: Point) {
  let #(x, y) = point
  v.Record(dict.from_list([#("x", v.Integer(x)), #("y", v.Integer(y))]))
}

pub fn islands(islands: List(Island)) {
  v.LinkedList({
    use Island(at: #(x, y), target:, bridges:) <- list.map(islands)
    v.Record(
      dict.from_list([
        #("x", v.Integer(x)),
        #("y", v.Integer(y)),
        #("target", v.Integer(target)),
        #("bridges", v.Integer(bridges)),
      ]),
    )
  })
}

pub fn bridges(bridges: List(Bridge)) {
  v.LinkedList({
    use Bridge(from:, to:, count:) <- list.map(bridges)
    v.Record(
      dict.from_list([
        #("from", point(from)),
        #("to", point(to)),
        #("count", v.Integer(count)),
      ]),
    )
  })
}

pub fn outcome(outcome: Result(Nil, Refusal)) {
  case outcome {
    Ok(Nil) -> v.ok(v.unit())
    Error(refusal) ->
      v.error(case refusal {
        NoIsland(at) -> v.Tagged("NoIsland", point(at))
        NotReachable -> v.Tagged("NotReachable", v.unit())
        Full -> v.Tagged("Full", v.unit())
        NoBridge -> v.Tagged("NoBridge", v.unit())
        AlreadySolved -> v.Tagged("AlreadySolved", v.unit())
      })
  }
}

/// Convert a raised effect into one the game understands.
pub fn cast(label, lift) {
  interface.cast(harness(), label, lift)
}

pub fn types() {
  interface.types(harness())
}
