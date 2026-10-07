" Run from packages/vim-eyg: vim -u NONE -N -es -S test/test.vim
let s:root = expand('<sfile>:p:h:h')
execute 'set runtimepath+=' . s:root
syntax on
filetype on
execute 'edit ' . s:root . '/test/query.eyg'
let s:expected = [
  \ ['@{', 'eygQueryOperator'], ['\<fact\>', 'eygQueryKeyword'],
  \ ['\<rule\>', 'eygQueryKeyword'], ['\<var\>', 'eygQueryKeyword'],
  \ ['\<resolve\>', 'eygQueryKeyword'], ['\<let\>', 'eygKeyword'],
  \ ['Edge', 'eygTag'], ['"A"', 'eygString'], ['from:', 'eygField'],
  \ ['@std', 'eygPackage'], ['!int_add', 'eygBuiltin'], ['\<1\>', 'eygNumber']]
let s:failures = []
for [s:pattern, s:group] in s:expected
  call cursor(1, 1)
  let s:pos = searchpos(s:pattern, 'cW')
  let s:found = synIDattr(synID(s:pos[0], s:pos[1], 1), 'name')
  if s:found !=# s:group
    call add(s:failures, s:pattern . ' expected ' . s:group . ' got ' . s:found)
  endif
endfor
if empty(s:failures)
  qa!
endif
call writefile(s:failures, '/dev/stderr')
cquit!
