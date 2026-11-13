import cloud/discord/api/client
import cloud/discord/api/operations
import cloud/discord/api/schema
import gleam/http
import gleam/http/request
import gleam/http/response
import gleeunit/should
import midas/continuation
import midas/effect

pub fn guild_metadata_test() {
  let context =
    client.Context(token: "test-token", fetch: fn(req) {
      req.method |> should.equal(http.Get)
      req.host |> should.equal("discord.com")
      req.path |> should.equal("/api/v10/guilds/123456789012345678")
      request.get_header(req, "authorization")
      |> should.equal(Ok("Bot test-token"))
      continuation.return(Ok(
        response.new(200)
        |> response.set_body(<<
          "{\"id\":\"123456789012345678\",\"name\":\"EYG server\",\"owner_id\":\"987\"}":utf8,
        >>),
      ))
    })
  client.guild(context, "123456789012345678")(fn(x) { x })
  |> should.equal(Ok(schema.Guild("123456789012345678", "EYG server")))
}

pub fn guild_api_failure_test() {
  let context =
    client.Context(token: "test-token", fetch: fn(_) {
      continuation.return(Ok(
        response.new(403)
        |> response.set_body(<<
          "{\"code\":50001,\"message\":\"Missing Access\"}":utf8,
        >>),
      ))
    })
  client.guild(context, "123")(fn(x) { x })
  |> should.equal(
    Error(
      client.ApiFailure(
        operations.DiscordError(schema.ApiError(50_001, "Missing Access")),
      ),
    ),
  )
}

pub fn guild_missing_name_test() {
  let context =
    client.Context(token: "test-token", fetch: fn(_) {
      continuation.return(Ok(
        response.new(200)
        |> response.set_body(<<"{\"id\":\"123\"}":utf8>>),
      ))
    })
  let assert Error(client.InvalidResponse(_)) =
    client.guild(context, "123")(fn(x) { x })
}

pub fn guild_network_failure_test() {
  let context =
    client.Context(token: "test-token", fetch: fn(_) {
      continuation.return(Error(effect.NetworkError("unavailable")))
    })
  client.guild(context, "123")(fn(x) { x })
  |> should.equal(
    Error(client.RequestFailed(effect.NetworkError("unavailable"))),
  )
}
