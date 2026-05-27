---
name: dnsimple
description: Work with the DNSimple API to manage domains and integrations.
---

The DNSimple API is documented at https://developer.dnsimple.com/llms.txt
Request to the API should be made using EYG scripts.
You have no access to a DNSimple API token.
Instead the DNSimple effect with operations should be used.

ALWAYS load the `write-eyg` skill before creating a function.
ALWAYS read the API documentation for the endpoints you will use.
NEVER return dummy or example data. Tell the user you can't write the script if you keep getting errors.
NEVER guess an endpoint.

For example:

```eyg
let list_accounts = (_) -> {
  let operation = {
    method: GET({}),
    path: "/v2/accounts",
    query: None({}),
    headers: [],
    body: !string_to_binary("")
  }
  perform DNSimple(operation)
}
let list_domains = (_) -> {
  let operation = {
    method: GET({}),
    path: \"TODO fix\",
    query: None({}),
    headers: [],
    body: !string_to_binary(\"\")
  }
  match perform DNSimple(operation) {
    Ok({body: body}) -> {
      match !string_from_binary(body) {
        Ok(body) -> { body }
        Error(_) -> { \"bad body\"}
      }
    }
    Error(_) -> { \"bad request\" }
  }
}
{list_domains: list_domains, list_accounts: list_accounts}
```