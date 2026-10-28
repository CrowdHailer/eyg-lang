---
name: Bedrock Overlay models
description: Use a signed Converse request with tool calls, temporary credentials and recorded token usage.
---

# Bedrock Overlay models

Set `llm` in an [Overlay configuration](../packages/overlay/README.md):

```eyg
let credentials = import ".env.eyg"
{
  provider: Bedrock({
    region: "eu-west-1",
    access_key_id: credentials.access_key_id,
    secret_access_key: credentials.secret_access_key,
    session_token: credentials.session_token
  }),
  model: "your-bedrock-model-id"
}
```

The credentials file returns `{access_key_id, secret_access_key, session_token}`.
Use `None({})` for a long-lived key or `Some(token)` for temporary credentials.
Add the configuration's policy and context as usual, then run
`eyg overlay path/to/.overlay.eyg`.

The adapter calls HTTPS `Converse` in the selected AWS region, signing the body,
model path and headers with SigV4. Choose a model or inference profile with
Converse tool support and grant `bedrock:InvokeModel`. [Converse reference](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html),
[signing reference](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html).

Text and function tools are supported. Neighbouring messages with the same role
are joined; tool results become user content blocks. Image attachments are not
forwarded. The adapter buffers the ordinary JSON response, including when
Overlay asks for streaming; it does not implement the binary ConverseStream
protocol. Invalid or incomplete documents become recorded failures when the
stream closes. Reported input/output tokens are saved in the trajectory.

The signing implementation uses portable Gleam SHA-256 and HMAC on the BEAM,
Node, Bun and browsers. The public web app's provider selector does not expose
AWS credentials; using this provider in a browser host also requires a suitable
network/CORS setup.

## Check without an AWS account

```sh
cd packages/overlay_llm
gleam test
gleam test --target javascript --runtime bun
cd ../gleam_cli
TEMP=/tmp/eyg-cli-snapshots gleam test --runtime bun
cd ../overlay_web
gleam test --runtime bun
```

These checks cover the published AWS signing vector, an independently computed
signature for an encoded model ID with a session token, one-byte UTF-8 response
chunks, malformed documents and configuration decoding. The CLI runs a tool
round trip against a controlled transport, checks the actual result `42`, saves
usage and verifies archive closure and replay. The browser state check verifies
completion, usage and failure handling. These checks do not call live AWS.
