# EYG on Android

The app runs the same Zig evaluator as the terminal binary. An Expo module calls
a small JNI shim; each native session owns an arena and an explicit interpreter
continuation. Evaluation runs on Kotlin's IO dispatcher. A suspended phone effect
returns to JavaScript, awaits the real Expo API, then resumes Zig with `Ok(value)`
or `Error(message)`. The UI thread does not wait for native evaluation.

## Build

Use Node 24, Java 21 for Gradle, a Java 17 compile toolchain, Zig 0.14.1 and the Android SDK/NDK. Dependencies and exact
versions are recorded in `package-lock.json`; SDK 58 currently uses Android 37,
build tools 37.0.0 and NDK 27.1.12297006.

```sh
cd packages/zig_runtime/android
npm ci
npm test
npm run typecheck
npm run check:capabilities
EXPO_NO_TELEMETRY=1 npm run prebuild -- --no-install
ZIG=/path/to/zig ANDROID_NDK_HOME=/path/to/ndk ./build-runtime.sh
ANDROID_HOME=/path/to/sdk npm run android
```

`build-runtime.sh` builds ARM64 and x86-64 Zig/JNI libraries with 16 KiB page
alignment. Build the native libraries after a clean checkout; they are generated
files and are not committed. `npm run android` needs a connected device or
emulator. Expo Go cannot load this custom native module.

The managed build in this delivery reached Android/Kotlin compilation but could
not assemble an APK: Maven Central redirects React Native's Android artifact to
the following host, which the environment's network policy denied with HTTP 403:

```text
https://repo.reactnative.dev/maven2/com/facebook/react/react-android/0.88.1/react-android-0.88.1-debug.aar
```

Allow `repo.reactnative.dev` in the environment network configuration, then rerun
the Gradle build. No APK or device launch is claimed. Android ARM64 and x86-64
Zig/JNI shared libraries were successfully cross-compiled before this blocker.
`apk-build-blocker.txt` and `validation.json` preserve the observed status.

The installed React Native package also documents a supported source composite
build. An isolated offline attempt substituted ReactAndroid and Hermes projects
under `work/source-build`; it stopped before task graph creation because the
Kotlin 2.2.0 Gradle plugin marker was not cached. Full native third-party sources
are also absent from the npm package. Its normal Boost publisher,
`archives.boost.io`, is outside this environment's enforced allowed hosts, so no
source download or alternate source URL was attempted. Exact upstream source
URLs, local prerequisites and the offline command are recorded in
`source-build-feasibility.json`. The validated app and native artifacts were
preserved throughout this isolated check.

## Phone effects

These effects are necessary because the CLI host has no camera, sensors, or
Android lifecycle. Their shared protocol exposes general host capabilities
instead of introducing a separate effect for each Expo method.

| Effect | Payload | Result inside `Ok` |
|---|---|---|
| `Expo` | `{module, method, args}` | Awaited SDK result |
| `Expo` | `{expo_handle, method, args}` | A native object's method result |
| `Expo` | `{module, method, args, defer: True({})}` | Handle for an operation still running |
| `Expo` | `{expo_handle, method: "$await"}` | Awaited result; consumes the deferred handle |
| `Expo` | `{object, method, get: True({})}` | Property from foreign data; method can be a path list |
| `Expo` | `{module, method, get: True({})}` | SDK constant/property |
| `Expo` | `{module, method, construct: True({}), args}` | Constructed SDK object handle |
| `ExpoView` | `{id, module, component, props, children, ref}` | View ID; mount/update an exported component tree |
| `ExpoView` | `{id, action: "close"}` | Empty result |
| `ExpoNextEvent` | `{timeout_ms}` | Next callback event, or `None({})` |
| `ExpoReply` | `{token, value}` or `{token, error}` | Resolve/reject an async SDK callback |
| `ExpoRelease` | `{expo_handle}` | Empty result; remove/release/close native object |
| `GitQuery` | Native Git request record | Native local Git result; shared with the desktop runtime |

`Expo({method: "$modules"})` lists the registered modules.
`Expo({module: "expo-camera", method: "$members"})` lists available members.
The registry includes 67 Expo feature packages, React Native, and bundled Android
libraries for storage, payments, graphics, native controls, WebView and gestures.
It exposes 101 package entrypoints plus `eyg-widgets` and `eyg-background`. The complete
SDK58 bundled manifest has 124 entries: 90 registered dependency packages and
34 explicit exclusions, with no unclassified entries. `capabilities.json` records
installed versions, decisions, evidence paths and platform/configuration limits.
Registration does not establish that every export or hardware feature works.
React hooks remain React hooks; call imperative SDK functions or mount components.

```eyg
let permissions = perform Expo({
  module: "expo-location", method: "requestForegroundPermissionsAsync", args: []
})
match permissions {
  Ok(permission) -> {
    match permission.granted {
      True(_) -> {
        perform Expo({
          module: "expo-location", method: "getCurrentPositionAsync", args: [{}]
        })
      }
      False(_) -> { Error("Location permission denied") }
    }
  }
  Error(message) -> { Error(message) }
}
```

Permission request methods must be called explicitly. Expo and Android retain
responsibility for permission checks. Unsupported hardware, denied permissions,
missing provider configuration, and unavailable APIs produce `Error` replies.

The value boundary preserves data without adding floating point to EYG:

- Native objects are `{expo_handle: integer}`. Pass the integer as `expo_handle` for
  subsequent method calls, or the whole record inside `args`.
- `{expo_callback: "topic"}` arguments become callbacks. `ExpoNextEvent` returns
  `{topic, args, dropped}`. The queue holds 1,024 events; `dropped` reports overflow.
- Add `expo_return: value` to return declared data synchronously from a callback.
  Add `expo_reply: True({})` instead to return a promise and receive a
  `callback_token` in its event; answer with `ExpoReply({token, value})` or reject
  with `ExpoReply({token, error})`. `expo_timeout_ms` bounds that callback's wait
  (default 30,000 ms; maximum 300,000 ms). These modes cannot be combined.
- When an SDK call waits for its callback, use `defer: True({})`. Receive the
  event, answer its callback token, then call `Expo({expo_handle, method: "$await"})`.
  This lets the EYG program make the callback decision before awaiting the
  original operation.
- Add `expo_sync: "(args) -> { ... }"` for an argument-dependent synchronous EYG
  decision. It receives a list of callback arguments and returns ordinary data.
  This runs an isolated native VM, with no effects, references or captured live
  continuation. `expo_steps` defaults to 1,000 and has a maximum of 10,000 total
  definition-plus-call steps. Limits are 4 MiB allocator capacity, 4,096 source
  bytes, 64 KiB request/output and bounded argument depth/size. `!equal`,
  `!string_split`, `!string_split_once` and `!string_replace` are rejected because
  their recursive/search work runs outside the VM step loop. Scalar comparison,
  string predicates and tag matching remain available. Budget/exhaustion errors
  throw synchronously to the calling SDK. Return modes cannot be combined.
  Source may also be canonical DAG-JSON IR text; use a Select node to read SDK
  fields such as `canAskAgain` that surface EYG identifiers cannot spell.
- Fractional and unsafe integers are `{expo_number: "51.5072"}`. Passing this
  record in `args` restores the JavaScript number, preserving coordinates,
  brightness, battery levels, and sensor readings.
- Typed bytes use `{expo_bytes: [0, 255]}`. Native EYG binary effect payloads are
  also decoded to this byte representation.
- Dates use `{expo_date: "2026-10-28T12:00:00.000Z"}`. Passing the wrapper in
  arguments restores a JavaScript Date; SDK Date results preserve the same value.
- `None({})` crosses to JavaScript `null`; `True({})` and `False({})` become booleans.

EYG field names use lowercase letters and underscores; `handle` is reserved.
The protocol therefore uses `expo_handle` and `timeout_ms`. Existing JavaScript
clients can still use `handle` and `timeoutMs`.
For SDK option names such as `shouldShowBanner`, construct a dictionary with
`{expo_object: [{key: "shouldShowBanner", value: True({})}]}`. Read foreign data
with `Expo({object: data, method: "canAskAgain", get: True({})})`. A method path
list such as `["metadata", "a.b"]` addresses a literal key containing a dot.

An ExpoView with `ref: True({})` emits `view:<id>:ready` with the object handle.
Use that handle for camera capture and similar component methods. Use the same
view ID to update its props. Event handler props accept `expo_callback` records.
Refs are opt-in because many functional UI components do not accept a ref.
The `children` field accepts text and nested `{module, component, props, children}`
descriptors; nested refs may use a string event topic. This permits Compose
Host/Column layouts, provider components and other native component composition.
Trees are limited to 64 levels and reject cycles.
Views belong to the current run: await `ExpoNextEvent` while they are in use;
returning from the program closes its owned view surface.

SDK58 widgets, Material Symbols and Advertising ID have Android support, even
though some package READMEs/native metadata emphasize iOS. `@expo/ui` also exposes
its Jetpack Compose, modifiers and Android community-adapter entrypoints.
`expo-updates` is registered, but remote updates require an updates URL, runtime
configuration and a release build. No remote update service is configured here.

`Expo({module: "eyg-widgets", method: "home", args: [{text: "42 commits"}]})`
returns the declared `EygWidget` provider's object handle. Call its
`updateSnapshot` with `{tree: {component: "Text", children: "Query complete"}}`.
Its precompiled layout accepts nested Text/Column/Row/Box/Image/Icon/Button,
Spacer/Divider/Checkbox/Switch/Card and progress-indicator descriptors with
ordinary JSON props. `notification` returns an Expo custom-notification factory;
call `post` with `{sections: {collapsed: tree, expanded: tree}}` and SDK options.
Updates use the same `{sections: ...}` shape. Permissions still use the normal
notification API. The actual Expo widget compiler is tested; posting and home
screen rendering still require an Android device. Additional widget provider
names and custom native layouts require a rebuild. Widget/Worklets callbacks
cannot capture a runtime EYG continuation; background continuation persistence
is not implemented.

## Durable background entrypoints

`eyg-background` saves EYG task source and JSON metadata in AsyncStorage. Sixteen
TaskManager dispatchers are defined synchronously at bundle initialization;
incoming cold-start events wait for durable definitions to restore. Each event
starts a fresh native session with `input` bound to
`{data, error, execution_info, metadata}`. It can perform ordinary phone/native
effects and retains its result after the JavaScript process exits.

Call `Expo({module: "eyg-background", method: "define", args: [{name: "history",
source: "input.data", result_kind: "task"}]})`. The result's `task_name` is the
stable OS slot name. Register that name through `expo-background-task`,
`expo-location` or another normal Expo scheduling API. Defining source does not
schedule OS work or grant permissions. `result_kind` selects BackgroundTask
(`task`), BackgroundFetch (`fetch`) or raw callback data (`value`) results.

`list`, `get(name)` and `result(name)` inspect saved definitions/results;
`run(name, data)` starts an immediate fresh invocation. `cancel(name)` aborts
an active invocation. `forget(name)` cancels it, unregisters its OS task and
removes its definition/result. Sources are limited to 64 KiB, metadata to 16 KiB,
callback input to 512 KiB and stored result values to 64 KiB. Timeouts default
to 30 seconds, configurable from 1 ms to 300 seconds; Android may impose a
shorter lifetime. Native operations already in progress may finish after cancel,
while the session's sticky cancellation prevents later effects.

Slot/name identities remain reserved after `forget` so delayed OS events cannot
reach a different task. There are at most sixteen historical names. To reclaim
them, forget all definitions and call `resetSlots`; it verifies that no reserved
OS tasks remain, closes the adapter and returns `{restart_required: True({})}`.
Restart the JavaScript process before defining new names. This persistence
stores entrypoint source, not a suspended interpreter continuation. Actual OS
scheduling, restart delivery and battery restrictions require device validation.

`Fetch`, `EYGParse`, `DecodeJSON`, `CreateKey`, `Sign`, `Hash`, and `Inflate` also
use the shared native implementations and the existing CLI effect contracts.
TLS remains verified; Android trusts hashed PEM/DER certificate files from both
`/apex/com.android.conscrypt/cacerts` and `/system/etc/security/cacerts`.

`GitQuery` executes the shared Zig object/pack/index/delta/query implementation
on the native IO dispatcher. A repository must be accessible in the app's Android
sandbox; for example, use Expo FileSystem to place a repository in its document
directory, then evaluate `perform GitQuery({action: "history", repo: "repo", limit: 20})`.
The app sends its document directory as the native session's working directory.
The native request API also accepts an explicit `directory` path or `file://` URI.

Relative `import "module.eyg"` and `.eyg.json` imports are read natively.
Initialization is pure, matching the Gleam oracle. Returned functions retain
their source directory and can perform phone/native effects when invoked by
the caller. Cycles and imports deeper than 64 modules fail explicitly.

Named packages, explicit versions, pinned releases, and content references use
the shared EYG hub cache. It verifies every module's CID against its canonical
bytes before evaluation. Module initialization is pure and requires pinned
dependencies; returned functions run under the caller's normal phone/native
effect handler. The default origin is `https://eyg.run`; `EYG_ORIGIN` or the C ABI
request's `hubOrigin` can configure another origin.

Tests can supply a `packages` fixture object in the native evaluation request.
Fixtures go through the same canonical hash validation and disable live hub
downloads, so missing-package and invalid-CID tests are reproducible.

Closing/cancelling a run removes subscriptions, closes owned objects, clears
views, resolves event waits, and destroys the native arena. A resource returned
after cancellation is disposed as soon as its pending API call completes.
Cancellation does not revoke an OS operation that the underlying Expo API cannot
cancel. Zig's instruction budget bounds runaway EYG programs.
The Kotlin owner retains an active native session until its IO worker finishes.
Closing the app drops ownership without waiting for an in-flight hub/HTTP read;
the last worker releases the arena after the operation returns.
Cancel re-enables editing immediately and isolates a newer run from old results
and view cleanup. It also sets a sticky atomic native cancellation flag. The
current OS operation can finish; checks after IO and before later effects prevent
the interpreter from continuing to another native mutation. The JNI owner signals
cancellation under its ownership lock and frees the pointer only after its last
active call returns.

## Oracle checks

The ordinary JS tests include 2,000 seeded value-boundary cases and lifecycle
checks for subscriptions, denied permissions, native object identity, view
ownership, cancellation, and late API results.

The C ABI can be tested without an Android emulator. This exercises the real Zig
interpreter, session allocation, effect suspension, continuation resume, parser,
UTF-8/JSON bytes, and invalid-reply checks:

```sh
cd packages/zig_runtime
mkdir -p android/work
zig build-lib src/android_bridge.zig -dynamic -lc -O ReleaseFast \
  --name eyg_android_host \
  -femit-bin=android/work/libeyg_android_host.so
python3 android/scripts/test-native.py android/work/libeyg_android_host.so \
  --cases 1000 --oracle --bun bun
```

Prepare the pinned `next-tui` oracle first with `scripts/prepare-oracles.sh`.
`--oracle` compares 1,000 generated programs and 1,000 suspended-effect programs
against the actual Gleam interpreter through the Android C ABI. The generator
uses seed `0x455947`; failure output retains the program and both results.
`python3 android/scripts/test-jni.py --zig zig --jdk /path/to/jdk` also compiles
and runs the actual JNI C shim on a Linux JDK, including 1,000 suspend/resume
calls and UTF-8/embedded-NUL byte round trips.
`python3 android/scripts/test-lifecycle.py --jdk /path/to/jdk` compiles the actual
Kotlin session owner and checks concurrent close/destroy/queued-call schedules
without Android mocks. Use `--gradle-cache /path/to/gradle-user-home` if its cached
Kotlin compiler jars are outside the default Gradle cache. The native suite also covers all hub reference forms,
CID mismatch rejection, pure initialization, native Fetch against a loopback
server, parser/decoder/hash/inflate wiring, and the RFC 8032 Ed25519 test vector.
From the Android directory, `node tests/phone-flow.mjs` runs generated EYG
programs through the real C ABI, production effect dispatcher, and deterministic
SDK fixture. It checks deferred callbacks, replies, foreign field names,
cancellation, and complete ownership cleanup. This is host integration testing;
it does not stand in for device validation.
From `packages/zig_runtime`,
`python3 android/scripts/test-cancel.py android/work/libeyg_android_host.so`
checks a real blocked native HTTP request followed by a Git repository creation.
The positive control creates the repository; cancelling the blocked run prevents
the subsequent mutation and keeps that session cancelled.
`node tests/sync-flow.mjs` exercises argument-dependent callbacks through the
real bounded native evaluator, including forbidden operations and clean memory,
output and step exhaustion. `scripts/test-sync-jni.py` verifies its actual
synchronous JNI entrypoint. `node tests/background-flow.mjs` restarts three real
native processes, restores durable definitions/results, delivers a cold event
before hydration completes, and checks input, cancellation and resource cleanup.

## Verification limits

`validation.json` records the checks actually run. A compiled library, successful
Metro bundle, and host oracle parity do not establish that every phone API works
on real hardware. Device permission flows, camera/media capture, sensors, maps,
notifications, and OS lifecycle/background behavior require device validation.
Durable background source entrypoints restart fresh VMs; serializing an existing
EYG continuation is not implemented. Maps needs a
provider API key; push notifications need project/provider configuration.
Native hub, HTTP, relative filesystem imports, and local Git are implemented and
tested through the host C ABI. Android certificate-directory selection is
cross-compiled; live Android TLS and OS behavior still require device validation.

The Android editor is a native mobile source editor and result view. Terminal
cell rendering remains covered by the desktop TUI oracle suite; no Android
pixel-equivalence claim is made for this different interface.
