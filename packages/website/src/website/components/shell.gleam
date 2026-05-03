import website/components/snippet

pub type ShellFailure {
  SnippetFailure(snippet.Failure)
  NoMoreHistory
}
