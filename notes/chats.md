---
name: Chats
description: Trade-offs in how a chat is recorded and runs its tool calls.
date: 2026-11-27
---

A chat is a process with its own journal, it is not code in a shell.
How it continues is described in `packages/cloud/src/cloud/chats/chat.gleam`.

The journal records each message, each completion and what each tool call returned, not the requests.
A request holds the llm's credentials and the whole chat so far, the chat is rebuilt from the journal instead.
A completion that was asked for but not recorded is asked for again, it costs a request but has no effect outside the chat.
Completions are streamed to show their text as it arrives, only the whole completion is recorded.

The journal is ordered by a serial id rather than a sequence per chat.
People append messages while the chat's process appends completions and results, a serial never conflicts.
A message sent while tool calls run comes after them in the journal and is added to the llm's chat after their results.

Each tool call runs as the only turn of a shell made for it, see `cloud/calls.gleam`.
The chat does not record which shell a call ran in, the shell records its chat and call and a call has one shell.
A call that was running when the chat stopped is finished in that shell, so its code never runs twice.
Some llms, such as Ollama's, give tool calls no id, those are named by their completion and place so each has its own shell.

The calls of one completion run at the same time, each from the box's latest root.
Their changes are merged by the box's process, a change to a file another call changed first is rejected as a conflict.
A rejected change is the call's result, the llm decides what to do, there is no separate repair loop.

The llm is recorded by name on the chat, a chat can only continue while an llm is configured under that name.
A chat turn that fails is followed in the next message's chat by a message saying why.
