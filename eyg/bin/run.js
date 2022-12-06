#!/usr/bin/env node

import * as cli from "../build/dev/javascript/eyg/cli.mjs";
const [_1, _2, ...args] = process.argv;
cli.run(args);
