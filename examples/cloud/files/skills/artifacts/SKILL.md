---
name: artifacts
description: How to publish an HTML page as an artifact and share it.
---

Save an HTML page with the `Artifact` effect, it returns the version and a URL to post.

```eyg
perform Artifact({
  name: "plan",
  bundle: [{
    path: "index.html",
    media_type: "text/html",
    content: !string_to_binary("<h1>Plan</h1>")
  }]
})
```

Saving with the same name makes a new version.
An artifact belongs to the channel that made it.
Other channels can only change it after its channel shares it with `perform ShareArtifact("plan")`.
