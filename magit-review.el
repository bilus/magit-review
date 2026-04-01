;;; magit-review.el --- Annotate diff lines in magit revision buffers -*- lexical-binding: t; -*-

;; Author: Marcin
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (magit "3.0"))
;; Keywords: tools, vc

;;; Commentary:

;; Provides a single command `magit-review-annotate' that captures a
;; one-line note about the diff line at point in a magit revision
;; buffer.  The annotation is written to REVIEW.md in the repository
;; root in the format:
;;
;;   a348a942 path/to/file:123: My annotation
;;
;; Lines in REVIEW.md are kept sorted.  The file is opened in a
;; window but focus stays in the magit buffer so you can keep
;; reviewing.

;;; Code:

(require 'magit)
(require 'magit-diff)

(defgroup magit-review nil
  "Annotate diff lines from magit revision buffers."
  :group 'magit
  :prefix "magit-review-")

(defcustom magit-review-file "REVIEW.md"
  "File name (relative to repo root) where annotations are stored."
  :type 'string
  :group 'magit-review)

(defcustom magit-review-sha-length 8
  "Number of hex characters to use for the abbreviated SHA."
  :type 'integer
  :group 'magit-review)

(defun magit-review--current-sha ()
  "Return the abbreviated commit SHA for the revision shown in the current buffer."
  (when-let ((rev (magit-section-case
                    (hunk  (oref (oref it parent) value))
                    (file  (oref it value))
                    (t     nil))))
    ;; rev may already be the SHA if we're in a revision buffer
    nil)
  ;; More reliable: pull from the revision buffer directly.
  (or (and (derived-mode-p 'magit-revision-mode)
           magit-buffer-revision)
      (and (derived-mode-p 'magit-diff-mode)
           magit-buffer-range)
      (magit-section-case
        (hunk (when-let ((section (oref it parent)))
                (and (derived-mode-p 'magit-revision-mode)
                     magit-buffer-revision)))
        (t nil))))

(defun magit-review--diff-file ()
  "Return the file path for the diff section at point."
  (when-let ((section (magit-current-section)))
    (let ((sec section))
      ;; Walk up to the file section.
      (while (and sec (not (magit-file-section-p sec)))
        (setq sec (oref sec parent)))
      (when sec
        (oref sec value)))))

(defun magit-review--diff-line-number ()
  "Return the line number in the new file for the current diff line.
Works by parsing the hunk header and counting non-removed lines."
  (save-excursion
    (beginning-of-line)
    (let ((target-pos (point))
          (line-num nil))
      ;; Find the hunk header above point.
      (when (re-search-backward "^@@" nil t)
        ;; Parse the +N from @@ -a,b +N,M @@
        (when (looking-at "^@@ -[0-9,]+ \\+\\([0-9]+\\)")
          (setq line-num (1- (string-to-number (match-string 1))))
          (forward-line 1)
          (while (< (point) target-pos)
            (let ((ch (char-after)))
              (cond
               ;; Context line or added line: increment new-file counter.
               ((or (eq ch ?\s) (eq ch ?+))
                (setq line-num (1+ line-num)))
               ;; Removed line: don't count.
               ((eq ch ?-) nil)
               ;; Anything else (e.g. "\ No newline"): skip.
               (t nil)))
            (forward-line 1))
          ;; Count the line we're actually on.
          (let ((ch (char-after)))
            (when (or (eq ch ?\s) (eq ch ?+))
              (setq line-num (1+ line-num))))))
      line-num)))

(defun magit-review--review-file-path ()
  "Return the absolute path to REVIEW.md in the repo root."
  (expand-file-name magit-review-file (magit-toplevel)))

(defun magit-review--format-entry (sha file line annotation)
  "Format a single review entry string."
  (format "%s:%d: [%s] %s"
          file
          line
          (substring sha 0 (min magit-review-sha-length (length sha)))
          annotation))

(defconst magit-review--header
  "> Code review:\n> Annotations in the following format: <path>:<line>: [<sha>] Annotation\n> C-c on a line to go to it (on HEAD)\n"
  "Header prepended to every REVIEW.md file.")

(defun magit-review--read-lines (path)
  "Read PATH and return annotation lines, skipping the header."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (seq-filter (lambda (s)
                    (and (not (string-empty-p s))
                         (not (string-prefix-p ">" s))
                         (not (string-prefix-p "-*-" s))))
                  (split-string (buffer-string) "\n")))))

(defun magit-review--write-sorted (path lines)
  "Write header followed by LINES sorted to PATH."
  (let ((sorted (sort (copy-sequence lines) #'string<)))
    (with-temp-file path
      (insert magit-review--header "\n")
      (insert (mapconcat #'identity sorted "\n") "\n"))))

(defun magit-review--show-file (path)
  "Display PATH in another window without selecting it."
  (let ((buf (find-file-noselect path)))
    (display-buffer buf '(display-buffer-use-some-window
                          (inhibit-same-window . t)))
    ;; Move to end so the latest entry is visible.
    (with-current-buffer buf
      (goto-char (point-max)))))

;;;###autoload
(defun magit-review-annotate ()
  "Annotate the diff line at point with a one-line comment.
The entry is appended to REVIEW.md in the repository root.  The
file is displayed in another window but focus remains here."
  (interactive)
  (unless (derived-mode-p 'magit-revision-mode 'magit-diff-mode)
    (user-error "Not in a magit revision/diff buffer"))
  (let ((sha (or (magit-review--current-sha)
                 (user-error "Cannot determine commit SHA")))
        (file (or (magit-review--diff-file)
                  (user-error "Cannot determine file path")))
        (line (or (magit-review--diff-line-number)
                  (user-error "Cannot determine line number (are you on a hunk line?)"))))
    (let* ((short-sha (substring sha 0 (min magit-review-sha-length (length sha))))
           (prompt (format "Review [%s:%d [%s]]: " file line short-sha))
           (annotation (read-string prompt)))
      (when (string-empty-p (string-trim annotation))
        (user-error "Empty annotation, aborting"))
      (let* ((path (magit-review--review-file-path))
             (entry (magit-review--format-entry sha file line annotation))
             (existing (magit-review--read-lines path))
             (new-lines (append existing (list entry))))
        (magit-review--write-sorted path new-lines)
        (magit-review--show-file path)
        (message "Annotated: %s" entry)))))

;;;###autoload
(defun magit-review-open ()
  "Open REVIEW.md for the current repository."
  (interactive)
  (find-file (magit-review--review-file-path)))

;; --- Transient integration ---

;;;###autoload
(with-eval-after-load 'magit
  (transient-append-suffix 'magit-diff "d"
    '("n" "Annotate line" magit-review-annotate))
  (transient-append-suffix 'magit-diff "n"
    '("N" "Open review file" magit-review-open)))

(provide 'magit-review)
;;; magit-review.el ends here
