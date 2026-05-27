---
name: ollama
description: Manage a running ollama instance; start stop and list active models
---

Ollama exposes an API to manage it.
The default port for a locally running ollama instance is 11434.
An index to the Ollama documentation is available at https://docs.ollama.com/llms.txt

When a user requests information about ollama follow the following steps.

1. Check that you can access the server by making a GET to the version endpoint
  `GET http://localhost:11434/api/version`
2. If access is denied check the location of the server with the user.
3. ALWAYS fetch the documentation index from https://docs.ollama.com/llms.txt
4. ALWAYS fetch the documentation that relates to the users query.
