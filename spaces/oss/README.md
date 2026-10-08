# OSS

The context layer for my open source projects.
My open source projects include:

- The [EYG language](https://eyg.run) for building safe scripts with managed side effects and sound type inference.
- Many Gleam libraries both on my [personal account](https://github.com/crowdhailer) and the [midas](https://github.com/midas-framework) account.
- My [personal website](https://petersaxton.uk/) and [techical blog](https://crowdhailer.me/)
- The [Gleam Weekly newsletter](https://gleamweekly.com/) and [Gleam Gathering](https://gleamgathering.com/)


## Authorization

DO NOT add authorization headers to requests, the fetch policy will add the required credentials for supported services.

supported services:

- api.hetzner.cloud
- api.kapi.com and kagi.com

For other services use the [spotless.run](https://spotless.run/llms.txt) service includes:

- netlify
- github

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
