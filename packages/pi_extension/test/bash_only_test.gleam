import pi_extension/bash_only

pub fn shell_syntax_cannot_append_commands_or_expand_arguments_test() {
  assert bash_only.allowed("eyg run -c 'perform StandardOut(\"a;b\")'")
  assert bash_only.allowed("eyg run -c 'let x = 1\nx'")
  assert !bash_only.allowed("curl example.com")
  assert !bash_only.allowed("eyg run -c '42' && curl example.com")
  assert !bash_only.allowed("eyg run -c \"$(curl example.com)\"")
  assert !bash_only.allowed("eyg run -c '42'\ncurl example.com")
  assert !bash_only.allowed("eyg run -c \\' ; curl example.com")
  assert !bash_only.allowed("eyg run -c 'unfinished")
}
