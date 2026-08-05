#!/usr/bin/env bash
# Make VS Code the default app for text/code/config file types on macOS.
#
# Deliberately NOT included (something else is the obvious default):
#   .html .htm .xhtml .xht .xhtm -> browser
#   .pdf .ps .eps           -> Preview
#   images/audio/video      -> Preview / QuickTime
#   .storyboard .xib .pbxproj .xcodeproj -> Xcode
#   .command                -> Terminal (it is meant to be executed)
#
# Re-run after macOS/VS Code upgrades if associations get reset.
# Requires: duti  (brew install duti)

set -u

# macOS only: LaunchServices/duti do not exist elsewhere.
if [ "$(uname)" != Darwin ]; then
  echo "skipping: macOS only" >&2
  exit 0
fi

APP="com.microsoft.VSCode"

EXTS=(
  # --- plain text / docs ---
  txt text log nfo readme me
  md markdown mdown mkd mdx rst adoc asciidoc org
  tex latex sty cls bib ltx
  po pot srt vtt sub
  diff patch rej orig
  csv tsv
  svg dot rt
  mdoc mdtext mdtxt mdwn mkdn

  # --- data / config ---
  json jsonc json5 jsonl ndjson geojson
  yaml yml toml ini cfg conf config properties env
  xml xsl xslt xsd dtd rng plist entitlements strings xcconfig
  proto thrift avsc graphql gql
  hcl tf tfvars tfstate nomad
  cue kdl ron
  editorconfig gitignore gitattributes gitconfig gitmodules
  npmrc nvmrc babelrc eslintrc prettierrc dockerignore
  bowerrc jscsrc jshintrc eyaml eyml
  wxi wxl wxs xaml csproj

  # --- build / infra ---
  dockerfile containerfile
  mk mak make makefile cmake ninja bzl bazel star just
  gradle sbt cabal nix rego
  spec service socket timer unit
  lock sum

  # --- shell / scripting ---
  sh bash zsh fish ksh csh tcsh profile bashrc zshrc
  bash_login bash_logout zlogin zlogout zprofile zshenv
  ps1 psm1 psd1 bat cmd
  awk sed vim vimrc
  applescript

  # --- python / notebooks ---
  py pyi pyw pyx pxd ipynb requirements

  # --- javascript / typescript / web app source ---
  js mjs cjs jsx ts tsx mts cts
  vue svelte astro
  css scss sass less styl postcss
  hbs handlebars ejs pug jade liquid mustache twig jinja jinja2 j2 njk erb haml slim
  wat wast

  # --- c family ---
  c h i cc cpp cxx c++ hpp hh hxx h++ ipp tpp inl
  m mm cs csx

  # --- jvm ---
  java kt kts scala groovy clj cljs cljc cljx clojure edn

  # --- systems / compiled ---
  go rs swift zig dart nim cr d v vala
  asm s S nasm ll

  # --- other languages ---
  rb rake gemspec podspec ru
  php phtml
  pl pm pod t pl6 pm6 psgi
  lua tl
  r rmd rnw rhistory rprofile
  jl
  ex exs eex heex erl hrl
  hs lhs elm purs
  ml mli fs fsx fsi fsscript
  scm rkt lisp cl el
  f f77 f90 f95 f03 for
  pas pp vb vbs
  sol
  tcl
  sql psql mysql prisma
  ino pde
  sv svh vhd vhdl verilog
  bqn apl k q
  gd gdscript shader hlsl glsl frag vert comp metal wgsl
  cshtml razor jsp aspx asp ascx ctp jshtm
  mel ms
  sml sig
  coffee litcoffee
  moon
  raku rakumod
  bal
  odin
  gleam
  roc
  zsh-theme
)

# UTI-level catch-alls so unknown/extension-less text files land in VS Code too.
UTIS=(
  public.plain-text
  public.source-code
  public.script
  public.shell-script
  public.c-source
  public.c-header
  public.c-plus-plus-source
  public.c-plus-plus-header
  public.objective-c-source
  public.python-script
  public.perl-script
  public.ruby-script
  public.php-script
  public.json
  public.yaml
  public.xml
  public.comma-separated-values-text
  public.tab-separated-values-text
  public.delimited-values-text
  public.utf8-plain-text
  public.utf16-plain-text
  com.apple.property-list
  com.apple.xml-property-list
  com.netscape.javascript-source
  com.apple.log
  com.adobe.edn
  public.svg-image
  org.tug.tex
)

ok=0; fail=0
for ext in "${EXTS[@]}"; do
  if duti -s "$APP" ".$ext" all 2>/dev/null; then ok=$((ok+1)); else
    fail=$((fail+1)); printf 'skip (no UTI): .%s\n' "$ext"
  fi
done
for uti in "${UTIS[@]}"; do
  if duti -s "$APP" "$uti" all 2>/dev/null; then ok=$((ok+1)); else
    fail=$((fail+1)); printf 'skip (no UTI): %s\n' "$uti"
  fi
done

printf '\nSet %d associations to VS Code (%d skipped).\n' "$ok" "$fail"

# Types that belong to something other than VS Code, but had been claimed by
# Antigravity IDE. Reasserted here so a re-run reproduces the full intended state.
duti -s com.google.Chrome .xhtml all 2>/dev/null
duti -s com.google.Chrome .xht   all 2>/dev/null
duti -s com.google.Chrome .xhtm  all 2>/dev/null
if [ -d /Applications/Xcode.app ]; then
  duti -s com.apple.dt.Xcode .xcodeproj   all 2>/dev/null
  duti -s com.apple.dt.Xcode .xcworkspace all 2>/dev/null
fi

# Known gap: .fs (F#) is claimed by VS Code and Antigravity as a legacy doc-type
# with no registered UTI, so duti cannot target it. It resolves to VS Code on its
# own once Antigravity is uninstalled.
