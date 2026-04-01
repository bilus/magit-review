# magit-review

Annotate diff lines while reviewing commits in magit. Annotations are saved to `REVIEW.md` in the repo root.

## Format

```
> Code review:
> Annotations in the following format: <path>:<line>: [<sha>] Annotation
> C-c on a line to go to it (on HEAD)

path/to/file:123: [a348a942] My annotation
```

Press `RET` on any annotation line to jump to the file and line.

## Installation (Doom Emacs)

In `packages.el`:

```elisp
(package! magit-review
  :recipe (:host github :repo "YOUR_USER/magit-review"))
```

In `config.el`:

```elisp
(use-package! magit-review
  :after magit)
```

Then `doom sync` and restart.

## Usage

1. Open a commit diff from `magit-log` (`RET` on a commit).
2. Move point to a diff line.
3. Press `d n` to annotate.
4. Type your note and hit `RET`.

`REVIEW.md` opens in a side window; focus stays in magit.

Press `d N` from any magit buffer to open `REVIEW.md`.

## Commands

| Key       | Command                  | Description                |
|-----------|--------------------------|----------------------------|
| `d n`     | `magit-review-annotate`  | Annotate line at point     |
| `d N`     | `magit-review-open`      | Open REVIEW.md             |

## Customization

| Variable                    | Default       | Description            |
|-----------------------------|---------------|------------------------|
| `magit-review-file`         | `"REVIEW.md"` | Output file name       |
| `magit-review-sha-length`   | `8`           | SHA abbreviation width |
