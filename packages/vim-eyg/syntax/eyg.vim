" Vim syntax for EYG, following the scopes of ../vscode-eyg/syntaxes/eyg.tmLanguage.json.
if exists("b:current_syntax")
  finish
endif

syntax match eygShebang "\%^#!.*$"
syntax match eygComment "//.*$" contains=@Spell
syntax region eygString start=+"+ skip=+\\.+ end=+"+ contains=eygEscape,eygBadEscape
syntax match eygBadEscape "\\." contained
syntax match eygEscape +\\[ntr"\\]+ contained
syntax match eygPackage "@[a-z_][a-z0-9_]*\(:[0-9]\+\(:b[a-z2-7]\+\)\?\)\?\>"
syntax match eygReference "#b[a-z2-7]\+\>"
syntax match eygBuiltin "![a-z_][a-z0-9_]*\>"
syntax keyword eygKeyword let match perform handle deep import
syntax keyword eygQueryKeyword fact rule var resolve
syntax match eygQueryOperator "@\ze{"
syntax match eygNumber "\(\w\)\@<!-\?[0-9]\+\>"
syntax match eygTag "\<[A-Z][A-Za-z0-9_]*\>"
syntax match eygField "\<[a-z_][a-z0-9_]*\>\ze[ \t]*:"
syntax match eygFunction "\<[a-z_][a-z0-9_]*\>\ze[ \t]*("
syntax match eygOperator "->\|\.\.\|=\||"

highlight default link eygShebang Comment
highlight default link eygComment Comment
highlight default link eygString String
highlight default link eygEscape SpecialChar
highlight default link eygBadEscape Error
highlight default link eygPackage Include
highlight default link eygReference Constant
highlight default link eygBuiltin Function
highlight default link eygKeyword Keyword
highlight default link eygQueryKeyword Keyword
highlight default link eygQueryOperator Keyword
highlight default link eygNumber Number
highlight default link eygTag Type
highlight default link eygField Identifier
highlight default link eygFunction Function
highlight default link eygOperator Operator

let b:current_syntax = "eyg"
