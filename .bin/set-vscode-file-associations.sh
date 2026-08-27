#!/usr/bin/env bash
# Make VS Code the default app for text/code/config file types on macOS.
#
# Deliberately NOT included (something else is the obvious default):
#   .html .htm .xhtml .xht .xhtm -> Chrome (asserted below)
#   .pdf .ps .eps           -> Preview
#   images/audio/video      -> Preview / QuickTime
#   .storyboard .xib .pbxproj .xcodeproj -> Xcode
#   .command                -> Terminal (it is meant to be executed)
#
# HOW THIS WORKS, and why it is not `duti`
# ----------------------------------------
# LaunchServices resolves an extension one of two ways, and the binding has to
# match or it is silently ignored:
#
#   * concrete UTI  (.pas -> public.pascal-source)  -> resolved by UTI, so the
#     handler must be recorded as LSHandlerContentType.
#   * dynamic UTI   (.conf -> dyn.ah62d4rv4ge80g55sq2) -> no UTI exists, so the
#     handler must be recorded as LSHandlerContentTag (the extension itself).
#
# `duti -s <app> .ext all` only ever writes the *tag* form. For every extension
# backed by a concrete UTI it reports success and changes nothing -- and pushing
# harder (setting viewer/editor/shell roles individually) makes Finder throw a
# modal "open with Code, or keep TextEdit?" confirmation per extension, i.e.
# dozens of dialogs to click. So this script probes each extension's real UTI
# and writes the correct entry straight into the LaunchServices preference file.
# Nothing prompts.
#
# Re-run after macOS/VS Code upgrades if associations get reset.
# Requires: nothing beyond the system Python.

set -u

# macOS only: LaunchServices does not exist elsewhere.
if [ "$(uname)" != Darwin ]; then
  echo "skipping: macOS only" >&2
  exit 0
fi

# LaunchServices stores bundle ids lowercased.
APP="com.microsoft.vscode"
BROWSER="com.google.chrome"

BROWSER_EXTS=(html htm xhtml xht xhtm)
BROWSER_UTIS=(public.html)

# Extensions VS Code lists, whose UTI actually belongs to a real binary format
# owned by another app. Reassigning these would break that app, so leave them:
#   .exs -> com.apple.logic.exs  (Logic/GarageBand sampler instrument)
#   .mts -> AVCHD video          (not TypeScript, to LaunchServices)
#   .dot -> Word template        (not Graphviz)
#   .pot -> PowerPoint template  (not gettext)
SKIP=(exs mts dot pot)

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

export LS_APP="$APP" LS_BROWSER="$BROWSER"
export LS_EXTS="${EXTS[*]}"           LS_UTIS="${UTIS[*]}"
export LS_BROWSER_EXTS="${BROWSER_EXTS[*]}" LS_BROWSER_UTIS="${BROWSER_UTIS[*]}"
export LS_SKIP="${SKIP[*]}"

/usr/bin/python3 <<'PYEOF'
import os, plistlib, pathlib, subprocess, tempfile

APP     = os.environ["LS_APP"]
BROWSER = os.environ["LS_BROWSER"]
exts    = os.environ["LS_EXTS"].split()
utis    = os.environ["LS_UTIS"].split()
bexts   = os.environ["LS_BROWSER_EXTS"].split()
butis   = os.environ["LS_BROWSER_UTIS"].split()
skip    = set(os.environ["LS_SKIP"].split())

def probe(extensions):
    """Map extension -> the UTI LaunchServices actually assigns it."""
    out = {}
    with tempfile.TemporaryDirectory() as d:
        for e in extensions:
            f = pathlib.Path(d, "probe." + e)
            f.touch()
            try:
                u = subprocess.run(
                    ["mdls", "-name", "kMDItemContentType", "-raw", str(f)],
                    capture_output=True, text=True, timeout=10).stdout.strip()
            except subprocess.SubprocessError:
                u = ""
            out[e] = u if u and u != "(null)" else ""
    return out

want = {}   # ("type", uti) | ("tag", ext)  ->  bundle id
def assign(extensions, uti_list, bundle):
    for u in uti_list:
        want[("type", u)] = bundle
    m = probe(extensions)
    for e in extensions:
        if e in skip:
            continue
        u = m.get(e, "")
        # concrete UTI -> bind the UTI; dynamic or unknown -> bind the extension
        if u and not u.startswith("dyn."):
            want[("type", u)] = bundle
        else:
            want[("tag", e)] = bundle

assign(exts, utis, APP)
assign(bexts, butis, BROWSER)      # browser last: it wins any overlap

p = pathlib.Path.home()/"Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
d = plistlib.loads(p.read_bytes()) if p.exists() else {}
handlers = d.setdefault("LSHandlers", [])

def key(entry):
    if "LSHandlerContentType" in entry:
        return ("type", entry["LSHandlerContentType"])
    if "LSHandlerContentTag" in entry:
        return ("tag", entry["LSHandlerContentTag"])
    return None

changed = kept = 0
index = {key(e): e for e in handlers if key(e)}
for k, bundle in sorted(want.items()):
    e = index.get(k)
    if e is not None:
        if e.get("LSHandlerRoleAll") == bundle:
            kept += 1
            continue
        e["LSHandlerRoleAll"] = bundle
    else:
        e = {"LSHandlerRoleAll": bundle,
             "LSHandlerModificationDate": 0,
             "LSHandlerPreferredVersions": {"LSHandlerRoleAll": "-"}}
        if k[0] == "type":
            e["LSHandlerContentType"] = k[1]
        else:
            e["LSHandlerContentTag"] = k[1]
            e["LSHandlerContentTagClass"] = "public.filename-extension"
        handlers.append(e)
        index[k] = e
    changed += 1

p.parent.mkdir(parents=True, exist_ok=True)
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_BINARY))
print(f"{changed} association(s) written, {kept} already correct, "
      f"{len(handlers)} entries total.")
PYEOF

# Reload the LaunchServices daemon and Finder so the new bindings take effect.
killall lsd 2>/dev/null || true
sleep 1
killall Finder 2>/dev/null || true

echo "Done. Open-with bindings reloaded."
