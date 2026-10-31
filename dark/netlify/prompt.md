# Netlify

Follow ../api_clients.md. Implement `dark/netlify/index.eyg` using pinned
`@standard`, `@json`, and `@http`. Use https://open-api.netlify.com/ for
`getCurrentUser`, `listSites`, `listSiteForms`, `listFormSubmissions`, and
`listSiteSubmissions`. Support token configuration and `netlify.connect({})`
through `eyg_packages/spotless/index.eyg` device auth. Preserve submission data
and pagination headers; distinguish HTTP application errors from transport and
protocol errors. Add deterministic tests and runnable forms/submissions scripts.
Run the repository tests and verify the GET operations live using `connect`.
