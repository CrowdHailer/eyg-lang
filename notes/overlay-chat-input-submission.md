---
name: Overlay chat input submission
description: Why the chat send button uses the same message as the textarea keyboard handler.
date: 2026-08-11
---

The Overlay chat input is not a form. Enter in the textarea and clicking the
send button both dispatch the application's existing submit message directly.
Using `on_click` keeps submission in one state-machine path and lets the
textarea retain explicit Enter and Shift+Enter handling.

Wrapping the input in a form would introduce a separate browser submit event.
The application would then need to track and prevent that form submission in
addition to its existing keyboard behavior, without gaining any form data or
navigation behavior.
