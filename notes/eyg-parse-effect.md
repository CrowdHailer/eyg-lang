---
name: EYG parse effect
description: Design notes for the EYGParse effect and flat AST representation.
date: 2026-06-02
---

This effect was added as a performance optimisation.
EYG doesn't yet have low enough binary access to implement an efficient parser.
Exposing an `EYGParse` effect allows reuse of the host parser.

Future work should remove this effect as implementing a native parser becomes more feasible.
