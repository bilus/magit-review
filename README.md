# magit-review

Annotate hunks in magit diffs using git notes. Built for code review workflows where you walk through commits, mark up specific lines, and export the annotations as Markdown for an LLM to act on.

## How it works

Annotations are stored as git notes under a dedicated ref (`refs/notes/review`) so they don't interfere with regular git notes. Each note is appended to its commit in the format:

```
path/to/file:line: your comment
```

A single commit can have multiple annotations:

```
src/server.go:45: Remove this dead code
src/server.go:112: Extract into a helper function
src/handler.go:23: Error handling is wrong, should wrap the error
```

## Installation

### straight.el + use-package

```elisp
(use-package magit-review
  :straight (:host github :repo "bilus/magit-review")
  :after magit
  :config
  (magit-review-setup))
```

### Manual

Copy `magit-review.el` to your load path, then:

```elisp
(require 'magit-review)
(magit-review-setup)
```

## Usage

### Annotating

1. Open a magit log with `l l`
2. Navigate to a commit and press `RET` to view its diff
3. Move point to a hunk you want to annotate
4. Press `d n` to annotate the hunk
5. Type your annotation at the prompt

### Other commands

| Binding     | Command                        | Description                          |
|-------------|--------------------------------|--------------------------------------|
| `d n`       | `magit-review-annotate-hunk`   | Annotate hunk at point               |
| `d N`       | `magit-review-show-notes`      | Show review notes for commit         |
| `C-c r n`   | `magit-review-annotate-hunk`   | Annotate hunk at point               |
| `C-c r s`   | `magit-review-show-notes`      | Show notes for commit                |
| `C-c r e`   | `magit-review-edit-notes`      | Edit notes in a buffer               |
| `C-c r d`   | `magit-review-remove-notes`    | Remove all notes for commit          |
| `C-c r x`   | `magit-review-export`          | Export all notes to Markdown file    |
| `C-c r b`   | `magit-review-export-to-buffer`| Export all notes to a buffer         |

### Exporting for LLM

Run `M-x magit-review-export` (or `C-c r x`). This produces a Markdown file (default: `REVIEW.md` in the repo root) structured for LLM consumption:

```markdown
# Code Review Notes

## Instructions

Each section below refers to a git commit. Annotations are in the format `path/to/file:line: comment`.
Apply the requested changes to the specified files and lines.

### Commit a1b2c3d — Add user authentication

\```
src/auth.go:45: Use bcrypt instead of sha256 for password hashing
src/auth.go:89: This token expiry should be configurable, not hardcoded
\```

### Commit e4f5g6h — Refactor database layer

\```
src/db/conn.go:12: Connection pool size should come from config
src/db/query.go:67: This N+1 query needs to be a join
\```
```

### Tips for effective annotations

Write annotations as direct instructions:

```
src/server.go:45: Remove this function, it's dead code
src/server.go:112: Extract lines 112-130 into a helper called validateInput
src/handler.go:23: Wrap the error with fmt.Errorf("handler failed: %w", err)
```

Avoid vague notes like "fix this" — the LLM works better with specific intent.

## Git notes management

Notes live in `refs/notes/review` (configurable via `magit-review-notes-ref`). They are local by default. To share them:

```bash
# Push
git push origin refs/notes/review

# Fetch
git fetch origin refs/notes/review:refs/notes/review
```

To configure automatic fetch:

```bash
git config --add remote.origin.fetch "+refs/notes/review:refs/notes/review"
```

## Customization

```elisp
;; Use a different notes ref
(setq magit-review-notes-ref "refs/notes/my-review")

;; Change the default export filename
(setq magit-review-export-file "review-notes.md")
```

## License

GPL-3.0
