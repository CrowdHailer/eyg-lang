import cloud/channel
import cloud/native_input as input
import cloud/plugins/whatsapp
import cloud/webhook
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/option.{None, Some}
import gleam/string
import simplifile

const config =
  whatsapp.Config(
    token: "t0ken",
    phone_number_id: "106540352242922",
    app_secret: "s3cret",
    verify_token: "verify-me",
  )

fn fixture(name) {
  let assert Ok(body) =
    simplifile.read("test/fixtures/whatsapp/" <> name <> ".json")
  body
}

fn sign(body) {
  let hex =
    crypto.hmac(<<body:utf8>>, crypto.Sha256, <<"s3cret":utf8>>)
    |> bit_array.base16_encode
    |> string.lowercase
  "sha256=" <> hex
}

fn delivery(body, signature) {
  webhook.Request(http.Post, [#("x-hub-signature-256", signature)], [], body)
}

pub fn subscription_is_verified_with_the_verify_token_test() {
  let query = fn(token) {
    [
      #("hub.mode", "subscribe"),
      #("hub.verify_token", token),
      #("hub.challenge", "1158201444"),
    ]
  }
  let request = fn(token) { webhook.Request(http.Get, [], query(token), "") }
  assert whatsapp.listen(config, request("verify-me"))
    == Error(webhook.Response(200, "1158201444"))
  assert whatsapp.listen(config, request("wrong"))
    == Error(webhook.Response(403, "verification failed"))
}

pub fn unsigned_deliveries_are_rejected_test() {
  let body = fixture("messages")
  assert whatsapp.listen(config, delivery(body, "sha256=bad"))
    == Error(webhook.Response(401, "invalid signature"))
}

pub fn messages_for_the_phone_number_are_parsed_test() {
  let body = fixture("messages")
  let assert Ok([text, reaction, image]) =
    whatsapp.listen(config, delivery(body, sign(body)))
  assert text.id == "wamid.text1"
  assert text.from == "16505551234"
  assert text.name == Some("Sheena Nelson")
  assert text.timestamp == "1749416383"
  assert text.content == whatsapp.Text("Does it come in another color?")
  assert reaction.content == whatsapp.Reaction("wamid.text1", "📚")
  assert image.content
    == whatsapp.Media(
      "image",
      Some("1003383421387256"),
      "This one",
      Some("image/jpeg"),
    )
  assert string.contains(image.data, "1003383421387256")
}

pub fn status_updates_are_not_messages_test() {
  assert whatsapp.parse(fixture("status"), config.phone_number_id) == Ok([])
}

pub fn native_button_and_interactive_fields_reach_handlers_test() {
  let body =
    "{\"entry\":[{\"changes\":[{\"field\":\"messages\",\"value\":{\"metadata\":{\"phone_number_id\":\"106540352242922\"},\"messages\":[{\"id\":\"button\",\"from\":\"1\",\"type\":\"button\",\"context\":{\"id\":\"root\"},\"button\":{\"text\":\"Choose\",\"payload\":\"private-key\"}},{\"id\":\"choice\",\"from\":\"1\",\"type\":\"interactive\",\"interactive\":{\"type\":\"list_reply\",\"list_reply\":{\"id\":\"sku-42\",\"title\":\"Item\",\"description\":\"The selected item\"}}},{\"id\":\"location\",\"from\":\"1\",\"type\":\"location\",\"location\":{\"latitude\":42}}]}}]}]}"
  let assert Ok([button, choice, location]) =
    whatsapp.parse(body, config.phone_number_id)
  assert button.context == Some("root")
  assert button.content == whatsapp.Button("Choose", "private-key")
  assert choice.content
    == whatsapp.Interactive(
      "list_reply",
      "sku-42",
      "Item",
      Some("The selected item"),
    )
  assert location.content == whatsapp.Other("location")
  assert string.contains(location.data, "latitude")
  let #(events, _) =
    whatsapp.receive(whatsapp.new_store(), [button, choice, location])
  let assert [button, choice, location] = events
  let button = input.event(button, "WhatsAppMessage", whatsapp.input_type())
  let choice = input.event(choice, "WhatsAppMessage", whatsapp.input_type())
  let _ = input.event(location, "WhatsAppMessage", whatsapp.input_type())
  let assert v.Tagged("Button", content) =
    input.field(input.field(button, "message"), "content")
  assert input.text(content, "payload") == "private-key"
  let assert v.Tagged("Interactive", content) =
    input.field(input.field(choice, "message"), "content")
  assert input.text(content, "id") == "sku-42"
}

pub fn messages_are_posted_and_reactions_name_their_message_test() {
  let body = fixture("messages")
  let assert Ok(incoming) = whatsapp.parse(body, config.phone_number_id)
  let #(events, store) = whatsapp.receive(whatsapp.new_store(), incoming)
  let assert [posted, reacted, _image] = events
  assert posted.conversation
    == channel.Conversation("whatsapp", "16505551234", None)
  let posted = input.event(posted, "WhatsAppMessage", whatsapp.input_type())
  let reacted = input.event(reacted, "WhatsAppMessage", whatsapp.input_type())
  assert input.text(input.field(posted, "message"), "from") == "16505551234"
  assert input.field(reacted, "referenced")
    == v.Tagged("Some", input.field(posted, "message"))
  let assert v.Tagged("Reaction", reaction) =
    input.field(input.field(reacted, "message"), "content")
  assert input.text(reaction, "emoji") == "📚"
  // WhatsApp redelivers when a delivery is not acknowledged.
  let #(events, _) = whatsapp.receive(store, incoming)
  assert events == []
}

pub fn removed_reactions_are_not_reported_test() {
  let incoming = [
    whatsapp.Incoming(
      "wamid.r",
      "1",
      None,
      whatsapp.Reaction("wamid.x", ""),
      "",
      None,
      "{}",
    ),
  ]
  let #(events, _) = whatsapp.receive(whatsapp.new_store(), incoming)
  assert events == []
}

pub fn replies_quote_the_message_test() {
  let request =
    whatsapp.message_request(config, "16505551234", "hi", Some("wamid.text1"))
  assert request.method == http.Post
  assert request.host == "graph.facebook.com"
  assert string.ends_with(request.path, "/106540352242922/messages")
  assert request.headers |> list_has(#("authorization", "Bearer t0ken"))
  assert string.contains(
    request.body,
    "\"context\":{\"message_id\":\"wamid.text1\"}",
  )
  let request = whatsapp.message_request(config, "16505551234", "hi", None)
  assert !string.contains(request.body, "context")
}

fn list_has(list, item) {
  case list {
    [] -> False
    [first, ..rest] -> first == item || list_has(rest, item)
  }
}

pub fn long_posts_are_sent_in_parts_test() {
  assert whatsapp.chunks("abcdefg", 3) == ["abc", "def", "g"]
  assert whatsapp.chunks("abc", 3) == ["abc"]
}
