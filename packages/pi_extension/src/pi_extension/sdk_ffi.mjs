import { Agent } from "@earendil-works/pi-agent-core";
import { Type } from "typebox";
export const agent = options => new Agent(options);
export const objectSchema = properties => Type.Object(properties);
export const stringSchema = options => Type.String(options);
