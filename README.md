# Workspace Environment & Repository Setup

This repository and home directory workspace are configured with separated repositories, isolated Python management, and consolidated AI developer guidelines.

---

## 📂 Git Repositories & Separation

1. **Dotfiles Repository (`~`)**:
   - Managed using the repository [iot49/dotfiles](https://github.com/iot49/dotfiles).
   - In `~`, git is configured to ignore all files by default (`*` in `.gitignore`).
   - To track new dotfiles, use `git add -f <filename>`.
2. **Git Isolation**:
   - To prevent git commands run in non-git subfolders (e.g. `~/iot/`) from accidentally interacting with the home directory's `.git`, the environment variable `GIT_CEILING_DIRECTORIES="$HOME"` is exported in `~/.zshrc`.
   - Subdirectories that have their own `.git` folders (like `~/iot/track-occupancy/` or `~/iot/py-rocrail/`) function normally as independent repositories.

---

## 🔄 Syncing & New Machine Installation

> [!WARNING]
> **iCloud & Sync Limitations:** The development folder `~/iot` is **not** synced via iCloud. GitHub must be used for syncing your code. Any files that are not pushed to GitHub must be backed up or synced manually.
> 
> **Credentials & Secrets:** Do **not** use secrets files (e.g., `.env`) for credentials. Use **1Password** for managing and storing credentials securely.

### Syncing Dotfiles
Since the home directory `~` is the Git repository itself, syncing is done directly via git commands run in `~`:

1. **Pushing updates from current machine**:
   ```bash
   # Add any new dotfiles (since '*' ignores everything by default, use -f to force)
   git add -f ~/.new_dotfile
   
   # Commit and push
   git commit -am "Update dotfiles"
   git push origin main
   ```
2. **Pulling updates on another machine**:
   ```bash
   cd ~
   git pull
   ```

### Installing on a New Machine (macOS)

Run these in order. Steps 3 and 4 are separate installers on purpose — neither `uv` nor the `code` CLI comes from the Brewfile.

**0. Prerequisites**
```bash
xcode-select --install                       # git and build tools
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**1. Check out the dotfiles into `~`**

The home directory *is* the repository, so clone in place rather than cloning into a subfolder:
```bash
cd ~
git init
git remote add origin https://github.com/iot49/dotfiles.git
git fetch
```
Files that already exist (`.zshrc`, `.gitignore`, `.gitconfig`) will block the checkout. Back them up, then check out:
```bash
mkdir -p ~/dotfiles_backup
for f in .zshrc .gitignore .gitconfig; do [ -e "$HOME/$f" ] && mv "$HOME/$f" ~/dotfiles_backup/; done
git checkout main
```

**2. Install packages**
```bash
brew bundle install --file=~/Brewfile
```
Installs formulae, casks, VS Code extensions, and cargo/npm globals. If an app is already present by hand, adopt it instead of erroring:
```bash
brew install --cask --adopt visual-studio-code
```

**3. Install `uv` and link Python**

`uv` is deliberately **not** a Homebrew package — it is installed standalone so Python is insulated from Homebrew and macOS updates:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh

# default interpreter for ad-hoc use; uv keeps these shims correct across upgrades
uv python install 3.12 --default --force

# pip shims, which uv does not manage -- point at the minor-version directory
# (cpython-3.12-*), NOT the patch one, so they survive `uv python upgrade`
# uv names the platform "macos"/"aarch64", which is NOT what `uname` reports
# (darwin/arm64) -- glob instead of constructing the name, or the links dangle.
MINOR=$(ls -d "$HOME"/.local/share/uv/python/cpython-3.12-*-none | head -1)
ln -sfn "$MINOR/bin/pip" ~/.local/bin/pip
ln -sfn "$MINOR/bin/pip3" ~/.local/bin/pip3
```

**4. Wire up VS Code**

The cask provides the `code` CLI, so the extensions in step 2 install themselves — the cask is listed before the `vscode` entries for exactly that reason. (Only if VS Code was installed by hand do you need Command Palette → *Shell Command: Install 'code' command in PATH*.)

Point macOS at the tracked settings and set file associations:
```bash
VSU="$HOME/Library/Application Support/Code/User"
mkdir -p "$VSU"
for f in settings.json keybindings.json; do
  [ -e "$VSU/$f" ] && [ ! -L "$VSU/$f" ] && mv "$VSU/$f" "$VSU/$f.bak"
  ln -sfn "$HOME/.config/Code/User/$f" "$VSU/$f"
done
~/.bin/set-vscode-file-associations.sh    # no dependencies beyond system Python
```

**5. Enable the 1Password SSH agent**

`.zshrc_Darwin` sets `SSH_AUTH_SOCK` to 1Password's agent socket. Open the 1Password app → *Settings → Developer → Use the SSH agent*. Git and SSH keys are managed there; no key files or `.env` secrets on disk.

**6. Restart the shell**
```bash
exec zsh
```

### Updating an Existing Machine

```bash
cd ~ && git pull
brew bundle install --file=~/Brewfile     # pick up newly added packages
```
Re-run `~/.bin/set-vscode-file-associations.sh` if macOS or VS Code has reset file associations (they reset on some upgrades). The Python shims no longer need re-running after an upgrade — see below.

To capture newly installed packages back into the repo:
```bash
cd ~ && brew bundle dump --force --file=Brewfile
git add -f Brewfile && git commit -m "Update Brewfile" && git push
```

### Linux

Only a subset applies. `.zshrc_Linux` assumes a Docker container on a server and is intentionally minimal. Portable pieces: `.zshrc`/`.zsh_alias`, `.gitconfig`, `.config/git/ignore`, `.claude/`, `.gemini/`, and `.config/Code/User/` (VS Code reads that path natively on Linux — no symlink needed). The Brewfile, the file-association script, and the 1Password agent socket are macOS-only; the script exits cleanly on other platforms.

---

## 🐍 Python Management & direnv (macOS Insulation)

Three Pythons coexist on this Mac. The split is deliberate:

| Interpreter | Role |
|---|---|
| `/usr/bin/python3` (Apple, 3.9) | macOS internals only — **never** used for development, never modified |
| `~/.local/bin/python3` → uv 3.12 | the default for ad-hoc scripts and the REPL |
| per-project `.venv` (uv + direnv) | all real work |

Homebrew also carries `python@3.11` as a dependency of `llvm` and `python-tk@3.11`. It cannot be uninstalled and is not used directly; the `PATH` ordering below keeps it from shadowing uv.

- `uv python install 3.12 --default` creates and maintains the `python`/`python3`/`python3.12` shims in `~/.local/bin`. They point at the **minor-version** directory (`cpython-3.12-*`), so `uv python upgrade` swaps the patch release underneath without breaking them.
- `pip`/`pip3` are not managed by uv and are symlinked by hand — also to the minor-version directory, for the same reason. Keep the default interpreter package-free: use `uv tool install` for CLI tools and `uv run --with X` for one-offs, so a `uv python upgrade` never takes packages with it.

> [!NOTE]
> `--default` is still marked experimental by uv and prints a warning. If it is ever removed, the shims are three `ln -sfn` commands — see the new-machine steps above.

### PATH ordering (why it lives in `.zshenv`, not `.zshrc`)

`.zshrc` runs **only for interactive shells**. With `PATH` set there, `python3` meant uv 3.12 in a terminal but Homebrew 3.11 in anything non-interactive — Makefiles, `sh -c`, `subprocess`, cron and launchd jobs — because macOS `path_helper` puts `/usr/local/bin` first. Silent, and it only bites in automation.

So `PATH` is set in **`.zshenv`** (every zsh) and re-prepended in **`.zprofile`** (login shells, after `/etc/zprofile` runs `path_helper` and hoists the system directories back to the front). `typeset -U path` keeps the second prepend from duplicating entries. Verify with:

```bash
for f in -lic -ic -lc -c; do /bin/zsh $f 'python3 --version'; done   # all must agree
```

Note that launchd jobs read none of these files — they inherit launchd's own environment. Scripts run by an agent should call absolute paths or set `PATH` in the plist.
- **direnv** is configured (`~/.config/direnv/direnvrc`) to manage virtualenv switching:
  - `layout_uv` validates or prompts for active virtual environments automatically in supported workspaces.

---

## 🛠️ Toolchains & Environments

- **Rust & Cargo:** Environment variables are initialized via `~/.zshenv` pointing to `~/.cargo/bin`.
- **Java (OpenJDK):** Installed via homebrew, with OpenJDK pathways prepended to `PATH` and `CPPFLAGS` exported in `~/.zshrc`.
- **LM Studio CLI (`lms`):** Binary pathways added to user `PATH` at `~/.lmstudio/bin`.
- **Docker:** Aliased to `docker compose` (`dc`) for simplified workflow management.

---

## 💬 Consolidated AI Guidelines

AI coding assistants use a tiered instructions hierarchy to avoid duplication:
1. **Gemini:** Full guidelines — planning templates, surgical execution rules, code standards — in [.gemini/GEMINI.md](.gemini/GEMINI.md).
2. **Claude Code:** [.claude/CLAUDE.md](.claude/CLAUDE.md), deliberately short since it is read on every session. Stack conventions and working style only; Claude Code handles planning natively, so the plan scaffolding in `GEMINI.md` is not repeated there.
3. **Claude Code settings:** [.claude/settings.json](.claude/settings.json) — permissions, sandbox, model, enabled plugins. Plugins reinstall themselves from the `enabledPlugins`/`extraKnownMarketplaces` entries, so `~/.claude/plugins/` is not tracked.
4. **Project-Specific Rules:** Sub-repositories contain minimal instructions pointing to the global guidelines, keeping only project-specific rules locally.

> [!NOTE]
> Session state under `~/.claude` (`projects/`, `sessions/`, `history.jsonl`, `file-history/`, caches) is intentionally **not** tracked: it is machine-local and contains conversation transcripts. `~/.claude/.claude.json` is excluded too — it holds a per-machine `machineID`/`userID`.

## 🖥️ Editor & Applications

- **VS Code** is the default editor and the default handler for code/text file types.
  - User settings live at `~/.config/Code/User/` (Linux-native path, tracked here). On macOS, `~/Library/Application Support/Code/User/{settings,keybindings}.json` are symlinks into it.
  - File associations are set by `~/.bin/set-vscode-file-associations.sh` (macOS only). It writes the LaunchServices preference file directly, picking `LSHandlerContentType` for extensions with a concrete UTI and `LSHandlerContentTag` for those with a dynamic one -- `duti` only ever writes the latter, so it silently fails on types like `.pas`, and forcing it throws one modal confirmation dialog per extension. Re-run after macOS or VS Code upgrades.
- **Brewfile:** Homebrew formulae, casks, VS Code extensions, and cargo/npm globals are captured in [Brewfile](Brewfile). Restore on a new Mac with `brew bundle install`; refresh with `brew bundle dump --force`.