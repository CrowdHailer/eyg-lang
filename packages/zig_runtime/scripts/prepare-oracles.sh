#!/usr/bin/env sh
set -eu
repo_dir=$(git -C "$(dirname -- "$0")/.." rev-parse --show-toplevel)
next_sha=be502aa03df926a8f9df474a0a7fe16c8fb14fbd
real_sha=f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9
mkdir -p "$repo_dir/work"
for ref in "$next_sha" "$real_sha"; do
  if ! git -C "$repo_dir" cat-file -e "$ref^{commit}" 2>/dev/null; then
    git -C "$repo_dir" fetch origin "$ref"
  fi
done
if [ ! -e "$repo_dir/work/oracle-next-tui/.git" ]; then
  git -C "$repo_dir" worktree add --detach work/oracle-next-tui "$next_sha"
fi
if [ ! -e "$repo_dir/work/oracle-real-world/.git" ]; then
  git -C "$repo_dir" worktree add --detach work/oracle-real-world "$real_sha"
fi
test "$(git -C "$repo_dir/work/oracle-next-tui" rev-parse HEAD)" = "$next_sha"
test "$(git -C "$repo_dir/work/oracle-real-world" rev-parse HEAD)" = "$real_sha"
cd "$repo_dir/work/oracle-next-tui/packages/gleam_cli"
gleam build --target javascript --warnings-as-errors
