# Workspace Environment & Repository Setup

This repository and home directory workspace are configured with separated repositories, isolated Python management, and consolidated AI developer guidelines.

---

## 📂 Git Repositories & Separation

1. **Dotfiles Repository (`~`)**:
   - Managed using the repository [iot49/dotfiles](https://github.com/iot49/dotfiles).
   - In `~`, git is configured to ignore all files by default (`*` in `.gitignore`).
   - To track new dotfiles, use `git add -f <filename>`.
2. **Git Isolation**:
   - To prevent git commands run in non-git subfolders (e.g. `~/iot/`) from accidentally interacting with the home directory's `.git`, the environment variable `GIT_CEILING_DIRECTORIES="/Users/ttmetro"` is exported in `~/.zshrc`.
   - Subdirectories that have their own `.git` folders (like `~/iot/track-occupancy/` or `~/iot/py-rocrail/`) function normally as independent repositories.

---

## 🐍 Python Management (macOS Insulation)

- Python versions are managed dynamically using **`uv`** to insulate development environments from macOS system Python updates.
- Standalone Python binaries installed by `uv` are linked globally to the user environment via symlinks in `~/.local/bin/` (which is prepended to the `PATH` in `~/.zshrc`):
  - `python` & `python3` -> `~/.local/share/uv/python/cpython-3.12.13-.../bin/python3`
  - `pip` & `pip3` -> `~/.local/share/uv/python/cpython-3.12.13-.../bin/pip3`

---

## 💬 Consolidated AI Guidelines

AI coding assistants (like Antigravity and Claude Code) use a tiered instructions hierarchy to avoid duplication:
1. **Global Guidelines:** General agent developer instructions, code standards (Lit Element, 2-space indent, `uv run`), planning templates, and surgical execution rules are defined centrally in [GLOBAL_GUIDELINES.md](GLOBAL_GUIDELINES.md).
2. **Project-Specific Rules:** Sub-repositories contain minimal instructions pointing to the global guidelines, keeping only project-specific rules locally.