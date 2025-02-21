pub fn pages() {
  [
    #("intro", intro_content()),
    #("http", http_content()),
    // #("json", json_content()),
  ]
}

pub fn intro_content() {
  [
    #(
      ["http"],
      "let http = #h85a585d
let task = #h3a65ae15
let json = #h53ac7475

let result_decoder = json.object(
  json.field(\"sunrise\", json.string, 
  json.field(\"sunset\", json.string,
  json.done)), (sunrise, sunset) -> { {sunrise, sunset} })
let decoder = json.object(json.field(\"results\", result_decoder, json.done), (x) -> { x }) 

let run = (_) -> {
  let query = \"lat=38.907192&lng=-77.036873\"
  let request = http.get(\"api.sunrisesunset.io\", \"/json\", Some(query))
  let response = task.fetch(request)

  json.parse_bytes(decoder, response)
}",
    ),
    #(
      ["cat"],
      "let { debug } = #he4b05da
let http = #h85a585d
let task = #h3a65ae15
let json = #h53ac7475

let run = (_) -> {
  let request = http.get(\"catfact.ninja\", \"/fact\", None({}))
  let response = task.fetch(request)

  let decoder = json.object(json.field(\"fact\", json.string, json.done), (fact) -> { fact })
  json.parse_bytes(decoder, response)
}",
    ),
    #(["toro"], "let x = todo"),
    #(
      ["whats the point"],
      "let { string } = #he4b05da

let run = (_) -> {
  let answer = perform Ask(\"What's your name?\")
  perform Log(string.append(\"Hello \", answer))
}",
    ),
    #(
      ["heo"],
      "let { string } = #he4b05da
  let run = (_) -> { 
    let a = match perform Geo({}) {
      Ok({latitude,longitude}) -> { {latitude,longitude} }
     }
    let _ = perform Wait(5000)
    a
  }",
    ),
  ]
}

pub fn http_content() {
  [
    #(
      ["constants"],
      "let http = HTTP({})
let https = HTTPS({})",
    ),
    #(
      ["building requests"],
      "let build_request = (method, scheme, host, port, path, query, headers, body) -> {
  {method, scheme, host, port, path, query, headers, body}
}

let get = (host, path, query) -> {
  build_request(GET({}), https, host, None({}), path, query, [], !string_to_binary(\"\"))
}",
    ),
    // #(
  //       ["task"],
  //       "let { equal, debug } = #he4b05da

  // let fetch = (request) -> {
  //   match perform Await(perform Fetch(request)) {
  //     Ok({status, body}) -> { match equal(status, 200) {
  //       True(_) -> { body }
  //       False(_) -> { perform Abort(\"request returned not OK status\") }
  //     } }
  //     Error(reason) -> { perform Abort(reason) }
  //   }
  // }",
  //     ),
  ]
}

pub fn json_content() {
  [
    #(
      ["json"],
      "let { list, keylist, string } = #he4b05da

let digits = [\"1\", \"2\", \"3\", \"4\", \"5\", \"6\", \"7\", \"8\", \"9\", \"0\"]
let whitespace = [\" \", \"\r\n\", \"\n\",\"\r\", \"\t\"]

let literal = [
  {key: \"{\", value: LeftBrace({})},
  {key: \"}\", value: RightBrace({})},
  {key: \"[\", value: LeftBracket({})},
  {key: \"]\", value: RightBracket({})},
  {key: \":\", value: Colon({})},
  {key: \",\", value: Comma({})}
]

let read_string = !fix((read_string, gathered, rest) -> { 
  !pop_prefix(rest, \"\\\\\\\"\", 
    read_string(string.append(gathered, \"\\\"\")), (_) -> {
    !pop_prefix(rest, \"\\\"\", 
      (rest) -> { Ok({gathered, rest}) }, 
      (_) -> {
        match string.pop_grapheme(rest) {
          Ok({head, tail}) -> { read_string(string.append(gathered, head), tail) }
          Error(_) -> { Error({}) }
        }
      }
    )
  })
})(\"\")

let read_number = !fix((read_number, gathered, rest) -> { 
  match string.pop_grapheme(rest) {
    Ok({head, tail}) -> { 
      match list.contains([\".\", ..digits], head) {
        True(_) -> { read_number(string.append(gathered, head), tail) }
        False(_) -> { {gathered, rest} }
      }
    }
    Error(_) -> { {gathered, rest} }
  }
})

let tokenise = !fix((tokenise, acc, rest) -> {
  !pop_prefix(rest, \"true\", tokenise([True({}), ..acc]), (_) -> { 
    !pop_prefix(rest, \"false\", tokenise([False({}), ..acc]), (_) -> { 
      !pop_prefix(rest, \"null\", tokenise([Null({}), ..acc]), (_) -> { 
        !pop_prefix(rest, \"\\\"\",
          (rest) -> {
            match read_string(rest) {
              Ok({gathered, rest}) -> { tokenise([String(gathered), ..acc], rest) }
              Error(_) -> { list.reverse([UnterminatedString(rest), ..acc]) }
            }
          }, 
          (_) -> { 
            match !pop_grapheme(rest) {
              Ok({head, tail}) -> { 
                match list.contains(whitespace, head) {
                  True(_) -> { tokenise(acc, tail) }
                  False(_) -> { 
                    match keylist.find(literal, head) {
                      Ok(token) -> { tokenise([token, ..acc], tail) }
                      Error(_) -> { 
                        match list.contains([\"-\", ..digits], head) {
                          True(_) -> { 
                            let {gathered, rest} = read_number(head, tail)
                            tokenise([Number(gathered), ..acc], rest)
                          }
                          False(_) -> { tokenise([IllegalCharachter(head), ..acc], tail) }
                        }
                      }
                    }
                  }
                }
              }
              Error(_) -> { list.reverse(acc) }
            }
          }
        )
      })
    })
  })
})([])
let run = (_) -> {
  tokenise(\"{
      \\\"results\\\": {
        \\\"date\\\": \\\"2024-06-26\\\",
        \\\"sunrise\\\": \\\"5:45:46 AM\\\",
        \\\"sunset\\\": \\\"8:38:48 PM\\\",
        \\\"first_light\\\": \\\"3:46:58 AM\\\",
        \\\"last_light\\\": \\\"10:37:36 PM\\\",
        \\\"dawn\\\": \\\"5:13:44 AM\\\",
        \\\"dusk\\\": \\\"9:10:50 PM\\\",
        \\\"solar_noon\\\": \\\"1:12:17 PM\\\",
        \\\"golden_hour\\\": \\\"7:58:53 PM\\\",
        \\\"day_length\\\": \\\"14:53:01\\\",
        \\\"timezone\\\": \\\"America/New_York\\\",
        \\\"utc_offset\\\": -240
      },
      \\\"status\\\": \\\"OK\\\"
    }\"
  )
}",
    ),
    #(
      ["Flat representation"],
      "let { list, keylist, string } = #he4b05da

let take = (tokens, then) -> {
  !uncons(tokens, (_) -> { Error(UnexpectedEnd({})) }, then)
}

let read_field = !fix((read_field, flat, acc, stack, tokens) -> {
  take(tokens, (token, tokens) -> {
    match token {
      RightBrace(_) -> { todo }
      String(raw) -> { 
        take(tokens, (token, tokens) -> {
          match token {
            Colon(_) -> {
              let depth = list.length(stack)
              let acc = [{term: Field(raw), depth},..acc]
              flat(acc, stack, tokens)
            }
            |(_) -> { Error(UnexpectedEnd({}))  }
          }
        })
      }
      |(_) -> { Error(UnexpectedEnd({}))  }
    }
  })
})


let flat = !fix((flat, acc, stack, tokens) -> {
  !uncons(tokens, (_) -> { Error(UnexpectedEnd({})) }, (token, tokens) -> {
    let depth = list.length(stack)
    let k = (acc, stack) -> { 
      !uncons(stack, (_) -> { Ok(list.reverse(acc)) },(_,_) -> { flat(acc, stack, tokens) })
    }
    match token {
      True(_) -> { k([{term: True({}), depth}, ..acc], stack) }
      False(_) -> { k([{term: False({}), depth}, ..acc], stack) }
      Null(_) -> { k([{term: Null({}), depth}, ..acc], stack) }
      Number(raw) -> { k([{term: Number(raw), depth}, ..acc], stack) }
      String(raw) -> { k([{term: String(raw), depth}, ..acc], stack) }
      LeftBracket(_) -> {
        k([{term: List({}), depth}, ..acc], [List({}), ..stack])
      }
      RightBracket(_) -> {
        !uncons(stack, (_) -> { Error(UnexpectedToken(token)) }, (current, stack) -> { 
          match current {
            List(_) -> { k(acc, stack) }
            |(_) -> { Error(UnexpectedToken(token)) }
          }
        })
      }
      LeftBrace(_) -> {
        read_field(flat, [{term: Object({}), depth}, ..acc], [Object({}), ..stack], tokens)
      }
      RightBrace(_) -> {
        !uncons(stack, (_) -> { Error(UnexpectedToken(token)) }, (current, stack) -> { 
          match current {
            Object(_) -> { k(acc, stack) }
            |(_) -> { Error(UnexpectedToken(token)) }
          }
        })
      }
      Comma(_) -> {
        !uncons(stack, (_) -> { Error(UnexpectedToken(token)) }, (current,_) -> { 
          match current {
            List(_) -> { k(acc, stack) }
            Object(_) -> { read_field(flat, acc, stack, tokens) }
            |(_) -> { Error(UnexpectedToken(token)) }
          }
        })
      }
      |(other) -> { Error(UnexpectedToken(other)) }
    }
    
  })
})([],[])

let a = (_) -> {
  let tokens = tokenise(\"{}\")
  flat(tokens)
}

let a = (_) -> {
  let tokens = tokenise(\"{\\\"b\\\":5,\\\"c\\\":{\\\"x\\\":5}}\")
  flat(tokens)
}


let run = (_) -> {
  let tokens = tokenise(\"[1,2]\")
  flat(tokens)
}",
    ),
    #(
      ["Parsing"],
      "let { equal, debug } = #he4b05da


let boolean = (flattened) -> {
  !uncons(flattened, (_) -> { Error(UnexpectedEnd({})) }, ({term}, rest) -> {
    match term {
      True(_) -> { Ok({value: True({}), rest}) }
      False(_) -> { Ok({value: False({}), rest})}
      |(other) -> { Error(UnexpectedTerm(other)) }
    }
  })
}

let integer = (flattened) -> {
  !uncons(flattened, (_) -> { Error(UnexpectedEnd({})) }, ({term}, rest) -> {
    match term {
      Number(raw) -> { match !int_parse(raw) {
        Ok(value) -> { Ok({value: value, rest}) }
        |(other) -> { Error(NotAnInteger(raw)) }
      } }
      |(other) -> { Error(UnexpectedTerm(other)) }
    }
  })
}

let string = (flattened) -> {
  !uncons(flattened, (_) -> { Error(UnexpectedEnd({})) }, ({term}, rest) -> {
    match term {
      String(raw) -> { Ok({value: raw, rest}) }
      |(other) -> { Error(UnexpectedTerm(other)) }
    }
  })
}

let lookup = !fix((lookup, flattened, field, under) -> {
  take(flattened, ({term, depth}, flattened) -> {
    match !int_compare(depth, under) {
      Lt(_) -> { Error(UnknownField(field)) }
      Eq(_) -> {
        match term {
          Field(f) -> { 
            match equal(f, field) {
              True(_) -> { Ok(flattened) }
              False(_) -> { lookup(flattened, field, under) }
            }
          }
          |(other) -> { lookup(flattened, field, under) }
        }
      }
      Gt(_) -> { lookup(flattened, field, under) }
    }

  })
})

let fetch_field = (flattened, field) -> {
  take(flattened, ({term, depth}, rest) -> {
    match term {
      Object(raw) -> { lookup(rest, field, !int_add(depth, 1)) }
      |(other) -> { Error(UnexpectedTerm(other)) }
    }
  })
}

let expect = (result) -> {
  match result {
    Ok(value) -> { value }
    Error(reason) -> { perform Abort(reason) }
  }
}


let a = (_) -> {
  let tokens = tokenise(\"{\\\"b\\\":5,\\\"c\\\":{\\\"x\\\":5}}\")
  let flattened =  expect(flat(tokens))
  let _ = perform Log(debug(flattened))
  field(flattened, \"c\")
}


let drop = !fix((drop, flattened, under) -> {
  !uncons(flattened, (_) -> { [] }, ({term, depth}, flattened) -> {
    match !int_compare(depth, under) {
      Lt(_) -> { flattened }
      |(_) -> { drop(flattened, under) }
    }

  })
})

let done = (builder,depth,flattened) -> {
  Ok({value: builder, rest: drop(flattened, depth)})
}

let field = (label, decoder, next, builder, level, flattened) -> {
  match lookup(flattened, label, level) {
    Ok(rest) -> { match decoder(rest) {
      Ok({value}) -> { next(builder(value), level, flattened) }
      |(other) -> { other }
    } }
    |(other) -> { other }
  }
}

let object = (fields, builder, flattened) -> {
  take(flattened, ({term, depth}, rest) -> {
    match term {
      Object(raw) -> { match fields(builder, !int_add(depth, 1), rest) {
        Ok(inner) -> { Ok(inner) }
        |(other) -> { other }
      }}
      |(other) -> { Error(UnexpectedTerm(other)) }
    }
  })
}

let a = (_) -> {
  let tokens = tokenise(\"{\\\"b\\\":5,\\\"c\\\":{\\\"x\\\":5}}\")
  let flattened =  expect(flat(tokens))
  let _ = perform Log(debug(flattened))
  let decoder = object(field(\"b\", integer, done), (x) -> { x })
  decoder(flattened)
}
 
let l = (decoder, rest) -> {
  !uncons(rest, (_) -> { Error(UnexpectedEnd({})) }, ({term, depth}, rest) -> {
    match term {
      List(_) -> {
        !fix((pull, acc, rest)-> {
          !uncons(rest, (_) -> { 
            Ok({value: list.reverse(acc), rest}) 
          }, ({depth: next},_)-> {
            match !int_compare(next, depth) {
              Gt(_) -> { match decoder(rest) {
                Ok({value, rest}) -> { pull([value,..acc], rest) }
                Error(reason) -> { Error(reason) }
              } }
              Lt(_) -> { Ok({value: list.reverse(acc), rest}) }
            }
          })
        })([], rest)
      }
      |(other) -> { Error(UnexpectedTerm(other)) }
    }
  })
}
",
    ),
    #(
      ["building"],
      "let { debug } = #he4b05da
let parse = (decoder, raw) -> {
  let flattened = flat(tokenise(raw))
  let _ = perform Log(debug(flattened))
  match flattened {
    Ok(flat) -> { match decoder(flat) {
      Ok({value}) -> { Ok(value) }
      Error(reason) -> { Error(reason) }
    } }
    Error(reason) -> { Error(reason) }
  }
}
 
let parse_bytes = (decoder, bytes) -> {
  
  match !string_from_binary(bytes) {
    Ok(string) -> { match flat(tokenise(string)) {
      Ok(flattened) -> { match decoder(flattened) {
        Ok({value}) -> { Ok(value) }
        |(other) -> { other }
      } }
      |(other) -> { other }
    } }
    |(other) -> { other }
  }
}

let run = (_) -> {
  let _ = parse(l(boolean), \"[true]\")
   parse(l(integer), \"[2]\")
}",
    ),
  ]
}
