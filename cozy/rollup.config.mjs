import resolve from "@rollup/plugin-node-resolve";

export default {
  input: "main.mjs",
  output: {
    file: "build/bundle.js",
    format: "cjs",
  },
  plugins: [resolve()],
};
