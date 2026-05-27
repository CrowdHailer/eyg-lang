---
name: tavily
description: Work with the Tavily API to perform web searches and retrieve data.
---
# Tavily API Skill

The Tavily API is documented at https://docs.tavily.com/llms.txt
Requests to the API should be made using EYG scripts.
You have no access to a Tavily API token.
Instead, the Tavily effect with operations should be used.

ALWAYS load the `write-eyg` skill before creating a function.
ALWAYS read the API documentation for the endpoints you will use.
NEVER return dummy or example data. Tell the user you can't write the script if you keep getting errors.
NEVER guess an endpoint.
DONT try to decode JSON. Return the JSON content for the llm to handle.

## Example Usage

```eyg
let {string: string} = @standard

let search_tavily = ({query: query, search_depth: search_depth, max_results: max_results}) -> {
  let operation = {
    method: POST({}),
    path: "/search",
    query: None({}),
    headers: [],
    body: !string_to_binary(
      "{\"query\": \"who is Ada Lovelace?\"}"
    )
  }
  match perform Tavily(operation) {
    Ok({body: body}) -> {
      match string.from_binary(body) {
        Ok(body) -> { body }
        Error(_) -> { "bad body" }
      }
    }
    Error(_) -> { "bad request" }
  }
}



{search_tavily: search_tavily}
```