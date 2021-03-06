# What is neco-ghc-lushtags?

neco-ghc-lushtags is a blazing fast completion plugin
for Haskell using ghc-mod, lushtags, and ghc-mod-cache.

neco-ghc-lushtags is a project forked from
[neco-ghc](https://github.com/eagletmt/neco-ghc),
so most of the functions are derived from neco-ghc.
If you have not used neco-ghc before, please see
the site first.

Anyway, this plugin completes words in the following way:

* pragma
    ![](http://cache.gyazo.com/c922e323be7dbed9aa70b2bac62be45e.png)
* language
    ![](http://cache.gyazo.com/9df4aa3cf06fc07495d6dd67a4d07cc4.png)
* importing a module
    ![](http://cache.gyazo.com/17a8bf08f3a6d5e123346f5f1c74c5f9.png)
* importing a function of a module
    ![](http://cache.gyazo.com/d3698892a40ffb8e4bef970a02198715.png)
* function based on importing modules
    ![](http://cache.gyazo.com/bc168a8aad5f38c6a83b8aa1b0fb14f6.png)
* record accessors
    ![Record accessors](https://www.evernote.com/shard/s75/sh/27ffcd40-65ad-4ebc-893b-e7448077cea4/b27a68078c3f0fa6/res/f051b76a-fe1c-4caf-a10e-24f0d9e3a9da/skitch.png)
* non-standard (local) modules
    ![Non-standard modules](https://www.evernote.com/shard/s75/sh/74fdad24-85ac-47da-9097-1f5842d40992/c7d0c6be3a6d9f82/res/cc91eb57-964c-4d98-bb76-8d22ad21e74f/skitch.png)

neco-ghc-lushtags achieves faster completion using
ghc-mod-cache, which is developed in this project.
I had been frustrated by slow ghc-mod. neco-ghc calls
ghc-mod so often, each of which calls may take a few
seconds but they often blocked vim for more than ten
seconds, which was unacceptable for me. I noticed
that results of ghc-mod could be cached in most cases,
so I developed ghc-mod-cache, which is a simple
wrapper script of ghc-mod. ghc-mod-cache caches the
result of `ghc-mod browse`. neco-ghc-lushtags can
response in less than a second after the result of
ghc-mod is cached.

Another source of frustration was that neco-ghc does
not complete functions in modules not installed.
Let me show an example. Suppose we are working on a
scaffolded Yesod site. neco-ghc does not complete
functions in non-standard modules such as Foundation,
Import, etc. neco-ghc-lushtags can completes such
functions.

neco-ghc was originally implemented by @eagletmt on July 25, 2010, and then
ujihisa added some new features. neco-ghc-lushtags was forked from
neco-ghc by @mkasa on May 31, 2015.

## Install

* Install `stack`.
* Install ghc-mod package by `stack install ghc-mod` or `cabal install ghc-mod`
* Install [modified version of lushtags](https://github.com/mkasa/lushtags).
* Put neco-ghc-lushtags in the plugin directory (You probably use
  Pathogen, NeoBundle, vim-plug, deim.vim, etc).
* Copy bin/ghc-mod-cache into PATH (e.g., ~/.local/bin or ~/.cabal/bin).
* Install yaml/json modules for Python (Optional but highly
  recommended). `pip install pyyaml` and `pip install json` usually work.
  If `pip` is not available, type `easy_install pip` to install `pip`
  first. Python 2.x/3.x are both fine.

Note: If you use ghc-mod 5.4, you should use ghc-mod 5.5+.
Because, ghc-mod 5.5 fixes the rootdir problem.

https://github.com/DanielG/ghc-mod/issues/665

## Usage

neco-ghc-lushtags provides `necoghc#omnifunc` for omni-completion.
I recommend adding the following in your ~/.vim/ftplugin/haskell.vim.

```vim
" Disable haskell-vim omnifunc
let g:haskellmode_completion_ghc = 0
autocmd FileType haskell setlocal omnifunc=necoghc#omnifunc
```

See `:help compl-omni` for details on omni-completion.

### Completion engines
This plugin can be used as a source of
[neocomplete.vim](https://github.com/Shougo/neocomplete.vim) or
[neocomplcache.vim](https://github.com/Shougo/neocomplcache.vim) or
[deoplete.nvim](https://github.com/Shougo/deoplete.nvim).
You can enjoy auto-completions without any specific configuration.

This plugin also should work with [YouCompleteMe](https://github.com/Valloric/YouCompleteMe), but not tested.
To enable auto-completions, you have to add the following setting.

```vim
let g:ycm_semantic_triggers = {'haskell' : ['.']}
```

## Options
### `g:necoghc_enable_detailed_browse`
Default: 0

Show detailed information (type) of symbols.
You can enable it by adding `let g:necoghc_enable_detailed_browse = 1` in your vimrc.
While it is quite useful, it will take longer boot time.

This feature was introduced in ghc-mod 1.11.5.

![](http://cache.gyazo.com/f3d2c097475021615581822eee8cb6fd.png)

### `g:necoghc_debug`
Default: 0

Show error message if ghc-mod command fails.
Usually it will be noisy if `ghc-mod browse Your.Project.Module` always 
fails.
Use this flag only if you have some trouble.

## Troubleshoot

### Q: neco-ghc-lushtags does not work

Check the $PATH variable in vim contains the path to your `ghc-mod` and `stack` command.
Or you can execute `:NecoGhcDiagnostics` command for debug.

## License

[BSD3 License](http://www.opensource.org/licenses/BSD-3-Clause), the same license as ghc-mod
and neco-ghc.
