import eyg/parse/expression as e
import eyg/parse/lexer
import eyg/parse/parser
import gleeunit/should

pub fn literal_test() {
  "x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(#(e.Variable("x"), #(0, 1)))

  "12"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(#(e.Integer(12), #(0, 2)))

  "\"hello\""
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(#(e.Str("hello"), #(0, 7)))
}

pub fn lambda_test() {
  "(x) -> { 5 }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(#(e.Lambda("x", #(e.Integer(5), #(9, 10))), #(0, 12)))

  "(x, y) -> { 5 }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(e.Lambda("x", #(e.Lambda("y", #(e.Integer(5), #(12, 13))), #(0, 15))), #(
      0,
      15,
    )),
  )
}

pub fn fn_pattern_test() {
  // Need both brackets if allowing multiple args
  "({x: a, y: b}) -> { 5 }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Lambda(
        "$",
        #(
          e.Let(
            "a",
            #(
              e.Apply(#(e.Select("x"), #(2, 3)), #(e.Variable("$"), #(3, 4))),
              #(2, 4),
            ),
            #(
              e.Let(
                "b",
                #(
                  e.Apply(
                    #(e.Select("y"), #(8, 9)),
                    #(e.Variable("$"), #(9, 10)),
                  ),
                  #(8, 10),
                ),
                #(e.Integer(5), #(20, 21)),
              ),
              #(8, 21),
            ),
          ),
          #(2, 21),
        ),
      ),
      #(0, 23),
    ),
  )
}

pub fn apply_test() {
  "a(1)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(e.Apply(#(e.Variable("a"), #(0, 1)), #(e.Integer(1), #(2, 3))), #(0, 4)),
  )
  "a(10)(20)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Apply(#(e.Variable("a"), #(0, 1)), #(e.Integer(10), #(2, 4))), #(
          0,
          5,
        )),
        #(e.Integer(20), #(6, 8)),
      ),
      #(0, 9),
    ),
  )

  "x(y(3))"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Variable("x"), #(0, 1)),
        #(e.Apply(#(e.Variable("y"), #(2, 3)), #(e.Integer(3), #(4, 5))), #(
          2,
          6,
        )),
      ),
      #(0, 7),
    ),
  )
}

pub fn multiple_apply_test() {
  "a(x, y)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Apply(#(e.Variable("a"), #(0, 1)), #(e.Variable("x"), #(2, 3))), #(
          0,
          4,
        )),
        #(e.Variable("y"), #(5, 6)),
      ),
      #(0, 7),
    ),
  )
}

pub fn let_test() -> Nil {
  "let x = 5
   x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(e.Let("x", #(e.Integer(5), #(8, 9)), #(e.Variable("x"), #(13, 14))), #(
      0,
      14,
    )),
  )

  "let x = 5
   x.foo"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Let(
        "x",
        #(e.Integer(5), #(8, 9)),
        #(
          e.Apply(#(e.Select("foo"), #(14, 18)), #(e.Variable("x"), #(13, 14))),
          #(13, 18),
        ),
      ),
      #(0, 18),
    ),
  )

  "let x =
    let y = 3
    y
   x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Let(
        "x",
        #(
          e.Let("y", #(e.Integer(3), #(20, 21)), #(e.Variable("y"), #(26, 27))),
          #(12, 27),
        ),
        #(e.Variable("x"), #(31, 32)),
      ),
      #(0, 32),
    ),
  )

  "let x = 5
   let y = 1
   x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Let(
        "x",
        #(e.Integer(5), #(8, 9)),
        #(
          e.Let("y", #(e.Integer(1), #(21, 22)), #(e.Variable("x"), #(26, 27))),
          #(13, 27),
        ),
      ),
      #(0, 27),
    ),
  )
}

pub fn let_record_test() -> Nil {
  "let {x: a, y: _} = rec
   a"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Let(
        "$",
        #(e.Variable("rec"), #(19, 22)),
        #(
          e.Let(
            "a",
            #(
              e.Apply(#(e.Select("x"), #(5, 6)), #(e.Variable("$"), #(6, 7))),
              #(5, 7),
            ),
            #(
              e.Let(
                "_",
                #(
                  e.Apply(
                    #(e.Select("y"), #(11, 12)),
                    #(e.Variable("$"), #(12, 13)),
                  ),
                  #(11, 13),
                ),
                #(e.Variable("a"), #(26, 27)),
              ),
              #(11, 27),
            ),
          ),
          #(5, 27),
        ),
      ),
      #(0, 27),
    ),
  )

  "let {x, y} = rec
   a"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(#(
    e.Let("$", #(e.Variable("rec"), #(13, 16)), #(
      e.Let(
        "x",
        #(e.Apply(#(e.Select("x"), #(5, 6)), #(e.Variable("$"), #(5, 6))), #(
          5,
          6,
        )),
        #(
          e.Let(
            "y",
            #(
              e.Apply(#(e.Select("y"), #(8, 9)), #(e.Variable("$"), #(8, 9))),
              #(8, 9),
            ),
            #(e.Variable("a"), #(20, 21)),
          ),
          #(8, 21),
        ),
      ),
      // This should go to end of let
      #(5, 21),
    )),
    #(0, 21),
  ))

  "let {} = rec
   a"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Let("$", #(e.Variable("rec"), #(9, 12)), #(e.Variable("a"), #(16, 17))),
      #(0, 17),
    ),
  )
}

pub fn list_test() {
  "[]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(#(e.Tail, #(0, 2)))

  "[1, 2]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Apply(#(e.Cons, #(0, 1)), #(e.Integer(1), #(1, 2))), #(0, 2)),
        #(
          e.Apply(
            #(e.Apply(#(e.Cons, #(2, 3)), #(e.Integer(2), #(4, 5))), #(2, 5)),
            #(e.Tail, #(5, 6)),
          ),
          #(2, 6),
        ),
      ),
      #(0, 6),
    ),
  )

  "[[11]]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(
          e.Apply(
            #(e.Cons, #(0, 1)),
            #(
              e.Apply(
                #(e.Apply(#(e.Cons, #(1, 2)), #(e.Integer(11), #(2, 4))), #(
                  1,
                  4,
                )),
                #(e.Tail, #(4, 5)),
              ),
              #(1, 5),
            ),
          ),
          #(0, 5),
        ),
        #(e.Tail, #(5, 6)),
      ),
      #(0, 6),
    ),
  )

  "[a(7), 8]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(
          e.Apply(
            #(e.Cons, #(0, 1)),
            #(e.Apply(#(e.Variable("a"), #(1, 2)), #(e.Integer(7), #(3, 4))), #(
              1,
              5,
            )),
          ),
          #(0, 5),
        ),
        #(
          e.Apply(
            #(e.Apply(#(e.Cons, #(5, 6)), #(e.Integer(8), #(7, 8))), #(5, 8)),
            #(e.Tail, #(8, 9)),
          ),
          #(5, 9),
        ),
      ),
      #(0, 9),
    ),
  )
}

pub fn list_spread_test() {
  "[1, ..x]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Apply(#(e.Cons, #(0, 1)), #(e.Integer(1), #(1, 2))), #(0, 2)),
        #(e.Variable("x"), #(6, 7)),
      ),
      #(0, 7),
    ),
  )
  "[1, ..x(5)]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Apply(#(e.Cons, #(0, 1)), #(e.Integer(1), #(1, 2))), #(0, 2)),
        #(e.Apply(#(e.Variable("x"), #(6, 7)), #(e.Integer(5), #(8, 9))), #(
          6,
          10,
        )),
      ),
      #(0, 10),
    ),
  )
}

pub fn record_test() {
  "{}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(#(e.Empty, #(0, 2)))

  "{a: 5, b: {}}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Apply(#(e.Extend("a"), #(0, 3)), #(e.Integer(5), #(4, 5))), #(0, 5)),
        #(
          e.Apply(
            #(e.Apply(#(e.Extend("b"), #(5, 9)), #(e.Empty, #(10, 12))), #(
              5,
              12,
            )),
            #(e.Empty, #(12, 13)),
          ),
          #(5, 13),
        ),
      ),
      #(0, 13),
    ),
  )
  // "{foo: x(2)}"
  // |> lexer.lex()
  // |> parser.parse()
  // |> should.be_ok()
  // |> should.equal(e.record([#("foo", e.Apply(e.Variable("x"), e.Integer(2)))]))
}

pub fn record_sugar_test() {
  "{a, b}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    #(
      e.Apply(
        #(e.Apply(#(e.Extend("a"), #(0, 2)), #(e.Variable("a"), #(1, 2))), #(
          0,
          2,
        )),
        #(
          e.Apply(
            #(
              e.Apply(#(e.Extend("b"), #(2, 5)), #(e.Variable("b"), #(4, 5))),
              #(2, 5),
            ),
            #(e.Empty, #(5, 6)),
          ),
          #(2, 6),
        ),
      ),
      #(0, 6),
    ),
  )
}
// pub fn overwrite_test() -> Nil {
//   "{a: 5, ..x}"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(
//     e.Apply(e.Overwrite("a"), e.Integer(5)),
//     e.Variable("x"),
//   ))

//   "{..x}"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Variable("x"))
// }

// pub fn overwrite_sugar_test() -> Nil {
//   "{a, ..x}"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(
//     e.Apply(e.Overwrite("a"), e.Variable("a")),
//     e.Variable("x"),
//   ))
// }

// pub fn field_access_test() {
//   "a.foo"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(e.Select("foo"), e.Variable("a")))

//   "b(x).foo"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(
//     e.Select("foo"),
//     e.Apply(e.Variable("b"), e.Variable("x")),
//   ))

//   "a.foo(2)"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(
//     e.Apply(e.Select("foo"), e.Variable("a")),
//     e.Integer(2),
//   ))
// }

// pub fn tagged_test() {
//   "Ok(2)"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(e.Tag("Ok"), e.Integer(2)))
// }

// pub fn match_test() {
//   "match { }"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.NoCases)

//   "match x { }"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(e.NoCases, e.Variable("x")))

//   "match {
//     Ok x
//     Error(y) -> { y }
//   }"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(
//     e.Apply(e.Case("Ok"), e.Variable("x")),
//     e.Apply(e.Apply(e.Case("Error"), e.Lambda("y", e.Variable("y"))), e.NoCases),
//   ))

//   "match {
//     User({name, age}) -> { age }
//   }"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(
//     e.Apply(
//       e.Case("User"),
//       e.Lambda(
//         "$",
//         e.Let(
//           "name",
//           e.Apply(e.Select("name"), e.Variable("$")),
//           e.Let(
//             "age",
//             e.Apply(e.Select("age"), e.Variable("$")),
//             e.Variable("age"),
//           ),
//         ),
//       ),
//     ),
//     e.NoCases,
//   ))
// }

// pub fn perform_test() {
//   "perform Log"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Perform("Log"))

//   "perform Log(\"stop\")"
//   |> lexer.lex()
//   |> parser.parse()
//   |> should.be_ok()
//   |> should.equal(e.Apply(e.Perform("Log"), e.Str("stop")))
// }
