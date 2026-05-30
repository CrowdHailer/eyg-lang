---
name: String iteration performance and lexing
description: Discussion of performance issues with pop_grapheme.
date: 2026-05-30
---

The original [discord discussion](https://discord.com/channels/768594524158427167/1256241016877350994/1256555020493787247).

Using `string.pop_grapheme` for line offset calculations was taking several seconds for ~100 lines of input.
The solution was to switch to a byte_slice approach which resulted in an approximatly 40x speedup.

This [Gist](https://gist.github.com/giacomocavalieri/dcd8646947c52906c276e97fa120940c) describes the approximate solution.
Which was implemented as [faster lexing](https://github.com/CrowdHailer/eyg-lang/commit/bff9309cade89d438d8058356de2f7906631fbdc) here.

The `gleam_parser` version `0.5.1` fixed parsing to support utf8 charachters in comments and string.
It is future work to consider supporting utf8 charachters in labels and names.