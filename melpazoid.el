;;; melpazoid.el --- A MELPA review tool  ; lexical-binding: t

;; Authors: Chris Rayner (dchrisrayner@gmail.com)
;; Created: June 9 2019
;; Keywords: tools, convenience
;; URL: https://github.com/riscy/melpazoid
;; Package-Requires: ((emacs "25.1"))
;; Version: 0.0.0

;;; Commentary:

;; A MELPA review tool to run the MELPA checklist in addition
;; to some other checks that might point to other issues.

;;; Code:

(require 'package)
(defvar checkdoc-version)
(declare-function pkg-info-format-version "ext:pkg-info.el" t t)
(declare-function pkg-info-package-version "ext:pkg-info.el" t t)
(declare-function package-lint-current-buffer "ext:package-lint.el" t t)
(defconst melpazoid-buffer "*melpazoid*" "Name of the 'melpazoid' buffer.")
(defvar melpazoid--misc-header-printed-p nil "Whether misc-header was printed.")
(defvar melpazoid-can-modify-buffers t "Whether melpazoid can modify buffers.")

(defun melpazoid-byte-compile (filename)
  "Wrapper for running `byte-compile-file' against FILENAME."
  ;; TODO: use flycheck or its pattern for cleanroom byte-compiling
  (let ((version (caddr (split-string (emacs-version)))))
    (melpazoid-insert "<kbd>byte-compile-file</kbd> (using Emacs %s):" version))
  (melpazoid--remove-no-compile)
  (ignore-errors (kill-buffer "*Compile-Log*"))
  (cl-letf (((symbol-function 'message) #'ignore))
    (melpazoid--check-lexical-binding)
    (let ((lexical-binding t)) (byte-compile-file filename)))
  (with-current-buffer (get-buffer-create "*Compile-Log*")
    (if (melpazoid--buffer-almost-empty-p)
        (melpazoid-insert "- No issues! 💯")
      (goto-char (point-min)) (forward-line 2)
      (melpazoid-insert "```")
      (melpazoid-insert (buffer-substring (point) (point-max)))
      (melpazoid-insert "```")))
  (melpazoid-insert ""))

(defun melpazoid--check-lexical-binding ()
  "Warn about lack of lexical binding."
  (save-excursion
    (goto-char (point-min))
    (unless (re-search-forward "lexical-binding:[[:blank:]]*t" nil t)
      (melpazoid-insert
       (concat
        "- Per CONTRIBUTING.org, consider"
        " [using lexical binding](https://github.com/melpa/melpa/blob/master/CONTRIBUTING.org#fixing-typical-problems)"
        " (you will need at least emacs 24)"))
      (melpazoid-insert "- Lexical binding will be used in what follows"))))

(defun melpazoid--remove-no-compile ()
  "Warn about and remove `no-byte-compile' directive."
  (save-excursion
    (let ((melpazoid--misc-header-printed-p t))  ; HACK: don't print a header
      (melpazoid-misc "no-byte-compile: t" "Don't set `no-byte-compile: t`" nil t))
    (when melpazoid-can-modify-buffers
      (goto-char (point-min))
      (while (re-search-forward "no-byte-compile:[\s\t]*t" nil t)
        (delete-char -1)
        (insert "nil")
        (melpazoid-insert "- Byte-compiling is enabled in what follows")
        (save-buffer)))))

(defun melpazoid--buffer-almost-empty-p ()
  "Return non-nil if current buffer is 'almost' empty."
  (<= (- (point-max) (point)) 3))

(defun melpazoid-checkdoc (filename)
  "Wrapper for running `checkdoc-file' against FILENAME."
  (require 'checkdoc)  ; to retain cleaner byte-compilation in script mode
  (melpazoid-insert "<kbd>M-x checkdoc</kbd> (using version %s):" checkdoc-version)
  (ignore-errors (kill-buffer "*Warnings*"))
  (let ((sentence-end-double-space nil)  ; be a little more leniant
        (checkdoc-proper-noun-list nil)
        (checkdoc-common-verbs-wrong-voice nil))
    (cl-letf (((symbol-function 'message) #'ignore))
      (ignore-errors (checkdoc-file filename))))
  (if (not (get-buffer "*Warnings*"))
      (melpazoid-insert "- No issues! 💯")
    (with-current-buffer "*Warnings*"
      (melpazoid-insert "```")
      (melpazoid-insert (buffer-substring (point-min) (point-max)))
      (melpazoid-insert "```")))
  (melpazoid-insert ""))

(defun melpazoid-package-lint ()
  "Wrapper for running `package-lint' against the current buffer."
  (require 'package-lint)    ; to retain cleaner byte-compilation in script mode
  (require 'pkg-info)        ; to retain cleaner byte-compilation in script mode
  (if (not (melpazoid--run-package-lint-p))
      (melpazoid-insert "(Skipping package-lint on this file)")
    (melpazoid-insert
     "<kbd>M-x package-lint-current-buffer</kbd> (using version %s):"
     (pkg-info-format-version (pkg-info-package-version "package-lint")))
    (ignore-errors (kill-buffer "*Package-Lint*"))
    (ignore-errors (package-lint-current-buffer))
    (with-current-buffer (get-buffer-create "*Package-Lint*")
      (let ((output (melpazoid--string-trim (buffer-substring (point-min) (point-max)))))
        (if (string= "No issues found." output)
            (melpazoid-insert "- No issues! 💯")
          (melpazoid-insert "```")
          (melpazoid-insert output)
          (melpazoid-insert "```")))))
  (melpazoid-insert ""))

(defun melpazoid--run-package-lint-p ()
  "Return non-nil if buffer's file is not the package's 'main' file."
  (or (not (getenv "PACKAGE_NAME"))
      ;; TODO: can we use buffer-file-name instead of (buffer-file-name)?
      (string= (getenv "PACKAGE_NAME") (file-name-base (buffer-file-name)))
      (zerop (length (getenv "PACKAGE_NAME")))))

(defun melpazoid-check-declare ()
  "Wrapper for `melpazoid' check-declare.
NOTE: this sometimes backfires when running checks automatically inside
a Docker container, e.g. kellyk/emacs does not include the .el files."
  (melpazoid-insert "<kbd>M-x check-declare-file</kbd> (optional):")
  (ignore-errors (kill-buffer "*Check Declarations Warnings*"))
  (check-declare-file (buffer-file-name (current-buffer)))
  (with-current-buffer (get-buffer-create "*Check Declarations Warnings*")
    (if (melpazoid--buffer-almost-empty-p)
        (melpazoid-insert "- No issues! 💯")
      (melpazoid-insert "```")
      (melpazoid-insert (buffer-substring (point-min) (point-max)))
      (melpazoid-insert "```")))
  (melpazoid-insert ""))

(defun melpazoid-check-sharp-quotes ()
  "Check for missing sharp quotes."
  (melpazoid-misc "#'(lambda" "There is no need to quote lambdas (neither #' nor ')")
  (melpazoid-misc "[^#]'(lambda" "Don't quote lambdas; this prevents them from being compiled")
  (let ((msg "It's safer to sharp-quote function names; use `#'`"))
    (melpazoid-misc "(apply-on-rectangle '[^,]" msg)
    (melpazoid-misc "(apply-partially '[^,]" msg)
    (melpazoid-misc "(apply '[^,]" msg)
    (melpazoid-misc "(seq-mapcat '[^,]" msg)
    (melpazoid-misc "(seq-map '[^,]" msg)
    (melpazoid-misc "(seq-mapn '[^,]" msg)
    (melpazoid-misc "(mapconcat '[^,]" msg)
    (melpazoid-misc "(functionp '[^,]" msg)
    (melpazoid-misc "(mapcar '[^,]" msg)
    (melpazoid-misc "(funcall '[^,]" msg)
    (melpazoid-misc "(cl-assoc-if '[^,]" msg)
    (melpazoid-misc "(call-interactively '" msg)
    (melpazoid-misc "(callf '[^,]" msg)
    (melpazoid-misc "(run-at-time[^(#]*[^#]'" msg)
    (melpazoid-misc "(seq-find '" msg)
    (melpazoid-misc "(add-hook '[^[:space:]]+ '" msg)
    (melpazoid-misc "(remove-hook '[^[:space:]]+ '" msg)
    (melpazoid-misc "(advice-add [^#)]*)" msg)
    (melpazoid-misc "(defalias [^#()]*)" msg)
    (melpazoid-misc "(run-with-idle-timer[^(#]*[^#]'" msg)))

(defun melpazoid-check-misc ()
  "Miscellaneous checker."
  (melpazoid-misc "(string-equal major-mode" "Check major mode with eq, e.g.: `(eq major-mode 'dired-mode)`")
  (melpazoid-misc "/tmp" "Use `temporary-file-directory` instead of /tmp in code")
  (melpazoid-misc "(s-starts-with-p" "Using `string-prefix-p` may allow dropping the dependency on `s`")
  (melpazoid-misc "(s-ends-with-p" "Using `string-suffix-p` may allow dropping the dependency on `s`")
  (melpazoid-misc "Copyright.*Free Software Foundation" "Did you really do the paperwork to assign your copyright?")
  (melpazoid-misc "(add-to-list 'auto-mode-alist.*\\$" "Terminate auto-mode-alist entries with `\\\\'`")
  (melpazoid-misc "This file is part of GNU Emacs." "This statement may not currently be accurate")
  (melpazoid-misc "lighter \"[^ \"]" "Minor mode lighters should start with a space")
  (melpazoid-misc "(fset" "Ensure this `fset` isn't being used as a surrogate `defalias`")
  (melpazoid-misc "(fmakunbound" "Use of `fmakunbound` in a package is an anti-pattern")
  (melpazoid-misc "(setq major-mode" "Explicitly setting major-mode is an anti-pattern")
  (melpazoid-misc "([^ ]*read-string \"[^\"]*[^ ]\"" "Many `*-read-string` prompts should end with a space")
  (melpazoid-misc "(define-derived-mode .*fundamental-mode" "It is unusual to derive from fundamental-mode; try special-mode")
  (melpazoid-misc ";;;###autoload\n(defcustom" "Don't autoload `defcustom`")
  (melpazoid-misc ";;;###autoload\n(add-hook" "Don't autoload `add-hook`")
  (melpazoid-misc "url-copy-file" "Be aware that url-copy-file can't handle redirects")
  (melpazoid-misc ";; Package-Version" "Prefer `;; Version` instead of `;; Package-Version` (MELPA automatically adds `Package-Version`)")
  (melpazoid-misc "^(define-key" "This define-key could overwrite a user's keybindings.  Try: `(defvar my-map (let ((km (make-sparse-keymap))) (define-key ...) km))`")
  (melpazoid-misc "(string-match[^(](symbol-name" "Prefer to use `eq` on symbols")
  (melpazoid-misc "(defcustom [^ ]*--" "Customizable variables shouldn't be private")
  (melpazoid-misc "(ignore-errors (re-search-[fb]" "Use `re-search-*`'s built-in NOERROR argument")
  (melpazoid-misc "(ignore-errors (search-[fb]" "Use `search-*`'s built-in NOERROR argument")
  (melpazoid-misc "(user-error (format" "No `format` required; messages are already f-strings")
  (melpazoid-misc "(message (concat" "No `concat` required; messages are already f-strings")
  (melpazoid-misc "(message (format" "No `format` required; messages are already f-strings")
  (melpazoid-misc "^ ;[^;]" "Single-line comments should (usually) begin with `;;`")
  (melpazoid-misc "(unless (null " "Consider `when ...` instead of `unless (not ...)`")
  (melpazoid-misc "(unless (not " "Consider `when ...` instead of `unless (null ...)`")
  (melpazoid-misc "(when (not " "Consider `unless ...` instead of `when (not ...)`")
  (melpazoid-misc "(when (null " "Consider `unless ...` instead of `when (null ...)`")
  (melpazoid-misc "http://" "Prefer `https` over `http` (if possible)" nil t)
  (melpazoid-misc "(eq[^()]*\\<nil\\>.*)" "You can use `not` or `null`")
  ;; (melpazoid-misc "'()" "Consider using `nil` instead of `'()`")
  ;; (melpazoid-misc (concat ":group '" (file-name-base (buffer-file-name))) "This :group is unnecessary (it is set implicitly)")
  ;; (melpazoid-misc "line-number-at-pos" "line-number-at-pos is surprisingly slow - avoid it")
  )

(defun melpazoid-misc (regexp msg &optional no-smart-space include-comments)
  "If a search for REGEXP passes, report MSG as a misc check.
If NO-SMART-SPACE is nil, use smart spaces -- i.e. replace all
SPC characters in REGEXP with [[:space:]]+.  If INCLUDE-COMMENTS
then also scan comments for REGEXP."
  (unless no-smart-space
    (setq regexp (replace-regexp-in-string " " "[[:space:]]+" regexp)))
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward regexp nil t)
      (when (or include-comments
                (not (comment-only-p (point-at-bol) (point-at-eol))))
        ;; print a header unless it's already been printed:
        (unless melpazoid--misc-header-printed-p
          (melpazoid-insert "Other static checks/suggestions:")
          (setq melpazoid--misc-header-printed-p t))
        (melpazoid-insert "- %s#L%s: %s"
                          (file-name-nondirectory (buffer-file-name))
                          (line-number-at-pos)
                          msg)))))

(defun melpazoid-insert (f-str &rest objects)
  "Insert F-STR in a way determined by whether we're in script mode.
OBJECTS are objects to interpolate into the string using `format'."
  (let* ((str (concat (melpazoid--string-trim f-str) "\n"))
         (str (apply #'format str objects)))
    (if (melpazoid--running-as-script-p)
        (send-string-to-terminal str)
      (with-current-buffer (get-buffer-create melpazoid-buffer)
        (insert str)))))

(defun melpazoid--string-trim (str)
  "Sanitize STR.  This is like `string-trim' without the 'require'.
\(The 'require' can affect melpazoid's byte-compilation output.)"
  (let* ((str (replace-regexp-in-string "[[:space:]]+$" "" str))
         (str (replace-regexp-in-string "^[[:space:]]+" "" str)))
    str))

;;;###autoload
(defun melpazoid (&optional filename)
  "Check current buffer, or FILENAME's buffer if given."
  (interactive)
  (melpazoid--reset-state)
  (let ((filename (or filename (buffer-file-name (current-buffer)))))
    (melpazoid-insert "\n\n### %s" (file-name-nondirectory filename))
    (save-window-excursion
      (set-buffer (find-file filename))
      (melpazoid-byte-compile filename)
      (melpazoid-checkdoc filename)
      ;; (melpazoid--check-declare)
      (melpazoid-package-lint)
      (melpazoid-check-sharp-quotes)
      (melpazoid-check-misc))
    (pop-to-buffer melpazoid-buffer)
    (goto-char (point-min))))

(defun melpazoid--reset-state ()
  "Reset melpazoid's current state variables."
  (add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/"))
  (add-to-list 'package-archives '("org" . "http://orgmode.org/elpa/"))
  (package-initialize)
  (setq melpazoid--misc-header-printed-p nil)
  (ignore-errors (kill-buffer melpazoid-buffer)))

(defun melpazoid--running-as-script-p ()
  "Whether we think we're running melpazoid as a script.
- MELPAZOID_FILENAME must be set as an environment variable
- We have not been called interactively
- We aren't (somehow) trying to test the melpazoid file"
;; TODO: is there a better way to determine when running inside a script?
  (let ((filename (getenv "MELPAZOID_FILENAME")))
    (and filename
         (not (called-interactively-p 'any))
         (string= (file-name-extension filename) "el")
         (not (string= (file-name-base filename) "melpazoid")))))

(when (melpazoid--running-as-script-p)
  (add-to-list 'load-path (file-name-directory (getenv "MELPAZOID_FILENAME")))
  (melpazoid (getenv "MELPAZOID_FILENAME")))

(provide 'melpazoid)
;;; melpazoid.el ends here
