import api_test
import cloud/catalog
import cloud/templates
import cloud/web
import gleam/http/request
import gleam/list
import gleam/string
import gleeunit/should
import howdy/testing

pub fn documentation_and_subdomain_test() {
  let #(service, _) = api_test.setup()
  let app = web.app(service, "eyg.cloud")
  let assert Ok(template) = templates.get("health-check")
  catalog.create(service.catalog, "health", template.files) |> should.be_ok
  let response =
    testing.get("/")
    |> request.set_host("health.eyg.cloud")
    |> testing.send(app)
  response.status |> should.equal(200)
  testing.text(response) |> should.equal("healthy\n")
  list.each(["concepts", "api", "getting-started", "templates"], fn(topic) {
    let response = testing.get("/docs/" <> topic) |> testing.send(app)
    response.status |> should.equal(200)
    let text = testing.text(response)
    string.contains(text, "Dashboard") |> should.be_true
  })
}
