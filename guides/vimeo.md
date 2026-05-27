---
name: vimeo
description: Work with the Vimeo API to manage videos.
---
# Vimeo API Skill

Work with the Vimeo API to manage videos and users.

The Vimeo API is documented at https://developer.vimeo.com/api
Requests to the API should be made using EYG scripts.
You have no access to a Vimeo API token.
Instead, the Vimeo effect with operations should be used.

ALWAYS load the `write-eyg` skill before creating a function.
ALWAYS read the API documentation for the endpoints you will use.
NEVER return dummy or example data. Tell the user you can't write the script if you keep getting errors.
NEVER guess an endpoint.
DONT try to decode JSON. Return the JSON content for the llm to handle.

## Example Usage

```eyg
let get_user_videos = (_) -> {
  let operation = {
    method: GET({}),
    path: "/me/videos",
    query: None({}),
    headers: [],
    body: !string_to_binary("")
  }
  perform Vimeo(operation)
}

let get_video_details = (video_id) -> {
  let operation = {
    method: GET({}),
    path: !string.concat("/videos/", video_id),
    query: None({}),
    headers: [],
    body: !string_to_binary("")
  }
  match perform Vimeo(operation) {
    Ok({body: body}) -> {
      match !string_from_binary(body) {
        Ok(body) -> { body }
        Error(_) -> { "bad body" }
      }
    }
    Error(_) -> { "bad request" }
  }
}

{get_user_videos: get_user_videos, get_video_details: get_video_details}
```

## Available Operations

The Vimeo effect supports the following operations:

### GET
Retrieve data from the Vimeo API.

**Parameters:**
- `path`: The API endpoint path (e.g., "/me/videos")
- `query`: Optional query parameters (as a record or None)
- `headers`: Optional headers (as a list of tuples)
- `body`: Empty string converted to binary

### POST
Create or update resources in the Vimeo API.

**Parameters:**
- `path`: The API endpoint path
- `query`: Optional query parameters
- `headers`: Optional headers
- `body`: Request body as binary

### PATCH
Partially update resources in the Vimeo API.

**Parameters:**
- `path`: The API endpoint path
- `query`: Optional query parameters
- `headers`: Optional headers
- `body`: Request body as binary

### DELETE
Remove resources from the Vimeo API.

**Parameters:**
- `path`: The API endpoint path
- `query`: Optional query parameters
- `headers`: Optional headers
- `body`: Empty string converted to binary

## Authentication

Authentication is handled automatically by the Vimeo effect. You don't need to include authorization headers in your operations.