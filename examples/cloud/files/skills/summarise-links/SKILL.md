---
name: summarise-links
description: How to fetch web pages and summarise them.
---

Fetch a page with the `Fetch` effect, the request is a record:

```eyg
let request = {
  method: GET({}),
  scheme: HTTPS({}),
  host: "example.com",
  port: None({}),
  path: "/",
  query: None({}),
  headers: [],
  body: !string_to_binary("")
}
match perform Fetch(request) {
  Ok(response) -> { !string_from_binary(response.body) }
  Error(reason) -> { Error(reason) }
}
```

Pages are large, return only the title and the first paragraphs of text from your program.
Summarise each page in at most two sentences and post all summaries in one message.
