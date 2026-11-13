import { create, notify, outer_args } from "./opencode_plugin/dispatch.mjs";
import { resources } from "./resources.mjs";
export { notify, outer_args };
export const wrap_tools = create(resources);
