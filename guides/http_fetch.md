---
name: http fetch
description: Create and dispatch HTTP requests.
---
# Fetch resources via HTTP

HTTP functionality is build into the standard package.
The package separates building requests from sending them to a server.
A client should create pure functions for building requests for each server operation.


Example 1. fetching a page from the bbc.

```
let http = @standard.http
let result = @standard.result

let get_page = (path) -> {
  let request = http.get("bbc.co.uk")
  http.path(request, path)
}

// used to fetch the homepage
let response = result.expect(http.send(get_page("/")), "failed to fetch from BBC")
```

Example 2. Posting JSON to an example API.
NOTE http.send expects the body to be a binary, as JSON is a string it needs converting.

```
let http = @standard.http
let string = @standard.string
let result = @standard.result

let post_to_example = (path, body) -> {
  let request = http.post("example.com")
  let request = http.path(request, path)
  let request = http.header(request, "content-type", "application/json")
  let request = http.body(request, string.to_binary(body))
}

let response = result.expect(http.send(post_to_example("/comment", "EYG is great!")), "failed to submit comment")
```

All the builder functions create requests that use https.