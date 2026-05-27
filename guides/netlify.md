---
name: netlify
description: Work with the Netlify API to manage sites and deployments.
---

The Netlify API is documented at https://docs.netlify.com/llms.txt
Requests to the API should be made using EYG scripts.
You have no access to a Netlify API token.
Instead, the Netlify effect with operations should be used.

ALWAYS load the `write-eyg` skill before creating a function.
ALWAYS read the API documentation for the endpoints you will use.
NEVER return dummy or example data. Tell the user you can't write the script if you keep getting errors.
NEVER guess an endpoint.

For example:

```eyg
let list_sites = (_) -> {
  let operation = {
    method: GET({}),
    path: "/api/v1/sites",
    query: None({}),
    headers: [],
    body: !string_to_binary("")
  }
  perform Netlify(operation)
}
let list_deployments = (_) -> {
  let operation = {
    method: GET({}),
    path: "/api/v1/deploys",
    query: None({}),
    headers: [],
    body: !string_to_binary("")
  }
  match perform Netlify(operation) {
    Ok({body: body}) -> {
      match !string_from_binary(body) {
        Ok(body) -> { body }
        Error(_) -> { "bad body" }
      }
    }
    Error(_) -> { "bad request" }
  }
}
{list_sites: list_sites, list_deployments: list_deployments}
```