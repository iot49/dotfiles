# Global AI Developer & Coding Guidelines

This document defines the global rules, philosophy, and best practices for AI coding assistants working in this workspace.

---

## 💬 Phase 1: Pre-Flight & Design Alignment

### 1. Align & Clarify Before Planning
Stop and engage in interactive discussion/clarification *before* drafting a plan or writing code if:
- **Ambiguity:** The request is underspecified. Ask to clarify assumptions.
- **Alternatives:** A simpler, standard architectural pattern exists. Suggest it.
- **Drawbacks:** The requested path introduces technical debt, resource leaks, or dependency risks.

### 2. Simplicity First (No Speculation)
- Deliver the minimum code required. Do not write speculative features, abstractions, or "flexibility" setups.
- Avoid premature error handling for impossible scenarios.
- If a solution can be implemented in 50 lines instead of 200, rewrite/simplify it.

---

## ⚡ Phase 2: Plan & Architectural Guardrails

Before executing any complex changes, you MUST present an optimized plan and obtain user approval.

### 1. Trigger Thresholds
- **DO NOT Plan For:** Diagnostic commands, file reads/greps, purely investigatory queries, or minor/one-line edits.
- **MUST Plan For:** Refactoring, new modules/packages, multi-package edits, state/config changes, or UI updates.

### 2. Plan Template
Your proposed plan must use this layout:
```markdown
### 🎯 Refined Goal & Objective
[2-sentence summary of what is being built/fixed, and why.]

### 🏗️ Architectural Alignment
- [Verify boundaries, patterns, and style conventions]

### 📂 Proposed File Changes
- **Modify:** [file_basename](path/to/file) - [brief description]
- **Create [NEW]:** [file_basename](path/to/file) - [brief description]

### 🔬 Verification & Testing Plan
- **Automated Check:** [Command to run, e.g. tests or build]
- **Manual Verification:** [What to look for]
```

---

## 🛠️ Phase 3: Surgical Execution & Verification

### 1. Surgical Edits (Minimum Impact Diffs)
- Touch only files and blocks required for the task. Do not reformat or "improve" adjacent code.
- Match existing code style, patterns, and naming conventions exactly.
- **Orphan clean-up:** Remove imports, variables, or functions that *your* changes make obsolete. Leave pre-existing dead code alone.

### 2. Goal-Driven Verification
- Proceed in small steps.
- Translate requirements into concrete, reproducible success criteria *before* coding.
- Verify changes continuously using local test suites, builds, or script outputs.
- Test all code before marking tasks as completed in `task.md`.

---

## 🐍 Python Guidelines
- Use `uv` to manage Python versions and environments.
- Run Python scripts and CLI tools using `uv run`.
- Use **Ruff**, **Black**, and **Pyright** for linting, formatting, and type-checking across all Python code (including Jupyter Notebooks where applicable).

---

## 💻 Web Frontend Guidelines
- Use TypeScript and pnpm.
- Use Lit Element for UI components:
  - Keep components small and focused; break them into individual components if functionality gets complex.
  - Create tests for all components.
- **Formatting Rules:** Never use inline CSS styles in HTML. Prefer 2-space indentation.
