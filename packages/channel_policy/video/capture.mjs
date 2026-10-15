// Run from anywhere with `bun video/capture.mjs`, after `gleam build`.
// Creates real commits only in a fresh temporary demo repository.
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { capture } from "../build/dev/javascript/channel_policy/channel_policy/video_demo.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const pkg = resolve(here, "..");
process.chdir(pkg);
const output = resolve(here, "output");
mkdirSync(output, { recursive: true });
const sandbox = mkdtempSync(resolve(tmpdir(), "channel-policy-video-"));
const transcript = [];
const env = {
  ...process.env,
  GIT_AUTHOR_NAME: "Ada (local video demo)",
  GIT_AUTHOR_EMAIL: "ada@example.invalid",
  GIT_COMMITTER_NAME: "Ada (local video demo)",
  GIT_COMMITTER_EMAIL: "ada@example.invalid",
  GIT_AUTHOR_DATE: "2026-10-08T12:00:00Z",
  GIT_COMMITTER_DATE: "2026-10-08T12:00:00Z",
};
function git(...args) {
  const result = execFileSync("git", args, {
    cwd: sandbox, env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  });
  transcript.push({ command: "git " + args.join(" "), output: result.trim() });
  return result.trim();
}
function reviewBeforeCommit() {
  git("status", "--short");
  git("diff");
  git("diff", "--cached");
  // A newly initialized repository has no log until its first commit.
  try { git("log", "--oneline", "-10"); } catch { /* first commit */ }
}
const source = readFileSync(resolve(pkg, "../../eyg_packages/authorization/rbac.eyg"), "utf8");
const quotaSource = readFileSync(resolve(pkg, "policies/llm_quota.eyg"), "utf8");
const mock = readFileSync(resolve(pkg, "src/channel_policy/mock.gleam"), "utf8");
const grantIds = ["deployment-page", "infra-submitter", "infra-reviewer"];
const grants = grantIds.map(id => {
  const start = mock.indexOf('      policy.Grant(\n        "' + id + '"');
  if (start < 0) throw new Error("Missing policy fixture " + id);
  const end = mock.indexOf("\n      ),", start) + "\n      ),".length;
  return mock.slice(start, end).split("\n").map(line => line.slice(6)).join("\n");
}).join("\n");

git("init", "-b", "main");
mkdirSync(resolve(sandbox, "infra"));
mkdirSync(resolve(sandbox, "policies"));
writeFileSync(resolve(sandbox, "policies/rbac.eyg"), source);
writeFileSync(resolve(sandbox, "infra/main.tf"), 'locals {\n  replicas = 2\n}\n');
git("add", "infra/main.tf", "policies/rbac.eyg");
reviewBeforeCommit();
git("commit", "-m", "Add infrastructure and channel policy fixture");
git("switch", "-c", "ada/scale-workers");
writeFileSync(resolve(sandbox, "infra/main.tf"), 'locals {\n  replicas = 3\n}\n');
const firstDiff = git("diff", "--", "infra/main.tf");
git("add", "infra/main.tf");
reviewBeforeCommit();
const firstCommit = git("commit", "-m", "Scale workers to three replicas");
const head = git("rev-parse", "HEAD");
writeFileSync(resolve(sandbox, "infra/main.tf"), 'locals {\n  replicas = 4\n}\n');
git("add", "infra/main.tf");
reviewBeforeCommit();
const secondCommit = git("commit", "-m", "Scale workers to four replicas");
const nextHead = git("rev-parse", "HEAD");
const captured = capture(head, nextHead, readFileSync(resolve(sandbox, "policies/rbac.eyg"), "utf8"));
function proofTree(tree) {
  return {
    kind: tree.kind,
    title: tree.title,
    fields: Object.fromEntries(tree.fields),
    source: tree.source,
    children: Array.from(tree.children, proofTree),
  };
}
const facts = {
  ...captured,
  page_proof: proofTree(captured.page_proof),
  approved_proofs: Array.from(captured.approved_proofs, proofTree),
  reapproved_proofs: Array.from(captured.reapproved_proofs, proofTree),
  inference_proof: proofTree(captured.inference_proof),
};
const result = {
  description: "Real local Git commits and EYG policy evaluations; mocked Slack/GitHub services; illustrated UI.",
  sandbox, head, nextHead, firstDiff, firstCommit, secondCommit, source, quotaSource, grants, facts, transcript,
};
writeFileSync(resolve(output, "capture.json"), JSON.stringify(result, null, 2) + "\n");
writeFileSync(resolve(output, "proofs.json"), JSON.stringify({
  provenance: "Captured from eyg/interpreter/explain, not authored by the renderer",
  deployments: facts.page_proof,
  pull_request: { head, permissions: facts.approved_proofs },
  updated_pull_request: { head: nextHead, permissions: facts.reapproved_proofs },
  inference_below_limit: facts.inference_proof,
}, null, 2) + "\n");
console.log("Verified passing examples include engine-generated proof trees:",
  [facts.page_proof, ...facts.approved_proofs, ...facts.reapproved_proofs, facts.inference_proof]
    .map(tree => `${tree.title}: ${tree.children.length} premises`).join("\n"));
console.log("Demo commits:", head, nextHead);
console.log("Captured in", resolve(output, "capture.json"));
