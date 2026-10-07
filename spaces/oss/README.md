# OSS

Work with my personal open source projects

## Kagi search client

`kagi.eyg` is a client for the [Kagi Search API](https://kagi.com/api/docs)
v1 search endpoint, `POST https://kagi.com/api/v1/search`. Request bodies
are JSON encoded with the `@json` package and requests built with
`@standard.http`.

### Use

Search returns every collection, or an error:

```eyg
let kagi = import "./kagi.eyg"

match kagi.search("kagi search api", kagi.defaults) {
  Ok(response) -> {
    // response.search, images, videos, news and podcasts are lists of
    // results; each result has url and title, with optional snippet, time
    // and image fields. Absent collections are [].
    response
  }
  Error(reason) -> { reason }
}
```

For just the web results, `search_results` returns a list of
`{title, url, snippet}` records where snippet is `Some(String)` or `None({})`:

```eyg
match kagi.search_results("steve jobs", kagi.defaults) {
  Ok(results) -> { results }
  Error(reason) -> { reason }
}
```

Options spread over `kagi.defaults`, see `kagi.eyg` for the full list:

```eyg
{limit: Some(5), ..kagi.defaults}
```

`search` returns `Error` for a transport failure, a non-200 response (with
the formatted Kagi error reason) or a 200 response that does not decode.

### Response decoding

Required fields (`meta`, plus `url` and `title` on results) must be present
with the documented types. Optional fields decode as follows:

- an absent field, or a `null` value, decodes to `None({})`
- a present value of the wrong type fails the whole decode with
  `Error("invalid response body: ...")`

A malformed response is therefore never reported as a successful empty
response; regression tests in `kagi_test.eyg` cover this distinction.

### Authentication

The client carries no credentials. `.overlay.eyg` loads the Kagi API key
from `.env.eyg` (git-ignored) and, through `kagi_policy.eyg`, attaches it
as a bearer token to fetch requests for `kagi.com` and `api.kagi.com`
only. Requests to any other host pass through the base policy unchanged.

### Tests

`kagi_test.eyg` holds the suite, written with the local `aok` package. All
HTTP responses are fixtures, so the suite runs without network access.

From the workspace root, print a per-test PASS/FAIL report:

```eyg
let aok = import "./aok/index.eyg"
aok.all(import "./kagi_test.eyg")
```

`aok.run_all` returns the outcomes without printing, and
`aok.debug(tests, "test name")` runs a single test with a source-located
stack trace.

`test.eyg` aggregates every suite into one flattened list of `{name, test}`
records:

```eyg
@standard.list.flatten([
  import "kagi_test.eyg"
])
```

so the whole workspace suite can be run at once with
`aok.all(import "./test.eyg")`. Add new suites to the list in `test.eyg`.
