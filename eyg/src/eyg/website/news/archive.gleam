import eyg/website/news/edition.{Edition}

pub const published = [
  Edition(
    "2024-08-24",
    "JavaScript interpreter available on npm",
    "
EYG is an intermediate representation for programs that never crash and can run in all kinds of environments.
Running EYG programs in JavaScript environments is now possible using the `eyg-run` package published to [npm](https://www.npmjs.com/package/eyg-run).
This interpreter can be used on [node.js](https://nodejs.org) and in the browser.

## Running programs on node.

EYG programs can be run on node, using npx, as follows:

```json
echo '{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Log\"},\"a\":{\"0\":\"s\",\"v\":\"Hello, World!\"}}' > hello.json
cat hello.json | npx eyg-run
```

The default node runner includes only the `Log` effect.
To implement other external effects, follow the browser instructions.

## Running in the browser.

To run in the browser requires building a runner.
In this example the `Log` effect is handled by the `window.alert` API.

```js
import { exec, Record, native } from \"https://esm.run/eyg-run\";

const extrinsic = {
  Log(message) {
    window.alert(message)
    return (Record())
  }
}

async function run() {
  let source = {\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Log\"},\"a\":{\"0\":\"s\",\"v\":\"Hello, World!\"}}

  let result = await exec(source, extrinsic)
  console.log(native(result))
}
run()
```


## Documentation of the EYG intermediate representation (IR)

Documentation describing the JSON format for EYG programs is now available on github.

[https://github.com/CrowdHailer/eyg-lang/tree/main/ir](https://github.com/CrowdHailer/eyg-lang/tree/main/ir)",
  ),
]
