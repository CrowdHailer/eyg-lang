# EYG for Vim

Syntax highlighting for EYG, including query literals: `@{`, `fact`, `rule`, `var` and `resolve`.
It follows the scopes of the [VS Code grammar](../vscode-eyg/syntaxes/eyg.tmLanguage.json).

Add this directory to the runtime path, for example in `~/.vimrc`:

```vim
set runtimepath+=/path/to/eyg-lang/packages/vim-eyg
syntax on
```

Test the highlighting with `vim -u NONE -N -es -S test/test.vim`, which exits non zero on failure.
