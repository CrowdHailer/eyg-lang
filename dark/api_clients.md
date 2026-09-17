# Writing API client

Follow this guide when writing API clients.

- Use `@http`, `@json` and `@standard` as required.
- Define operations and make use of `@http.dispatch`
  - Do not use abbreviations or short names
  - Use the names given in documentation
  - Use the operation names if given an OpenAPI spec
- separate network and protocol errors from application errors
  - An application may return `Ok(NotFound({}))` or `Ok(Denied(reason))`
- define a library specific `send` function that deals with considerations that a common to operations
- define a top level function for each required operation, it should take service config as the first argument
- return an object of functions one for each operation.

```eyg
let {string} = @standard
let http = @http
let {operation, origin} = http

let config = {
  origin: orign.https("api.example.com"),
  token: "secret"
}

let send = (config, operation) -> {
  let { token, origin } = config
  let header = { key: "authorization", value: string.append("Bearer ", token) }
  let operation = http.prepend_header(operation, header)
  http.dispatch(operation, origin)
}

let get_user = (config, user_id) -> {
  let path = string.append("/users/", user_id)
  match send(config, operation.get(path)) {
    Ok(response) -> match get_user_response(response) {
      Ok(value)
    }
    Error(reason) -> Error(reason)
  }
}

{
  get_user,
  list_users
}
```