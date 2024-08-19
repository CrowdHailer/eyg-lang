#!/usr/bin/env node

import * as fs from "fs";
import { exec, native, Record } from "./src/index.mjs";

const input = process.stdin.isTTY ? "" : fs.readFileSync(process.stdin.fd, 'utf-8');
const source = JSON.parse(input)

const extrinsic = {
  Log(message) {
    console.log(message);
    return Record()
  }
}
const value = await exec(source, extrinsic)

console.log(native(value));



