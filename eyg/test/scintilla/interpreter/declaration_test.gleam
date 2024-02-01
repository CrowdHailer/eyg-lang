// import gleam/dict
// import simplifile
// import glance as g
//
// import scintilla/reason as r
// import scintilla/prelude
// import repl/reader
// import repl/runner
// import gleeunit/should

// pub fn custom_enum_test() {
//   let state = runner.init(dict.new(), dict.new())
//   let assert Ok(#(term, [])) =
//     reader.parse(
//       "type Foo {
//     A
//     B
//   }",
//     )
//   let assert Ok(#(None, state)) = runner.read(term, state)

//   let assert Ok(#(term, [])) = reader.parse("A")
//   let assert Ok(#(return, _)) = runner.read(term, state)

//   return
//   |> should.equal(Some(v.R("A", [])))
// }

// pub fn custom_record_test() {
//   let state = runner.init(dict.new(), dict.new())
//   let assert Ok(#(term, [])) =
//     reader.parse(
//       "type Wrap {
//     Wrap(Int)
//   }",
//     )
//   let assert Ok(#(None, state)) = runner.read(term, state)

//   let assert Ok(#(term, [])) = reader.parse("Wrap(2)")
//   let assert Ok(#(return, _)) = runner.read(term, state)

//   return
//   |> should.equal(Some(v.R("Wrap", [g.Field(None, v.I(2))])))
// }

// pub fn named_record_fields_test() {
//   let initial = runner.init(dict.new(), dict.new())
//   let assert Ok(#(term, [])) =
//     reader.parse(
//       "type Rec {
//     Rec(a: Int, b: Float)
//   }",
//     )
//   let assert Ok(#(None, initial)) = runner.read(term, initial)

//   let assert Ok(#(term, [])) = reader.parse("Rec(b: 2.0, a: 1)")
//   let assert Ok(#(return, _)) = runner.read(term, initial)
//   return
//   |> should.equal(
//     Some(v.R("Rec", [g.Field(Some("a"), v.I(1)), g.Field(Some("b"), v.F(2.0))])),
//   )

//   let assert Ok(#(term, [])) = reader.parse("let x = Rec(b: 2.0, a: 1) x.a")
//   let assert Ok(#(return, _)) = runner.read(term, initial)
//   return
//   |> should.equal(Some(v.I(1)))

//   let assert Ok(#(term, [])) = reader.parse("let x = Rec(b: 2.0, a: 1) x.c")
//   let assert Error(reason) = runner.read(term, initial)
//   reason
//   |> should.equal(r.MissingField("c"))

//   let assert Ok(#(term, [])) = reader.parse("\"\".c")
//   let assert Error(reason) = runner.read(term, initial)
//   reason
//   |> should.equal(r.IncorrectTerm("Record", v.S("")))
// }

// pub fn constant_test() {
//   let initial = runner.init(dict.new(), dict.new())
//   let assert Ok(#(term, [])) = reader.parse("pub const x = 5")
//   let assert Ok(#(_, initial)) = runner.read(term, initial)

//   let assert Ok(#(term, [])) = reader.parse("x")
//   let assert Ok(#(return, _)) = runner.read(term, initial)
//   return
//   |> should.equal(Some(v.I(5)))
// }

// pub fn recursive_function_test() {
//   let initial = runner.init(dict.new(), dict.new())
//   let assert Ok(#(term, [])) =
//     reader.parse(
//       "pub fn count(items, total) {
//         case items {
//           [] -> total
//           [_, ..items] -> count(items, total + 1)
//         }
//       }",
//     )
//   let assert Ok(#(_, initial)) = runner.read(term, initial)

//   let assert Ok(#(term, [])) = reader.parse("count([], 0)")
//   let assert Ok(#(return, _)) = runner.read(term, initial)
//   return
//   |> should.equal(Some(v.I(0)))

//   let assert Ok(#(term, [])) = reader.parse("count([10, 20], 0)")
//   let assert Ok(#(return, _)) = runner.read(term, initial)
//   return
//   |> should.equal(Some(v.I(2)))
// }

// pub fn top_function_test() {
//   let state = #(dict.new(), dict.new())
//   let line = "fn foo(a x, b y) { x - y }"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(_, initial)) = r_runner.read(term, state)

//   let line = "foo(7, 6)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(Some(value), _)) = r_runner.read(term, initial)
//   value
//   |> should.equal(I(1))

//   let line = "foo(b: 3, a: 2)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(Some(value), _)) = r_runner.read(term, initial)
//   value
//   |> should.equal(I(-1))

//   let line = "foo(4, b: 8)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(Some(value), _)) = r_runner.read(term, initial)
//   value
//   |> should.equal(I(-4))

//   let line = "foo(4, c: 8)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Error(reason) = r_runner.read(term, initial)
//   reason
//   |> should.equal(r.MissingField("c"))

//   let line = "foo(4)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Error(reason) = r_runner.read(term, initial)
//   reason
//   |> should.equal(r.IncorrectArity(2, 1))

//   let line = "foo(4, 3, 2)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Error(reason) = r_runner.read(term, initial)
//   reason
//   |> should.equal(r.IncorrectArity(2, 3))
// }
