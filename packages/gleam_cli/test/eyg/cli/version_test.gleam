import eyg/cli/version

// Only a binary built by bin/compile from a tagged commit has a version.
pub fn unbundled_version_is_dev_test() {
  assert "dev" == version.string()
}
