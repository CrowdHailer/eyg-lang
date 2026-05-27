---
name: github
description: Work with the GitHub API to manage repositories, issues, and other resources.
---

The GitHub API is documented at https://docs.github.com/llms.txt
Requests to the API should be made using EYG scripts.
You have no access to a GitHub API token.
Instead, the GitHub effect with operations should be used.

ALWAYS load the `write-eyg` skill before creating a function.
ALWAYS read the API documentation for the endpoints you will use.
NEVER return dummy or example data. Tell the user you can't write the script if you keep getting errors.
NEVER guess an endpoint.

For example:

```eyg
let list_repositories = (_) -> {
  let operation = {
    method: GET({}),
    path: "/user/repos",
    query: None({}),
    headers: [],
    body: !string_to_binary("")
  }
  perform GitHub(operation)
}

let get_article = ({pathname: pathname}) -> {
  let operation = {
    method: GET({}),
    path: "/api/article",
    query: Some({pathname: pathname}),
    headers: [],
    body: !string_to_binary("")
  }
  match perform GitHub(operation) {
    Ok({body: body}) -> {
      match !string_from_binary(body) {
        Ok(body) -> { body }
        Error(_) -> { "bad body" }
      }
    }
    Error(_) -> { "bad request" }
  }
}

{list_repositories: list_repositories, get_article: get_article}
```