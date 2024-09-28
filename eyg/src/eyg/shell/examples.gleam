import eygir/decode
import morph/editable
import morph/projection

fn catfact_fetch() {
  let assert Ok(source) =
    decode.from_json(
      // "{\"0\":\"l\",\"l\":\"request\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"get\"},\"a\":{\"0\":\"v\",\"l\":\"http\"}},\"a\":{\"0\":\"s\",\"v\":\"catfact.ninja\"}},\"a\":{\"0\":\"s\",\"v\":\"/fact\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"None\"},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"l\",\"l\":\"response\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"$\",\"b\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"body\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"v\",\"l\":\"body\"}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Abort\"},\"a\":{\"0\":\"s\",\"v\":\"No response\"}}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Fetch\"},\"a\":{\"0\":\"v\",\"l\":\"request\"}}},\"t\":{\"0\":\"z\",\"c\":\"\"}}}",
      // "{\"0\":\"l\",\"l\":\"request\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"get\"},\"a\":{\"0\":\"v\",\"l\":\"http\"}},\"a\":{\"0\":\"s\",\"v\":\"catfact.ninja\"}},\"a\":{\"0\":\"s\",\"v\":\"/fact\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"None\"},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"$\",\"b\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"body\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"v\",\"l\":\"body\"}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Abort\"},\"a\":{\"0\":\"s\",\"v\":\"No response\"}}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Fetch\"},\"a\":{\"0\":\"v\",\"l\":\"request\"}}},\"t\":{\"0\":\"l\",\"l\":\"json\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"json\",\"b\":{\"0\":\"v\",\"l\":\"json\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"z\",\"c\":\"\"}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"binary_to_string\"},\"a\":{\"0\":\"v\",\"l\":\"body\"}}},\"t\":{\"0\":\"z\",\"c\":\"\"}}}}",
      "{\"0\":\"l\",\"l\":\"request\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"get\"},\"a\":{\"0\":\"v\",\"l\":\"http\"}},\"a\":{\"0\":\"s\",\"v\":\"catfact.ninja\"}},\"a\":{\"0\":\"s\",\"v\":\"/fact\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"None\"},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"$\",\"b\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"body\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"v\",\"l\":\"body\"}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Abort\"},\"a\":{\"0\":\"s\",\"v\":\"No response\"}}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Fetch\"},\"a\":{\"0\":\"v\",\"l\":\"request\"}}},\"t\":{\"0\":\"l\",\"l\":\"decoder\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"object\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"field\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"s\",\"v\":\"fact\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"string\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"done\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}}}},\"a\":{\"0\":\"f\",\"l\":\"x\",\"b\":{\"0\":\"v\",\"l\":\"x\"}}},\"t\":{\"0\":\"l\",\"l\":\"fact\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"json\",\"b\":{\"0\":\"v\",\"l\":\"json\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"z\",\"c\":\"\"}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"parse_bytes\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"v\",\"l\":\"decoder\"}},\"a\":{\"0\":\"v\",\"l\":\"body\"}}},\"t\":{\"0\":\"z\",\"c\":\"\"}}}}}",
    )
  let source = editable.from_expression(source)
  let source = projection.focus_at(source, [0])
  #(source, "fetch a random cat fact")
}

fn sunrise() {
  let assert Ok(source) =
    decode.from_json(
      "{\"0\":\"l\",\"l\":\"query\",\"v\":{\"0\":\"s\",\"v\":\"lat=36.7201600&lng=-4.4203400\"},\"t\":{\"0\":\"l\",\"l\":\"decoder\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"object\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"field\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"s\",\"v\":\"results\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"object\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"field\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"s\",\"v\":\"sunrise\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"string\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"done\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}}}},\"a\":{\"0\":\"f\",\"l\":\"x\",\"b\":{\"0\":\"v\",\"l\":\"x\"}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"done\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}}}},\"a\":{\"0\":\"f\",\"l\":\"x\",\"b\":{\"0\":\"v\",\"l\":\"x\"}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"$\",\"b\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"body\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"l\",\"l\":\"status\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"status\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"parse_bytes\"},\"a\":{\"0\":\"v\",\"l\":\"json\"}},\"a\":{\"0\":\"v\",\"l\":\"decoder\"}},\"a\":{\"0\":\"v\",\"l\":\"body\"}}}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"z\",\"c\":\"\"}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Fetch\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"get\"},\"a\":{\"0\":\"v\",\"l\":\"http\"}},\"a\":{\"0\":\"s\",\"v\":\"api.sunrise-sunset.org\"}},\"a\":{\"0\":\"s\",\"v\":\"/json\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"Some\"},\"a\":{\"0\":\"v\",\"l\":\"query\"}}}}}}}",
    )
  let source = editable.from_expression(source)
  let source = projection.focus_at(source, [0])
  #(source, "get your sunrise sunset time")
}

fn wordcount() {
  let assert Ok(source) =
    decode.from_json(
      "{\"0\":\"l\",\"l\":\"expect\",\"v\":{\"0\":\"f\",\"l\":\"result\",\"b\":{\"0\":\"f\",\"l\":\"message\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"v\",\"l\":\"value\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Abort\"},\"a\":{\"0\":\"v\",\"l\":\"message\"}}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"v\",\"l\":\"result\"}}}},\"t\":{\"0\":\"l\",\"l\":\"bytes\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"expect\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"File.Read\"},\"a\":{\"0\":\"s\",\"v\":\"tmp.md\"}}},\"a\":{\"0\":\"s\",\"v\":\"failed to read file\"}},\"t\":{\"0\":\"l\",\"l\":\"text\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"expect\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"binary_to_string\"},\"a\":{\"0\":\"v\",\"l\":\"bytes\"}}},\"a\":{\"0\":\"s\",\"v\":\"not a text file\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"length\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"list\"},\"a\":{\"0\":\"v\",\"l\":\"std\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"tail\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"split\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"string\"},\"a\":{\"0\":\"v\",\"l\":\"std\"}}},\"a\":{\"0\":\"v\",\"l\":\"text\"}},\"a\":{\"0\":\"s\",\"v\":\" \"}}}}}}}",
    )
  let source = editable.from_expression(source)
  let source = projection.focus_at(source, [0])
  #(source, "count words in a file")
}

fn deploy() {
  let assert Ok(source) =
    decode.from_json(
      "{\"0\":\"l\",\"l\":\"files\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"content\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_to_binary\"},\"a\":{\"0\":\"s\",\"v\":\"yo!\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"name\"},\"a\":{\"0\":\"s\",\"v\":\"index.html\"}},\"a\":{\"0\":\"u\"}}}},\"a\":{\"0\":\"ta\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Netlify.DeploySite\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"site\"},\"a\":{\"0\":\"s\",\"v\":\"4b271125-3f12-40a9-b4bc-ccf5e82879dd\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"files\"},\"a\":{\"0\":\"v\",\"l\":\"files\"}},\"a\":{\"0\":\"u\"}}}}}",
    )
  let source = editable.from_expression(source)
  let source = projection.focus_at(source, [0])
  #(source, "deploy a page to netlify")
}

pub fn examples() {
  [catfact_fetch(), wordcount(), deploy(), sunrise()]
}