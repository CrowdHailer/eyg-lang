---
name: Agent branch final commit review
description: Every retained commit reviewed against main ea52e422 and the in-memory cloud scope.
date: 2026-11-13
---

Base: `origin/main` at `ea52e422`. Starting point for this revision: bot
`agent` at `abb3cf16`. The revised history has 61 feature/documentation commits
plus one review and HTML/PDF commit: 62 total. Deployment is commit 3.

Cloud state stays in memory. The intended cluster design has no local JSON store,
SQLite working copies or writable data volume. Replication and all-owner-loss
recovery are not implemented here. Startup files, imports and seed directories
are read-only inputs. Configuration source edits, secrets and users live in actors.

Requested removals and the persistence audit:

| Original commit | Disposition |
| --- | --- |
| `bb22e74a` workspace secret store | Removed the local JSON store and its CLI. Mutable secrets are held with workspace source in memory. |
| `02907612` file/history snapshots | Removed snapshot encoding, writes, restart restoration and storage paths, including now-unused chat serialization. Main’s in-memory roots/history remain. |
| `97b366d4` service feeds and webhooks | Removed feeds, generic service webhook integrations, event logs, consumers and examples. Shared plain event types remain with their first runtime consumer. Chat webhook plumbing remains for WhatsApp. |
| `fcba3557` cloud helpers/example workspace | Removed the public EYG cloud package, its tests and the example workspace. Runtime tests use small local fixtures. |
| `e34ae26c` operator pages | Removed product/admin pages, quick-trigger widgets, checks and routes. Root now reports service status; shell/API remain. |
| `23718651` cloud databases/dataclips | Removed the entire cloud SQLite/dataclip feature and its dependencies, examples and tests. |
| `f0aa7cac` dependent database guides/recordings | Removed the obsolete database workflows and demonstrations. |
| `790dd89d` runtime | Reworked rather than removed: eliminate user JSON, source-file writes, secret-store calls and session snapshot wiring. |
| `adef5f09` deployment | Reworked rather than removed: no /data initialization, copying startup script or volume requirement. |
| `c473d41f` chat/WhatsApp adapters | Moved implementations and runtime wiring after deployment. |

Earlier removals remain: runtime value checking (`f98d41ca`) is folded into
source checking; keyword fields (`d5c0b973`), custom cron parsing (`08f992bf`)
and hub artifact storage (`96065cb8`) are absent. Initial OTel (`4f17fd58`)
stays folded into its first runtime consumer. Main's Clockwork helper, central
serial actor, direct replies, reserved keywords and Pass/Mock gates remain.
Agents are unbounded, with the shared-queue trade-off documented.

No later cloud commit adds a disk store. The remaining filesystem-backed CLI
cache, sandbox, Raspberry Pi and local SQLite features belong to other hosts.
Browser-local artifacts and cloud in-memory artifacts remain; the hub stores none.
The historical event-storming boards are explicitly archival, not a disk-first
implementation plan.

| Commit | Review and simplification decision |
| --- | --- |
| `b43673ce` Extend main’s session actor with source-checked in-memory workspaces | Keep main’s serial actor; fold shared event types, source checking and initial tracing here. Files/history, users, secrets, source edits and artifacts stay in memory. No feeds, public helpers or operator pages. |
| `e25dac4e` Document the in-memory cloud API, web shell and tracing | Retain only API, web-shell and tracing guidance; remove obsolete helper, feed and snapshot workflows. |
| `7f639db8` Build cloud deployment without writable host storage | Ship read-only startup inputs. Remove data-volume initialization; verify boot with a read-only root filesystem. |
| `96b73bd6` Add network secrets as an independent policy package after deployment | Keep the later credential-substitution feature as an independent network_secrets package, with its own tested entry point and no storage backend. |
| `0c91d436` Add example-chat and WhatsApp adapters after deployment | Move actual adapter implementations, wiring, tests and their guide after deployment. Shared input types are already used by runtime tests. |
| `e8861324` Add a howdy and Lustre example chat with channels, threads and reactions | Keep the standalone chat application after deployment. |
| `964dfa87` Extend main’s native adapters after deployment | Extend main’s existing adapters after deployment. Preserve startup triggers; remove dependencies on deleted helper/example tests. |
| `a42c4958` Resolve local language dependencies for query and runtime extensions | Keep after deployment; move former checker-only local dependency changes here. |
| `48b38d49` Add typed query tables with indexed fixed-point evaluation | Keep after deployment; remove keyword-field relaxation and obsolete value-checker adaptations. |
| `0e5c26e5` Plan evaluated query tables as SQLite joins | Keep planner separate from evaluation; consumers follow. |
| `4157554f` Define SQLite effects for statements and query tables | Keep common effect interfaces for local hosts. Update the cloud’s transitive compiler dependency here at first use; do not install a cloud SQLite handler. |
| `d4472232` Record performed effects and expose recorded shell evaluation | Keep combined effect recording and shell API; earlier duplicate API commit stays folded. |
| `07e40ac9` Add portable OTLP export with bounded HTTP transport | Keep portable export separate from the initial span library; preserve current dependency graph. |
| `ec816a3e` Bound interpreter runs and expose resumable reduction slices | Keep resumable evaluation slices; these do not bound cloud agent rounds. |
| `2d47df46` Preserve subsequent stdin bytes when reading CLI prompts | Keep independent stdin correctness fix and subprocess regressions. |
| `d7d2e395` Trace effect execution and profile functions through one CLI lifecycle | Keep shared tracing/profiling lifecycle and cancellation semantics. |
| `c53a3d26` Reuse cached release metadata when resolving packages | Keep cache correctness and no-network lookup behavior. |
| `360c380b` Add portable trajectory archives with verified replay and secret redaction | Keep archive format, verification and redaction as a shared library. |
| `de1cc55b` Record, inspect, replay and upload pinned CLI trajectories | Keep CLI archive consumers with release pinning and upload checks. |
| `eb9b2231` Record retained shell cells with correct lexical binding order | Keep lexical-order fix folded with retained-cell recording. |
| `1c5a8d17` Explain agent execution, abort values and effect policies consistently | Keep shared instructions and Abort semantics; no separate Reject protocol. |
| `2d2456c3` Export Overlay chats in the OpenCode session format | Keep independent OpenCode export format. |
| `45e55a6b` Retain and control browser chats with portable trajectory downloads | Keep browser persistence, policy controls and trajectory downloads. |
| `3c1be283` Keep pinned CLI agent trajectories across turns | Keep multi-turn CLI recording and credential redaction. |
| `6624c794` Add sealed sandbox acquisition, isolated forks and offline evaluation | Keep sealed acquisition and private forks as a distinct authority boundary. |
| `a57cf97c` Bound browser binary summaries and keep the chat input visible | Keep bounded model-facing binary summaries without truncating runtime values. |
| `af39b4e1` Add isolated local artifact workspaces and reusable viewers | Remove all hub publishing/storage/UI/proxy paths; retain local workspaces/viewers and cloud hosting. |
| `9c9e9b01` Unify bounded compiled execution, scoped masks and shallow handlers | Keep interpreter/compiler semantics together; preserve keyword-field restrictions. |
| `21630fb7` Expose a retained typed shell and standalone native host API | Keep typed retained shell and native host API before embedding consumers. |
| `92d4d083` Stream HTTP bodies and retain recorded Overlay frontend sessions | Keep streaming transport and retained frontend state. |
| `676ddd94` Build CLI executables in Gleam and persist verified package responses | Keep executable builds and verified persistent package cache. |
| `9d549fc0` Edit terminal prompts by grapheme and stop recorded agent turns safely | Keep grapheme editing and cancellation as terminal correctness work. |
| `e4df920d` Support portable provider transports and a checked embedded agent | Keep provider protocols and embedded agent; update manifests at this feature boundary. |
| `eaf8205b` Evaluate bounded agent sessions with reusable contexts and offline reports | Keep offline evaluation/context tools; their explicit budgets are independent of cloud execution. |
| `e7f861e1` Expose recorded agents and checked code to EYG scripts | Keep EYG-facing recorded agent API and checked code. |
| `1a496114` Exercise embedded hosts through TodoMVC, Hashi and nginx adapters | Keep real host examples exercising the public embedding boundary. |
| `9b7f1809` Share composable native tool policies across Pi and OpenCode | Keep shared policies and actual Pi/OpenCode dispatcher integrations. |
| `b8e247b5` Inspect sealed trajectories and performance in browser tools | Keep inspection/debugger tools over archives and performance data. |
| `9bf8c7ec` Build and boot a persistent EYG Raspberry Pi image | Keep independent Pi bootable host; not a cloud prerequisite. |
| `e2131a9d` Run recorded Overlay and the BEAM shell through main terminal components | Keep main’s terminal components and adapt recorded agents/BEAM shell. |
| `a19193d0` Validate runtimes, native hosts and local artifact workflows in CI | Add local-artifact checks; CI for future packages now lands with those packages. |
| `57098aa2` Generate typed programs to test analysis and interpreter soundness | Keep property-testing infrastructure and its own CI entry. |
| `f09d99e6` reject record types that name a label twice | Keep independent type-system correctness fix with regressions. |
| `5bc65ce5` cover every runnable program form in soundness search | Keep generator coverage expansion after the semantic fix. |
| `1964f35e` Add guided implementation walkthroughs | Keep implementation walkthroughs for the integrated runtime. |
| `6435ecac` Document agent integration levels and the query design | Keep integration/query design documentation distinct from implementation. |
| `37e42391` Add executable authorization policies and tutorial | Keep executable authorization examples and tutorial. |
| `59bdc1ae` Compare query models and present agent oversight | Keep model comparisons and oversight explanation. |
| `ce8ecac6` Implement SQLite effects in local hosts | Keep CLI/browser SQLite hosts. These add no persistence to packages/cloud. |
| `8d2f2b05` test every example from the datalog in javascript essay | Keep executable query-essay examples. |
| `0b8cec39` Expose compiled JavaScript expressions and preserve record keys | Keep compiler export and record-key correctness change. |
| `dd028739` Load and query a movie database with SQLite | Keep runnable movie database example. |
| `3328b8b9` Document SQLite query resolution and variable syntax tradeoffs | Keep SQLite resolution and variable-syntax trade-offs. |
| `8ea53887` Record the movie query demo from inline facts to SQLite | Keep reproduction material for the movie workflow. |
| `a57b501a` check the query operator is highlighted on the website | Keep focused website query-highlighting regression. |
| `37e52569` add vim syntax highlighting for eyg | Keep editor integration independent of runtime changes. |
| `7e486347` add channel-based authorization and datalog proof trees | Keep proof trees and mocked channel authorization; CI lands here. |
| `b0b58ee7` Add native Zig EYG interpreter, oracle-tested TUI and Git runtime | Keep Zig as an independent merge decision with its own CI and documented oracle/platform limits. |
| `9a5becdc` Add oracle talk slide deck and controlled optimisation measurements | Keep controlled measurement evidence separate from runtime implementation. |
| `5f935715` Explain how the roadmap builds on the agent branch | Update roadmap to remove hub-artifact claims. |
| `38129c4f` Record the event-storming study and cluster-first follow-up | Retain historical study evidence; replace the disk-first rollout with current in-memory constraints and open cluster questions. |
| Final review / presentation | Current work list, per-commit audit and ten-slide HTML/PDF. |

Validation for this revision:

- Deployment checkpoint: strict build, 110 cloud tests and 87 EYG tests with its checkout-built CLI. Docker build, read-only boot, HTTP 200 at `/`, expected 401 at `/api/me`, and no container filesystem changes.
- Network secrets: 111 cloud tests and 94 repository EYG tests.
- Chat/WhatsApp checkpoint: 120 cloud tests; native-adapter checkpoint: 138.
- Final source: strict cloud build, 138 cloud tests, 198 CLI tests and 260 repository-root EYG tests with the checkout-built CLI.
- New regression coverage checks in-memory source/secret updates, workspace isolation, unchanged startup files, private session files across commands and fresh owners without disk restoration.
- Range comparison reviews every retained patch. Independent later features retain their prior implementation; compiler dependency metadata lands with its first consumer. Final history cleanup preserves the tested tree.

The full branch has not been merged or deployed to production. The example login
still requires front-door authentication. The work does not claim cluster
replication or recovery guarantees.
