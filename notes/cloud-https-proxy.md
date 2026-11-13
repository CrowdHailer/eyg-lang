---
name: Cloud HTTPS proxy
description: Why the cloud configures Erlang's httpc with the proxy named by HTTPS_PROXY.
date: 2026-11-12
---

Sandboxed environments, such as cloud development containers and many corporate networks,
block direct outbound connections and only allow traffic through an HTTP proxy named by the `HTTPS_PROXY` variable.
Most tools, curl, Node and Python, read that variable. Erlang's `httpc`, which `gleam_httpc` uses, does not.
Without configuration every outbound request from the cloud, to Slack, to LLM providers and from the `Fetch` effect, fails to connect.

`cloud/system.configure_proxy` runs at startup and passes the proxy to `httpc:set_options`.
`localhost` and `127.0.0.1` are excluded so local services, such as the example chat app, are reached directly.
Only https requests are proxied, plain http requests still connect directly.
When `HTTPS_PROXY` is not set nothing changes.
