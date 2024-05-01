import gleam/fetch
import gleam/http
import gleam/http/request
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/string
import harness/impl/http as serve_http
import plinth/node/fs

const api_host = "api.dnsimple.com"

pub fn main() {
  let assert Ok(raw) = fs.read_file_sync(".env")
  let lines = string.split(raw, "\n")
  let secrets = list.filter_map(lines, string.split_once(_, "="))
  let assert Ok(ctrl_client_secret) =
    list.key_find(secrets, "CTRL_CLIENT_SECRET")
  serve_http.do_serve(8081, fn(request) {
    let request = serve_http.to_gleam_request(request)
    case request.path_segments(request) {
      ["v2", "oauth", "access_token"] -> {
        let body =
          string.concat([request.body, "&client_secret=", ctrl_client_secret])

        let request =
          request.new()
          |> request.set_method(http.Post)
          |> request.set_host(api_host)
          |> request.set_path(request.path)
          |> request.prepend_header(
            "content-type",
            "application/x-www-form-urlencoded",
          )
          |> request.set_body(body)

        promise.await(fetch.send(request), fn(response) {
          //   let body = string.append("You are being redirected to ", target)
          io.debug(response)

          let assert Ok(response) = response
          promise.map(fetch.read_text_body(response), fn(response) {
            io.debug(response)
            let assert Ok(response) = response
            #(
              response.status,
              array.from_list([
                #("access-control-allow-origin", "*"),
                #("content-type", "application/json"),
              ]),
              <<response.body:utf8>>,
            )
          })
        })
      }
      ["v2", _account_id, "domains"] -> {
        let request =
          request.Request(
            ..request,
            scheme: http.Https,
            host: api_host,
            port: None,
          )
        //   request
        //   |> request.set_host()
        //   |> request.(None)
        promise.await(fetch.send(request), fn(response) {
          let assert Ok(response) = response
          promise.map(fetch.read_text_body(response), fn(response) {
            io.debug(response)
            let assert Ok(response) = response
            #(
              response.status,
              array.from_list([
                #("access-control-allow-origin", "*"),
                #("content-type", "application/json"),
              ]),
              <<response.body:utf8>>,
            )
          })
        })
      }
      _ -> {
        io.debug(#("Some other", request))
        promise.resolve(
          #(
            200,
            array.from_list([
              #("access-control-allow-origin", "*"),
              #("content-type", "application/json"),
            ]),
            <<>>,
          ),
        )
      }
    }
  })
}
