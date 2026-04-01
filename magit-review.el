;;; magit-review.el --- Annotate magit diff hunks with git notes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Marcin Bilski

;; Author: Marcin Bilski
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (magit "3.0") (transient "0.4"))
;; Keywords: vc, tools, convenience
;; URL: https://github.com/bilus/magit-review

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; magit-review lets you annotate individual hunks in magit diff buffers
;; using git notes.  Navigate to a hunk, press a key, type your annotation,
;; and it gets stored as a git note on that commit in the format:
;;
;;   path/to/file:line: your annotation
;;
;; Multiple annotations per commit are supported via `git notes append'.
;; Notes can be exported as structured Markdown for use with LLMs.

;;; Code:

(require 'magit)
(require 'magit-diff)
(require 'transient)

(defgroup magit-review nil
  "Annotate magit diff hunks with git notes."
  :group 'magit-extensions
  :prefix "magit-review-")

(defcustom magit-review-notes-ref "refs/notes/review"
  "Git notes ref used for review annotations.
Using a dedicated ref keeps review notes separate from regular
git notes in refs/notes/commits."
  :type 'string
  :group 'magit-review)

(defcustom magit-review-export-file "REVIEW.md"
  "Default filename for exported review notes."
  :type 'string
  :group 'magit-review)

;;; Core

(defun magit-review--commit-at-point ()
  "Return the commit SHA for the current context."
  (or (magit-commit-at-point)
      magit-buffer-revision
      (car magit-buffer-range)))

(defun magit-review--hunk-line ()
  "Return the starting line number from the hunk header at point."
  (when (magit-section-match 'hunk)
    (save-excursion
      (goto-char (oref (magit-current-section) start))
      (when (looking-at "@@[^@]+@@")
        (let ((header (match-string 0)))
          (when (string-match "\\+\\([0-9]+\\)" header)
            (match-string 1 header)))))))

(defun magit-review--hunk-text ()
  "Return the hunk diff text at point."
  (when (magit-section-match 'hunk)
    (let ((section (magit-current-section)))
      (buffer-substring-no-properties
       (oref section start)
       (oref section end)))))

(defun magit-review--format-annotation (file line comment)
  "Format an annotation string from FILE, LINE, and COMMENT."
  (format "%s:%s: %s" file (or line "?") comment))

;;;###autoload
(defun magit-review-annotate-hunk (comment)
  "Add a file:line annotation to git notes for the commit at point.
COMMENT is the annotation text.  The note is appended to the
review notes ref so multiple annotations per commit are supported."
  (interactive
   (let* ((file (magit-file-at-point))
          (line (magit-review--hunk-line)))
     (unless (magit-review--commit-at-point)
       (user-error "No commit at point"))
     (unless file
       (user-error "No file at point"))
     (list (read-string (format "Note for %s:%s: " file (or line "?"))))))
  (let* ((rev (magit-review--commit-at-point))
         (file (magit-file-at-point))
         (line (magit-review--hunk-line))
         (annotation (magit-review--format-annotation file line comment)))
    (magit-run-git "notes" "--ref" magit-review-notes-ref
                   "append" "-m" annotation rev)
    (message "Review note added: %s" annotation)))

;;;###autoload
(defun magit-review-show-notes ()
  "Show review notes for the commit at point."
  (interactive)
  (let ((rev (magit-review--commit-at-point)))
    (unless rev (user-error "No commit at point"))
    (condition-case nil
        (let ((notes (magit-git-string "notes" "--ref" magit-review-notes-ref
                                       "show" rev)))
          (if notes
              (message "%s" notes)
            (message "No review notes for %s" (magit-rev-format "%h" rev))))
      (error (message "No review notes for %s" (magit-rev-format "%h" rev))))))

;;;###autoload
(defun magit-review-remove-notes ()
  "Remove all review notes for the commit at point."
  (interactive)
  (let ((rev (magit-review--commit-at-point)))
    (unless rev (user-error "No commit at point"))
    (when (yes-or-no-p (format "Remove all review notes for %s? "
                               (magit-rev-format "%h" rev)))
      (magit-run-git "notes" "--ref" magit-review-notes-ref "remove" rev)
      (message "Review notes removed for %s" (magit-rev-format "%h" rev)))))

;;;###autoload
(defun magit-review-edit-notes ()
  "Edit review notes for the commit at point in a buffer."
  (interactive)
  (let ((rev (magit-review--commit-at-point)))
    (unless rev (user-error "No commit at point"))
    (magit-run-git-with-editor "notes" "--ref" magit-review-notes-ref
                               "edit" rev)))

;;; Export

(defun magit-review--collect-notes ()
  "Collect all review notes as an alist of (short-rev full-rev subject notes)."
  (let ((result '())
        (log-output (magit-git-string
                     "log" "--all" "--format=%H"
                     (concat "--notes=" magit-review-notes-ref))))
    ;; Get all commits that have notes
    (dolist (full-rev (split-string
                       (or (magit-git-output
                            "log" "--all" "--format=%H"
                            (concat "--notes=" magit-review-notes-ref))
                           "")
                       "\n" t))
      (condition-case nil
          (let ((notes (magit-git-string "notes" "--ref" magit-review-notes-ref
                                         "show" full-rev)))
            (when (and notes (not (string-empty-p notes)))
              (let ((short-rev (magit-rev-format "%h" full-rev))
                    (subject (magit-rev-format "%s" full-rev)))
                (push (list short-rev full-rev subject notes) result))))
        (error nil)))
    (nreverse result)))

(defun magit-review--format-markdown (notes-alist)
  "Format NOTES-ALIST as Markdown for LLM consumption."
  (with-temp-buffer
    (insert "# Code Review Notes\n\n")
    (insert "## Instructions\n\n")
    (insert "Each section below refers to a git commit. ")
    (insert "Annotations are in the format `path/to/file:line: comment`.\n")
    (insert "Apply the requested changes to the specified files and lines.\n\n")
    (insert "## Annotations\n\n")
    (dolist (entry notes-alist)
      (let ((short-rev (nth 0 entry))
            (full-rev (nth 1 entry))
            (subject (nth 2 entry))
            (notes (nth 3 entry)))
        (insert (format "### Commit %s — %s\n\n" short-rev subject))
        (insert "```\n")
        (insert notes)
        (unless (string-suffix-p "\n" notes)
          (insert "\n"))
        (insert "```\n\n")))
    (buffer-string)))

;;;###autoload
(defun magit-review-export (&optional file)
  "Export all review notes as Markdown to FILE.
Defaults to `magit-review-export-file' in the repository root."
  (interactive
   (list (read-file-name "Export to: "
                         (magit-toplevel)
                         nil nil
                         magit-review-export-file)))
  (let* ((notes (magit-review--collect-notes))
         (md (magit-review--format-markdown notes))
         (target (or file (expand-file-name magit-review-export-file
                                            (magit-toplevel)))))
    (if (null notes)
        (message "No review notes found.")
      (with-temp-file target
        (insert md))
      (message "Exported %d annotated commits to %s" (length notes) target)
      (find-file target))))

;;;###autoload
(defun magit-review-export-to-buffer ()
  "Export all review notes as Markdown to a buffer."
  (interactive)
  (let* ((notes (magit-review--collect-notes))
         (md (magit-review--format-markdown notes)))
    (if (null notes)
        (message "No review notes found.")
      (let ((buf (get-buffer-create "*magit-review-export*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert md)
          (markdown-mode)
          (goto-char (point-min)))
        (switch-to-buffer buf)))))

;;;###autoload
(defun magit-review-clear-all ()
  "Remove all review notes from the repository.
This deletes the entire review notes ref."
  (interactive)
  (when (yes-or-no-p "Remove ALL review notes from this repository? ")
    (condition-case nil
        (progn
          (magit-run-git "update-ref" "-d" magit-review-notes-ref)
          (message "All review notes cleared."))
      (error (message "No review notes to clear.")))))

;;; Transient integration

(transient-define-suffix magit-review-annotate-hunk-suffix ()
  "Add a review annotation to the hunk at point."
  :key "n"
  :description "Review: annotate hunk"
  (interactive)
  (call-interactively #'magit-review-annotate-hunk))

(transient-define-suffix magit-review-show-notes-suffix ()
  "Show review notes for commit at point."
  :key "N"
  :description "Review: show notes"
  (interactive)
  (call-interactively #'magit-review-show-notes))

;;;###autoload
(defun magit-review-setup-transient ()
  "Add review commands to magit-diff transient."
  (transient-append-suffix 'magit-diff "t"
    '("n" "Review: annotate hunk" magit-review-annotate-hunk-suffix))
  (transient-append-suffix 'magit-diff "n"
    '("N" "Review: show notes" magit-review-show-notes-suffix)))

;;; Minor mode for keybindings

(defvar magit-review-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c r n") #'magit-review-annotate-hunk)
    (define-key map (kbd "C-c r s") #'magit-review-show-notes)
    (define-key map (kbd "C-c r e") #'magit-review-edit-notes)
    (define-key map (kbd "C-c r d") #'magit-review-remove-notes)
    (define-key map (kbd "C-c r x") #'magit-review-export)
    (define-key map (kbd "C-c r b") #'magit-review-export-to-buffer)
    map)
  "Keymap for `magit-review-mode'.")

;;;###autoload
(define-minor-mode magit-review-mode
  "Minor mode for annotating magit diffs with review notes."
  :lighter " Rev"
  :keymap magit-review-mode-map
  :group 'magit-review)

;;;###autoload
(defun magit-review-enable ()
  "Enable magit-review in magit diff and revision buffers."
  (magit-review-mode 1))

;;;###autoload
(defun magit-review-setup ()
  "Set up magit-review: hooks and transient integration."
  (interactive)
  (add-hook 'magit-diff-mode-hook #'magit-review-enable)
  (add-hook 'magit-revision-mode-hook #'magit-review-enable)
  (magit-review-setup-transient))

(provide 'magit-review)
;;; magit-review.el ends here
