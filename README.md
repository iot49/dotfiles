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

### Installing on a New Machine
To set up this environment on a fresh machine, follow these steps:

1. **Initialize Git and add remote**:
   ```bash
   cd ~
   git init
   git remote add origin https://github.com/iot49/dotfiles.git
   git fetch
   ```
2. **Back up existing conflicting files**:
   Any standard files (like `.zshrc` or `.gitignore`) that already exist on the new machine will conflict with the checkout. Back them up:
   ```bash
   mkdir -p ~/dotfiles_backup
   # Move conflicting files to the backup directory
   ```
3. **Checkout the repository**:
   ```bash
   git checkout main
   ```
4. **Initialize Toolchains & Links**:
   - Ensure `uv` is installed.
   - Run the Python setup script to create python/pip links:
     ```bash
     ~/.bin/setup-python-links
     ```

---

## 🐍 Python Management & direnv (macOS Insulation)

- Python versions are managed dynamically using **`uv`** to insulate development environments from macOS system Python updates.
- Standalone Python binaries installed by `uv` are linked globally to the user environment via symlinks in `~/.local/bin/` (which is prepended to the `PATH` in `~/.zshrc`).
- To initialize or update these symlinks dynamically based on the system's architecture, use the helper script:
  - `~/.bin/setup-python-links` (tracks `python`, `python3`, `pip`, and `pip3` to the appropriate `uv` toolchain).
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

---

## 🖥️ Editor & Applications

- **VS Code** is the default editor and the default handler for code/text file types.
  - User settings live at `~/.config/Code/User/` (Linux-native path, tracked here). On macOS, `~/Library/Application Support/Code/User/{settings,keybindings}.json` are symlinks into it.
  - File associations are set by `~/.bin/set-vscode-file-associations.sh` (macOS only; requires `duti`). Re-run after macOS or VS Code upgrades.
- **Brewfile:** Homebrew formulae, casks, VS Code extensions, and cargo/npm globals are captured in [Brewfile](Brewfile). Restore on a new Mac with `brew bundle install`; refresh with `brew bundle dump --force`.