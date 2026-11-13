---
name: Unbounded cloud agent turns
description: Keep main's completion loop unbounded while all sessions share one executor.
date: 2026-11-13
---

Cloud agent turns have no tool-round limit. They continue until the model returns
without tool calls or a provider request fails, matching main. Delegates run inside
the same turn and have the same behavior.

One actor executes every session serially, so a model that keeps requesting tools
can hold the queue indefinitely. Persistent history trimming limits retained
conversation data; it is not an execution limit. Cancellation or fair scheduling
would be a separate change. The former bounded-loop/provider-proxy commit is
removed; configured channels only add the callback needed to reuse main's loop.
