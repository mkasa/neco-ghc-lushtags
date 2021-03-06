" http://www.haskell.org/ghc/docs/latest/html/users_guide/pragmas.html
let s:pragmas = [
      \ 'ANN',
      \ 'DEPRECATED',
      \ 'INCLUDE',
      \ 'INLINE',
      \ 'INLINABLE',
      \ 'LANGUAGE',
      \ 'LINE',
      \ 'MINIMAL',
      \ 'NOINLINE',
      \ 'NOUNPACK',
      \ 'OPTIONS_GHC',
      \ 'RULES',
      \ 'SOURCE',
      \ 'SPECIALIZE',
      \ 'UNPACK',
      \ 'WARNING',
      \ ]

" todo: channel support
let s:is_async = has('nvim')
" let s:is_async = has('nvim') || (has('job') && has('channel')
"         \                && exists('*job_getchannel')
"         \                && exists('*job_info'))
let s:job_info = {}
let s:max_processes = 5

function! necoghc#boot() abort "{{{
  if exists('s:browse_cache')
    return
  endif

  let s:browse_cache = {}
  call s:ghc_mod_caching_browse('Prelude')

  augroup necoghc
    autocmd!
    autocmd FileType haskell call s:on_haskell()
    autocmd FileType lhaskell call s:on_haskell()
  augroup END

  call s:on_haskell()
endfunction "}}}

function! necoghc#omnifunc(findstart, base) abort "{{{
  if a:findstart
    let l:col = col('.')-1
    if l:col == 0
      return -1
    else
      return necoghc#get_keyword_pos(getline('.')[0 : l:col-1])
    endif
  else
    call necoghc#boot()
    " Redo get_keyword_pos to detect YouCompleteMe.
    let l:col = col('.')-1
    let l:pos = necoghc#get_keyword_pos(getline('.')[0 : l:col-1])
    return necoghc#get_complete_words(l:pos, a:base)
  endif
endfunction "}}}

function! necoghc#get_keyword_pos(cur_text) abort "{{{
  if s:synname() =~# 'Comment'
    return -1
  endif

  let [nothing, just_pos] = s:multiline_import(a:cur_text, 'pos')
  if !nothing
    return just_pos
  endif
  if a:cur_text =~# '^import\>'
    if a:cur_text =~# '(.*,'
      return matchend(a:cur_text, '^.*,\s*')
    endif
    let parp = matchend(a:cur_text, '(\s*')
    return parp > 0 ? parp :
          \ matchend(a:cur_text, '^import\s\+\(qualified\s\+\)\?')
  else
    if s:synname() =~# 'Pragma' && a:cur_text =~# 'OPTIONS_GHC'
      let l:pattern = '-[[:alnum:]-]*$'
    else
      let l:pattern = '\%([[:alpha:]_''][[:alnum:]_''.]*\m\)$'
    endif
    let l:pos = match(a:cur_text, l:pattern)
    if l:pos == -1
      " When the completion method is Vim (or YouCompleteMe?), a:cur_text is
      " '{-# '.
      let l:pos = strlen(a:cur_text)
    endif
    return l:pos
  endif
endfunction "}}}

function! s:word_prefix(dict, keyword, need_prefix_filter) abort "{{{
  let l:len = strlen(a:keyword)
  if strpart(a:dict.word, 0, l:len) ==# a:keyword
    if a:need_prefix_filter
      let a:dict.word = strpart(a:dict.word, l:len)
    endif
    return 1
  else
    return 0
  endif
endfunction "}}}

function! s:to_desc(sym, dict) abort
  let l:desc = '[ghc] '
  if has_key(a:dict, 'kind')
    let l:desc .= printf('%s %s %s', a:dict.kind, a:sym, a:dict.args)
  elseif has_key(a:dict, 'type')
    let l:desc .= printf('%s :: %s', a:sym, a:dict.type)
  else
    let l:desc .= a:sym
  endif
  return l:desc
endfunction

function! necoghc#debug_print_module_list() abort "{{{

endfunction "}}}

function! necoghc#update_current_buffer_completion_keywords_with_lushtags() abort "{{{
  let l:lushtag_result = s:lushtags([expand('%:t')])
  if get(g:, 'necoghc_trace', 0)
    echomsg printf("Lushtag returned %d lines", len(l:lushtag_result))
  endif
  if len(l:lushtag_result) <= 0
    " We got nothing. The buffer contains no functions, typs, etc,
    " or just lashtags aborted due to error
    if !exists('b:necoghc_modules_cache')
      " We need to avoid the 'variable not found' error even lashtags failed
      let b:necoghc_buffer_function_cache = []
      let b:necoghc_buffer_module_cache = []
      let b:necoghc_buffer_typeconst_cache = []
      if get(g:, 'necoghc_trace', 0)
        echomsg printf("Lushtag did not yield a result")
      endif
    endif
    " We keep everything when lushtags failed (or outputs nothing)
    " but we already have cache data. When user adds something to
    " a program, it often breaks the integrity of source code, so
    " the buffer may not compile, which means lushtags just fails.
    " We do not discard the previous result, assuming this senario.
  endif
  let l:module_name = '.'
  let l:llist = []
  let l:lmlist = []
  let l:ltclist = []
  for l:p in l:lushtag_result
    let l:ps = split(l:p, '\t')
    if len(l:ps) < 4
      continue
    endif
    let l:mt = l:ps[3]
    if l:mt ==# 'f'
      if 6 <= len(l:ps)
        call add(l:llist, { 'word': l:ps[0], 'menu': '<fun> ' . l:ps[5][11:-2]})
      else
        call add(l:llist, { 'word': l:ps[0], 'menu': '<fun> (noinfo)'})
      endif
    elseif l:mt ==# 'i'
      let l:addl_info = ''
      if 6 <= len(l:ps)
        let l:modifier = l:ps[5]
        if l:modifier =~# '^signature'
          let l:as_name = l:ps[5][11:-2]
          let l:addl_info = l:addl_info . ' ' . l:as_name
          if 7 <= len(l:ps)
            if l:ps[6] =~# 'access:protected'
              let l:addl_info = l:addl_info . ' (qualified)'
            endif
          endif
          call add(l:lmlist, { 'word': l:as_name, 'menu': '<mod> [' . l:ps[0] . ']' . l:addl_info})
        else
          if l:modifier =~# 'access:protected'
            let l:addl_info = l:addl_info . ' (qualified)'
          endif
        endif
      endif
      call add(l:lmlist, { 'word': l:ps[0], 'menu': '<mod>' . l:addl_info})
    elseif l:mt ==# 'd'
      call add(l:lmlist, { 'word': l:ps[0], 'menu': '<dat>'})
    elseif l:mt ==# 't'
      if 6 <= len(l:ps)
        call add(l:lmlist, { 'word': l:ps[0], 'menu': '<typ> ' . l:ps[5]})
      else
        call add(l:lmlist, { 'word': l:ps[0], 'menu': '<typ> (noinfo)'})
      endif
    elseif l:mt ==# 'n'
      if 6 <= len(l:ps)
        call add(l:lmlist, { 'word': l:ps[0], 'menu': '<nty> ' . l:ps[5]})
      else
        call add(l:lmlist, { 'word': l:ps[0], 'menu': '<nty> (noinfo)'})
      endif
    elseif l:mt ==# 'c'
      if 6 <= len(l:ps)
        call add(l:ltclist, { 'word': l:ps[0], 'menu': '<ctr> ' . l:ps[5]})
      else
        call add(l:ltclist, { 'word': l:ps[0], 'menu': '<ctr> (noinfo)'})
      endif
    elseif l:mt ==# 'F'
      if 6 <= len(l:ps)
        call add(l:llist, { 'word': l:ps[0], 'menu': '<fld> ' . l:ps[5]})
      else
        call add(l:llist, { 'word': l:ps[0], 'menu': '<fld> (noinfo)'})
      endif
    elseif l:mt ==# 'm'
      let l:module_name = l:ps[0]
    elseif l:mt ==# 'e'
      " Nothing to do
    else
      call add(l:llist, { 'word': l:ps[0], 'menu': '<???> '})
    endif
  endfor
  let b:necoghc_buffer_function_cache = l:llist
  let b:necoghc_buffer_module_cache = l:lmlist
  let b:necoghc_buffer_typeconst_cache = l:ltclist
endfunction "}}}

function! necoghc#get_complete_words(cur_keyword_pos, cur_keyword_str) abort "{{{
  if get(g:, 'necoghc_trace', 0)
    echomsg "Completer called"
  endif
  let l:col = col('.')-1
  " HACK: When invoked from Vim, col('.') returns the position returned by the
  " omnifunc in findstart phase.
  if a:cur_keyword_pos == l:col
    " Invoked from Vim.
    let l:cur_keyword_str = a:cur_keyword_str
    let l:need_prefix_filter = 0
    let l:need_filter = 1
  elseif empty(a:cur_keyword_str)
    " Invoked from YouCompleteMe.
    " It doesn't give correct a:base and doesn't filter out prefix.
    let l:cur_keyword_str = getline('.')[a:cur_keyword_pos : l:col-1]
    let l:need_prefix_filter = 1
    let l:need_filter = 1
  else
    " Invoked from neocomplcache.vim or neocomplete.vim.
    " They give correct a:base and doesn't need filter.
    let l:cur_keyword_str = a:cur_keyword_str
    let l:need_prefix_filter = 0
    let l:need_filter = 0
  endif

  let l:list = []
  let l:line = getline('.')[: a:cur_keyword_pos]

  if (&filetype ==# 'lhaskell')
    let l:line = substitute(l:line, '^>[ \t]*', '', 'g')
  endif

  let [nothing, just_list] = s:multiline_import(l:line, 'list')
  if !nothing
    if get(g:, 'necoghc_trace', 0)
      echomsg "Multiline import >>"
    endif
    return s:filter(just_list, l:cur_keyword_str, 0, l:need_filter)
  endif

  if l:line =~# '^import\>.\{-}('
    let l:mod = matchstr(l:line, '^import\s\+\%(qualified\s\+\)\?\zs[^ (]\+')
    if get(g:, 'necoghc_trace', 0)
      echomsg printf("Importing a function from %s", l:mod)
    endif
    for [l:sym, l:dict] in items(necoghc#browse(l:mod))
      call add(l:list, { 'word': l:sym, 'menu': s:to_desc(l:mod . '.' . l:sym, l:dict)})
    endfor
    return s:filter(l:list, l:cur_keyword_str, 0, l:need_filter)
  endif

  let l:syn = s:synname()
  if l:line =~# '^import\>'
    if !exists('s:list_cache')
      call necoghc#caching_all_module_names()
      let s:list_cache = s:necoghc_all_module_name_cache
    endif
    for l:mod in s:list_cache
      call add(l:list, { 'word': l:mod, 'menu': '[ghc] ' . l:mod })
    endfor
  elseif l:syn =~# 'Pragma'
    if l:line[:a:cur_keyword_pos-1] =~# '{-#\s\+$'
      for l:p in s:pragmas
        call add(l:list, { 'word': l:p, 'menu': '[ghc] ' . l:p })
      endfor
    elseif l:line =~# 'LANGUAGE'
      if !exists('s:lang_cache')
        let s:lang_cache = s:ghc_mod(['lang', '-s'])
      endif
      for l:lang in s:lang_cache
        call add(l:list, { 'word': l:lang, 'menu': '[ghc] ' . l:lang })
        call add(l:list, { 'word': 'No' . l:lang, 'menu': '[ghc] No' . l:lang })
      endfor
    elseif l:line =~# 'OPTIONS_GHC'
      if !exists('s:flag_cache')
        let s:flag_cache = s:ghc_mod(['flag', '-s'])
      endif
      for l:flag in s:flag_cache
        call add(l:list, { 'word': l:flag, 'menu': '[ghc] ' . l:flag })
      endfor
    endif
  elseif l:cur_keyword_str =~# '\.'
    " qualified
    let l:idx = matchend(l:cur_keyword_str, '^.*\.')
    let l:qual = l:cur_keyword_str[0 : l:idx-2]
    let l:name = l:cur_keyword_str[l:idx :]
    if get(g:, 'necoghc_trace', 0)
      echomsg "Qualified completion: " . l:qual
    endif
    for [l:mod, l:opts] in items(necoghc#get_modules())
      if l:mod == l:qual || (has_key(l:opts, 'as') && l:opts.as == l:qual)
        if get(g:, 'necoghc_trace', 0)
          echomsg "  Hit module " . l:mod . "{"
        endif
        for [l:sym, l:dict] in items(necoghc#browse(l:mod))
          call add(l:list, { 'word': l:qual . '.' . l:sym, 'menu': s:to_desc(l:mod . '.' . l:sym, l:dict) })
          if get(g:, 'necoghc_trace', 0)
            echomsg "    " . l:sym
          endif
        endfor
        if get(g:, 'necoghc_trace', 0)
          echomsg "  }"
        endif
      endif
    endfor
    if exists('b:necoghc_buffer_function_cache')
      if get(g:, 'necoghc_trace', 0)
        echomsg "  Added a buffer function cache {"
        for l:sym in b:necoghc_buffer_function_cache
          echomsg "    " . l:sym
        endfor
        echomsg "  }"
      endif
      let l:list = l:list + b:necoghc_buffer_module_cache
    endif
  elseif l:cur_keyword_str =~# '^[A-Z]'
    if exists('b:necoghc_buffer_function_cache')
      if get(g:, 'necoghc_trace', 0)
        echomsg "  Added a type const cache {"
        for l:sym in b:necoghc_buffer_typeconst_cache
          echomsg "    " . l:sym
        endfor
        echomsg "  }"
        echomsg "  Added a buffer function cache {"
        for l:sym in b:necoghc_buffer_function_cache
          echomsg "    " . l:sym
        endfor
        echomsg "  }"
      endif
      let l:list = l:list + b:necoghc_buffer_typeconst_cache + b:necoghc_buffer_module_cache
    endif
  else
    if get(g:, 'necoghc_trace', 0)
      echomsg "  Other caess"
    endif
    for [l:mod, l:opts] in items(necoghc#get_modules())
      if !l:opts.qualified || l:opts.export
        for [l:sym, l:dict] in items(necoghc#browse(l:mod))
          call add(l:list, { 'word': l:sym, 'menu': s:to_desc(l:mod . '.' . l:sym, l:dict) })
        endfor
      endif
    endfor
    if !exists('b:necoghc_buffer_function_cache')
      if get(g:, 'necoghc_trace', 0)
        echomsg "  Added a buffer function cache {"
        for l:sym in b:necoghc_buffer_function_cache
          echomsg "    " . l:sym
        endfor
        echomsg "  }"
      endif
      let l:list = l:list + b:necoghc_buffer_typeconst_cache + b:necoghc_buffer_module_cache
      call necoghc#update_current_buffer_completion_keywords_with_lushtags()
    endif
    let l:list = l:list + b:necoghc_buffer_function_cache
  endif

  if get(g:, 'necoghc_trace', 0)
    echomsg "Listing Done"
  endif
  return s:filter(l:list, l:cur_keyword_str, l:need_prefix_filter,
        \         l:need_filter)
endfunction "}}}

" like the following case:
"   import Data.List (all
"                    ,
" returns Maybe pos
function! s:multiline_import(cur_text, type) abort "{{{
  if a:cur_text =~# '^\s\+[[:alpha:],(]'
    let mod = s:dangling_import(getpos('.')[1])
    if mod != ''
      if a:type == 'pos'
        let l:idx = matchend(a:cur_text, '^\s\+\%(\ze\%([[:alpha:]]\|([!#$%&*+./<=>?@\\^|~-]\)\|[,(]\s*\)')
        if l:idx != -1
          return [0, max([matchend(a:cur_text, '^.*,\s*', l:idx), l:idx])]
        else
          return [0, -1]
        endif
      else " 'list'
        let l:list = []
        for [l:sym, l:dict] in items(necoghc#browse(l:mod))
          call add(l:list, { 'word': l:sym, 'menu': s:to_desc(l:mod . '.' . l:sym, l:dict) })
        endfor
        return [0, l:list]
      endif
    endif
  endif
  return [1, 0]
endfunction "}}}

function! necoghc#browse(mod) abort "{{{
  if !has_key(s:browse_cache, a:mod)
    if get(g:, 'necoghc_trace', 0)
      echomsg "    Call ghc_mod_caching_browse"
    endif
    call s:ghc_mod_caching_browse(a:mod)
  else
    if get(g:, 'necoghc_trace', 0)
      echomsg "    Using cache"
    endif
  endif
  return get(s:browse_cache, a:mod, {})
endfunction "}}}

function! s:ghc_mod_caching_browse(mod) abort "{{{
  let l:cmd = ['browse', '-o']
  if get(g:, 'necoghc_enable_detailed_browse')
    let l:cmd += ['-d']
  endif
  " a callback to supply extra parameters to the `browse` command
  " depending on the module name
  if exists('*g:NecoghcExtraBrowseOptions')
    let l:cmd += g:NecoghcExtraBrowseOptions(a:mod)
  endif
  let l:cmd += [a:mod]
  if get(g:, 'necoghc_trace', 0)
    echomsg "    Command: " . join(l:cmd, ' ')
  endif

  if !s:is_async
    if get(g:, 'necoghc_trace', 0)
      echomsg "    calling ghc_mod_caching_async"
    endif
    call s:ghc_mod_caching_async(s:ghc_mod(l:cmd), a:mod)
    return
  endif

  if get(g:, 'necoghc_trace', 0)
    echomsg "    async call..."
  endif
  if len(s:job_info) > s:max_processes
        \ || !empty(filter(copy(s:job_info), 'v:val.mod != a:mod'))
    return
  endif

  if has('nvim')
    let l:id = jobstart(['ghc-mod'] + l:cmd, {
          \ 'on_stdout': function('s:job_handler'),
          \ 'on_stderr': function('s:job_handler'),
          \ 'on_exit': function('s:job_handler'),
          \ })
    let s:job_info[l:id] = {
          \ 'candidates': [],
          \ 'eof': 0,
          \ 'status': -1,
          \ 'mod': a:mod,
          \ }
  elseif s:is_async
    try
      " Note: In Windows, job_start() does not work in shellslash.
      let shellslash = 0
      if exists('+shellslash')
        let shellslash = &shellslash
        set noshellslash
      endif
      let l:job = job_start(['ghc-mod'] + l:cmd, {
            \   'callback': function('s:job_handler_vim'),
            \ })
      let l:id = s:channel2id(job_getchannel(l:job))
      let s:job_info[l:id] = {
            \ 'candidates': [],
            \ 'eof': 0,
            \ 'status': -1,
            \ 'mod': a:mod,
            \ 'job': l:job,
            \ }
    finally
      if exists('+shellslash')
        let &shellslash = shellslash
      endif
    endtry
  endif
endfunction "}}}
function! s:job_handler_vim(channel, msg) abort "{{{
  call s:job_handler(s:channel2id(a:channel), a:msg, a:channel)
endfunction"}}}
function! s:job_handler(id, msg, event) abort "{{{
  if !has_key(s:job_info, a:id)
    return
  endif

  let job = s:job_info[a:id]

  if (has('nvim') && a:event ==# 'exit')
        \ || (!has('nvim') && ch_status(a:event) !=# 'open')
    let job.eof = 1
    let job.status = has('nvim') ? a:msg : 0
    if !has('nvim')
      let job.candidates += split(iconv(a:msg, 'char', &encoding), "\n")
    endif
    call s:ghc_mod_caching_async(job.candidates, job.mod)
    call remove(s:job_info, a:id)
    return
  endif

  let lines = has('nvim') ?
        \ map(a:msg, "iconv(v:val, 'char', &encoding)") :
        \ split(iconv(a:msg, 'char', &encoding), "\n")

  let candidates = job.candidates
  if has('nvim') && !empty(lines)
        \ && lines[0] != "\n" && !empty(job.candidates)
    " Join to the previous line
    let candidates[-1] .= lines[0]
    call remove(lines, 0)
  endif

  let candidates += lines
endfunction"}}}

function! s:ghc_mod_caching_async(lines, mod) abort "{{{
  let l:dict = {}
  for l:line in a:lines
    let l:m = matchlist(l:line, '^\(class\|data\|type\|newtype\) \(\S\+\)\( .\+\)\?$')
    if !empty(l:m)
      let l:dict[l:m[2]] = {'kind': l:m[1], 'args': l:m[3][1 :]}
    else
      let l:m = matchlist(l:line, '^\(\S\+\) :: \(.\+\)$')
      if !empty(l:m)
        let l:dict[l:m[1]] = {'type': l:m[2]}
      elseif l:line =~# '^\S\+$'
        let l:dict[l:line] = {}
      else
        " Maybe some error occurred.
        break
      endif
    endif
  endfor
  let s:browse_cache[a:mod] = l:dict
endfunction "}}}

function! s:channel2id(channel) abort "{{{
  return matchstr(a:channel, '\d\+')
endfunction"}}}

function! necoghc#caching_modules() abort "{{{
  call necoghc#caching_all_module_names()
  let b:necoghc_modules_cache = s:extract_modules()
  if s:is_async
    for l:mod in keys(b:necoghc_modules_cache)
      call necoghc#browse(l:mod)
    endfor
  endif
endfunction "}}}

function! necoghc#caching_all_module_names() abort "{{{
  if !exists('s:necoghc_all_module_name_cache')
    let l:cmd = ['ghc-mod-cache', 'modules']
    let l:ret = s:system(l:cmd)
    let l:lines = split(l:ret, '\r\n\|[\r\n]')
    let s:necoghc_all_module_name_cache = filter(l:lines, "v:val !~# '^Warning:'")
  endif
endfunction "}}}

function! necoghc#invalidate_all_module_names() abort "{{{
  if exists('s:necoghc_all_module_name_cache')
    unlet s:necoghc_all_module_name_cache
    if exists('s:list_cache')
      unlet s:list_cache
    endif
    call necoghc#caching_modules()
  endif
endfunction "}}}

function! necoghc#get_modules() abort "{{{
  if !exists('b:necoghc_modules_cache')
    call necoghc#caching_modules()
  endif
  return b:necoghc_modules_cache
endfunction "}}}

function! s:lushtags(cmd) "{{{
  let l:dir = getcwd()
  try
    lcd `=expand('%:p:h')`
    let l:cmd = ['lushtags'] + a:cmd
    let l:ret = s:system(l:cmd)
  catch
    throw v:exception
  finally
    lcd `=l:dir`
  endtry
  let l:lines = split(l:ret, '\r\n\|[\r\n]')
  if empty(l:lines)
    if get(g:, 'necoghc_debug', 0)
      echohl ErrorMsg
      echomsg printf('neco-ghc: lushtags returned nothing: %s', join(l:cmd, ' '))
      echohl None
    endif
    return []
  else
    return l:lines
  endif
endfunction "}}}

function! s:ghc_mod(cmd) abort "{{{
  let l:dir = getcwd()
  try
    " Calling lcd during a call to lcd, i.e. "lcd `=s:get_ghcmod_root()`",
    " results in an error. To circumvent this, we call s:get_ghcmod_root()
    " indirectly.
    let l:ghcmod_dir = s:get_ghcmod_root()
    lcd `=l:ghcmod_dir`
    let l:cmd = ['ghc-mod-cache'] + a:cmd
    let l:ret = s:system(l:cmd)
  finally
    lcd `=l:dir`
  endtry
  let l:lines = split(l:ret, '\r\n\|[\r\n]')
  if get(g:, 'necoghc_trace', 0)
    echomsg '===GHC-MOD==='
    for l:line in l:lines
      echomsg '  ' . l:line
    endfor
    echomsg '============='
  endif
  let l:warnings = filter(copy(l:lines), "v:val =~# '^Warning:'")
  let l:lines = filter(copy(l:lines), "v:val !~# '^Warning:'")
  let l:errors = filter(copy(l:lines), "v:val =~# '^Error:'")

  if empty(l:lines) && get(g:, 'necoghc_debug', 0)
    echohl ErrorMsg
    echomsg printf('neco-ghc: ghc-mod returned nothing: %s', join(l:cmd, ' '))
    echohl None
  endif

  if !empty(l:errors)
    if get(g:, 'necoghc_debug', 0) || get(g:, 'necoghc_trace', 0)
      echohl ErrorMsg
      echomsg printf('neco-ghc: ghc-mod returned error messages: %s', join(l:cmd, ' '))
      for l:line in l:errors
        echomsg l:line
      endfor
      echohl None
    endif
    return []
  endif

  if !empty(l:warnings)
    if get(g:, 'necoghc_debug', 0) || get(g:, 'necoghc_trace', 0)
      echomsg printf('neco-ghc: ghc-mod-cache returned warning messages: %s', join(l:cmd, ' '))
      for l:line in l:warnings
        echomsg l:line
      endfor
    endif
    " return []
  endif

  return l:lines
endfunction "}}}

function! s:extract_modules() abort "{{{
  let l:modules = {'Prelude': {'qualified': 0, 'export': 0}}

  let l:in_module = 0
  let l:line = 1
  while l:line <= line('.')
    let l:str = getline(l:line)
    if l:str =~# '^import\s\+'
      let l:idx = matchend(l:str, '^import\s\+')

      " qualified
      let l:end = matchend(l:str, '^qualified\s\+', l:idx)
      if l:end != -1
        let l:qualified = 1
        let l:idx = l:end
      else
        let l:qualified = 0
      endif

      let l:name = matchstr(l:str, '^[A-Za-z][A-Za-z0-9.]*', l:idx)
      if l:name != ''
        if !has_key(l:modules, l:name)
          let l:modules[l:name] = { 'qualified': 0, 'export': 0 }
        endif
        let l:modules[l:name].qualified = l:modules[l:name].qualified || l:qualified
        let l:idx = matchend(l:str, '^[A-Za-z][A-Za-z0-9.]*\s*', l:idx)

        " as
        let l:end = matchend(l:str, '^as\s\+', l:idx)
        if l:end != -1
          let l:pattern = "\\%([[:alpha:]_'][[:alnum:]_'.]*\\m\\)"
          let l:as = matchstr(l:str, l:pattern, l:end)
          let l:modules[l:name].as = l:as
        elseif match(l:str, '^(', l:idx) != -1
          " exports
          let l:modules[l:name].export = 1
        endif
      endif
    elseif l:in_module || l:str =~# '^\s*$'
      " skip
    elseif l:str =~# '^module\s'
      let l:in_module = 1
    else
      let l:end = matchend(l:str, '^\s*')
      let l:syn = s:synname(l:line, l:end+1)
      if l:syn !~# 'Pragma' && l:syn !~# 'Comment'
        break
      endif
    endif

    if l:line =~# '\<where\>'
      let l:in_module = 0
    endif
    let l:line += 1
  endwhile

  if get(g:, 'necoghc_trace', 0)
    echomsg "Extracted modules:"
    for [l:sym, l:dict] in items(l:modules)
      let l:as_str = ""
      if has_key(l:dict, 'as')
        let l:as_str = " " . l:dict.as
      endif
      if l:dict['qualified']
        echomsg "  qualified " . l:sym . l:as_str
      else
        echomsg "  " . l:sym . l:as_str
      endif
    endfor
  endif
  return l:modules
endfunction "}}}

function! s:dangling_import(n) abort "{{{
  let i = a:n
  while i >= 1
    let line = getline(i)
    if line =~# '^import\>'
      return matchstr(l:line, '^import\s\+\%(qualified\s\+\)\?\zs[^ (]\+')
    elseif line =~# '^\(\s\|--\)'
      let i -=1
    else
      break
    endif
  endwhile
  return 0
endfunction "}}}

function! necoghc#ghc_mod_version() abort "{{{
  let l:ret = s:system(['ghc-mod-cache', 'version'])
  return matchstr(l:ret, '\cghc-mod\%(.exe\)\?\s\+version\s\+\zs\%(\d\+\.\)*\d\+')
endfunction "}}}

function! s:synname(...) abort "{{{
  if a:0 == 2
    let l:line = a:000[0]
    let l:col = a:000[1]
  else
    let l:line = line('.')
    let l:col = col('.') - (mode() ==# 'i' ? 1 : 0)
  endif
  return synIDattr(synID(l:line, l:col, 0), 'name')
endfunction "}}}

function! s:system(list) abort "{{{
  if !exists('s:exists_vimproc')
    try
      call vimproc#version()
      let s:exists_vimproc = 1
    catch
      let s:exists_vimproc = 0
    endtry
  endif
  return s:exists_vimproc && !has('nvim') ?
        \ vimproc#system(a:list) : system(join(a:list, ' '))
endfunction "}}}

function! s:on_haskell() abort "{{{
  call necoghc#caching_modules()
  call necoghc#caching_all_module_names()
  call necoghc#update_current_buffer_completion_keywords_with_lushtags()

  augroup necoghc
    autocmd InsertLeave <buffer> call necoghc#caching_modules()
    autocmd BufWritePost <buffer> call necoghc#update_current_buffer_completion_keywords_with_lushtags()
  augroup END

  command! -buffer -bar -nargs=0 NecoGhcCaching
        \ call necoghc#caching_modules()
endfunction "}}}

" Adapted version of s:find_basedir from
" https://github.com/eagletmt/ghcmod-vim/blob/3e012a5b0b904c5c32eeea39071534d492a64a0f/autoload/ghcmod.vim#L336-L350
function! s:get_ghcmod_root() abort "{{{
  if !exists('b:ghcmod_root')
    let l:dir = getcwd()
    try
      lcd `=fnamemodify(bufname('%'), ':p:h')`
      let b:ghcmod_root =
        \ substitute(s:system(['ghc-mod', 'root']), '\n*$', '', '')
    finally
      lcd `=l:dir`
    endtry
  endif
  return b:ghcmod_root
endfunction "}}}

function! s:filter(list, keyword, need_prefix, needed) abort "{{{
  return a:needed ? filter(a:list,
        \                  's:word_prefix(v:val, a:keyword, a:need_prefix)'
        \                 ) : a:list
endfunction "}}}

" vim: ts=2 sw=2 sts=2 foldmethod=marker
