import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{None, Some}
import gleam/time/timestamp
import overlay/llm/sigv4

// The get-vanilla example from the AWS SigV4 test suite.
pub fn get_vanilla_test() {
  let assert Ok(time) = timestamp.parse_rfc3339("2015-08-30T12:36:00Z")
  let request =
    request.new()
    |> request.set_method(http.Get)
    |> request.set_host("example.amazonaws.com")
    |> request.set_path("/")
    |> request.set_body(<<>>)
  let credentials =
    sigv4.Credentials(
      "AKIDEXAMPLE",
      "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
      None,
    )
  let signed = sigv4.sign(request, credentials, "us-east-1", "service", time)
  assert list.key_find(signed.headers, "authorization")
    == Ok(
      "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31",
    )
  assert list.key_find(signed.headers, "x-amz-date") == Ok("20150830T123600Z")
}

pub fn encode_test() {
  assert sigv4.encode("anthropic.claude:0") == "anthropic.claude%3A0"
  assert sigv4.encode("a%3A") == "a%253A"
}

pub fn bedrock_temporary_credentials_test() {
  let assert Ok(time) = timestamp.parse_rfc3339("2015-08-30T12:36:00Z")
  let request =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("bedrock-runtime.eu-west-1.amazonaws.com")
    |> request.set_path("/model/anthropic.claude-sonnet%3A0/converse")
    |> request.set_header("content-type", "application/json")
    |> request.set_body(<<"{}">>)
  let credentials =
    sigv4.Credentials(
      "AKIDEXAMPLE",
      "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
      Some("temporary-token"),
    )
  let signed = sigv4.sign(request, credentials, "eu-west-1", "bedrock", time)
  // OpenSSL HMAC of the explicit canonical request, whose SHA-256 is
  // 9a88d9a60b8906a848ef2b398f6217184c9dead4c9dc1e2bda867667cfc99a5d.
  // The already encoded model colon is %253A in that canonical request.
  assert list.key_find(signed.headers, "authorization")
    == Ok(
      "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/eu-west-1/bedrock/aws4_request, SignedHeaders=content-type;host;x-amz-date;x-amz-security-token, Signature=65d241b99eaa55850ccb2865abeaa5c23322d180edfa6aebb4803f989fef1353",
    )
  assert list.key_find(signed.headers, "x-amz-security-token")
    == Ok("temporary-token")
  let changed =
    request
    |> request.set_body(<<"{\"changed\":true}">>)
    |> sigv4.sign(credentials, "eu-west-1", "bedrock", time)
  assert list.key_find(signed.headers, "authorization")
    != list.key_find(changed.headers, "authorization")
}

pub fn equivalent_headers_and_query_order_test() {
  let assert Ok(time) = timestamp.parse_rfc3339("2015-08-30T12:36:00Z")
  let credentials = sigv4.Credentials("AKID", "secret", None)
  let request =
    request.new()
    |> request.set_host("example.amazonaws.com")
    |> request.set_port(8443)
    |> request.set_body(<<>>)
  let first =
    request
    |> request.set_query([#("key", "z"), #("key", "a"), #("empty", "")])
    |> request.set_header("x-amz-meta-check", "  a\t  b  ")
    |> sigv4.sign(credentials, "eu-west-1", "service", time)
  let second =
    request
    |> request.set_query([#("empty", ""), #("key", "a"), #("key", "z")])
    |> request.set_header("x-amz-meta-check", "a b")
    |> sigv4.sign(credentials, "eu-west-1", "service", time)
  assert list.key_find(first.headers, "authorization")
    == list.key_find(second.headers, "authorization")
  let default_port =
    request
    |> request.set_port(443)
    |> request.set_query([#("empty", ""), #("key", "a"), #("key", "z")])
    |> request.set_header("x-amz-meta-check", "a b")
    |> sigv4.sign(credentials, "eu-west-1", "service", time)
  assert list.key_find(first.headers, "authorization")
    != list.key_find(default_port.headers, "authorization")
}
