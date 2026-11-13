---
name: EYG cloud compared with IFTTT
description: How EYG cloud and IFTTT differ, and which to choose.
---

# EYG cloud and IFTTT

IFTTT connects services with applets: if this happens, then do that.

| | EYG cloud | IFTTT |
| --- | --- | --- |
| Triggers | Pure EYG functions over any event field | Choose a trigger from a service, with fields to fill |
| Actions | EYG scripts with the channel's effects, agents through `Delegate` | Choose an action from a service |
| Hosting | Your own server | IFTTT's cloud |

## Human agency

Applets are as expressive as the options a service exposes. An EYG trigger is a function, so the condition can be anything you can write, and it cannot do anything until its script passes the channel's policy.

## Choose IFTTT when

- You want simple consumer automations between popular services.

## Choose EYG cloud when

- Your trigger needs logic, for example only when an account has posted before, using the event log.

Comparisons describe each product as its public documentation does at the time of writing, check it for changes.
See [all comparisons](./README.md).
