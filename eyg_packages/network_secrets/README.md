# Network secrets

Load a secret in trusted configuration with `load(name, hosts)`, then install
`env(secrets)` and `fetch(secrets, otherwise)` as the channel's policy gates.
`Env` exposes a hash placeholder. For allowed HTTPS hosts, the fetch gate replaces
placeholders or adds bearer authentication before passing the request to the next
gate. Programs never receive the secret itself.

This package has no storage backend. Cloud supplies secrets from actor-held
configuration state. It is independent of the removed cloud helper package.
Run its tests through the repository's `entry.eyg` suite.
