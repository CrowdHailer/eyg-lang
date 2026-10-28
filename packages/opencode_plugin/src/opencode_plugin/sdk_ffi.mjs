import { asSchema, jsonSchema, tool } from "ai";
import { tool as pluginTool } from "@opencode-ai/plugin";
export const schema = async input => await asSchema(input).jsonSchema;
export { jsonSchema, tool };
export const stringSchema = () => pluginTool.schema.string();
export { createOpencodeClient } from "@opencode-ai/sdk/client";
