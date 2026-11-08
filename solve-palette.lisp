#!/usr/bin/env -S sbcl --script
;;;; solve-palette.lisp: work out the colors for a light and a dark theme.
;;;;
;;;;   ./solve-palette.lisp syntax [THEME]  # editor syntax colors (doom/config.el)
;;;;   ./solve-palette.lisp prompt [THEME]  # shell prompt colors (starship/starship.toml)
;;;;   ./solve-palette.lisp diff   [THEME]  # git diff colors (theme/THEME/gitconfig)
;;;;   ./solve-palette.lisp ansi   [THEME]  # terminal colors 1-6 (theme/THEME/ghostty)
;;;;   ./solve-palette.lisp verify [THEME]  # check the colors the configs use now
;;;;
;;;; THEME is light or dark. A solve uses light if you leave it out; verify
;;;; checks both.
;;;;
;;;; The modes don't all want the same thing. Syntax colors are read for hours,
;;;; so they get solid contrast. Prompt and diff colors are glanced at, so they
;;;; only need to clear a contrast minimum and can spend the rest on being
;;;; colorful. On a light background those two pull against each other: the
;;;; most colorful colors are mid-lightness, and every bit of extra contrast
;;;; costs some color.
;;;;
;;;; This file holds the themes, where each color lives in the config files,
;;;; the four modes, and the printing. The measuring and searching are the
;;;; beholder library in src/.

(require :asdf)
(asdf:load-asd (merge-pathnames "beholder.asd" *load-truename*))
(asdf:load-system "beholder")

(defpackage :solve-palette
  (:use :cl :beholder))
(in-package :solve-palette)

;; Seeded so running a mode twice gives the same answer.
(setf *random-state* (sb-ext:seed-random-state 20260722))

;; The usual minimum contrast for text.
(defparameter +aa+ 4.5d0)

;; Where verify finds each color. Verify reads the hex straight out of the
;; config file, so it always checks what's really in use.
;;
;; Each entry is (role file section anchor). Verify looks in FILE, only inside
;; SECTION if there is one, for the first line that isn't commented out and
;; contains ANCHOR, then takes the first #rrggbb after the anchor. A section
;; starts at its opening line: a [header] in TOML and gitconfig, or the
;; custom-theme-set-faces! line in doom/config.el (which has one block per
;; theme).
;;
;; A few things worth knowing:
;; - syn:string and syn:type are picked by hand, not by the solver (see the
;;   README).
;; - tig can only use terminal colors 0-15, so its rows are really the Ghostty
;;   colors. Checking them here stops a palette change from quietly making a
;;   tig color hard to read.
;; - tig's deleted-line color is a fixed bright gold outside the theme, so
;;   there's no row for it.
(defun deployed-sources (&key faces gitconfig palette ghostty)
  (flet ((face   (role anchor) (list role "doom/config.el" faces anchor))
         (git    (role anchor) (list role gitconfig "[color \"diff\"]" anchor))
         (prompt (role anchor) (list role "starship/starship.toml" palette anchor))
         (slot   (role anchor) (list role ghostty nil anchor)))
    (list (face   "syn:keyword"       "font-lock-keyword-face")
          (face   "syn:string"        "font-lock-string-face")
          (face   "syn:function"      "font-lock-function-name-face")
          (face   "syn:type"          "font-lock-type-face")
          (face   "syn:constant"      "font-lock-constant-face")
          (face   "syn:builtin"       "font-lock-builtin-face")
          (git    "git:added"         "new = ")
          (git    "git:removed"       "old = ")
          (prompt "prompt:dir"        "dir ")
          (prompt "prompt:branch"     "branch ")
          (prompt "prompt:alert"      "alert ")
          (prompt "prompt:ok"         "ok ")
          (slot   "tig:add(blue)"     "palette = 4=")
          (slot   "tig:tag(yellow)"   "palette = 3=")
          (slot   "tig:remote(red)"   "palette = 1=")
          (slot   "tig:id(cyan)"      "palette = 6=")
          (slot   "tig:date(magenta)" "palette = 5=")
          (slot   "tig:author(green)" "palette = 2=")
          (slot   "tig:dim(color8)"   "palette = 8="))))

;;; ------------------------------------------------------------------- themes
;;; A theme is a background, the text and comment colors (which every solve
;;; keeps as they are and steers around), the lightness range to search, an
;;; optional contrast ceiling, and where verify finds each color.

(defstruct (theme (:constructor make-theme
                      (&key name bg fg comment light-min light-max ceiling restarts sources)))
  name bg fg comment light-min light-max ceiling restarts sources)

(defparameter *themes*
  (list
   (make-theme
    :name      "light"
    :bg        "#f2e9d8"     ; a warm off-white, like paper
    :fg        "#2f2b25"
    :comment   "#6b6862"     ; a plain gray on purpose; see SOLVE-SYNTAX
    :light-min 0.13d0
    :light-max 0.58d0
    :ceiling   nil
    ;; The current light colors were found with 8. More restarts find a
    ;; different prompt palette that's just as good, so changing this would
    ;; stop the solver matching what's in use.
    :restarts  8
    :sources   (deployed-sources :faces     "(custom-theme-set-faces! 'doom-gruvbox-light"
                                 :gitconfig "theme/light/gitconfig"
                                 :palette   "[palettes.paper]"
                                 :ghostty   "theme/light/ghostty"))
   ;; A muted green-gray. It's easier on the eyes than a navy, which is the
   ;; hardest background to focus on, and it was picked by eye over graphite,
   ;; warm gray, pine, slate and aubergine. The text is a slightly tinted
   ;; off-white.
   ;;
   ;; The ceiling only applies here: no accent may be brighter than the body
   ;; text. On a dark background bright text glows a little, and an accent
   ;; brighter than everything else would be the blurriest word on the line.
   (make-theme
    :name      "dark"
    :bg        "#33362f"
    :fg        "#dbded8"
    :comment   "#9e9e9e"     ; the same contrast as the light theme's comment
    :light-min 0.40d0
    :light-max 0.92d0
    :ceiling   9.04d0        ; the body text's own contrast
    ;; The dark theme tries more colors per slot, so it needs more restarts
    ;; to find a good answer.
    :restarts  40
    :sources   (deployed-sources :faces     "(custom-theme-set-faces! 'doom-gruvbox"
                                 :gitconfig "theme/dark/gitconfig"
                                 :palette   "[palettes.sage]"
                                 :ghostty   "theme/dark/ghostty"))))

;; Print a message and quit with an error.
(defun die (format-string &rest args)
  (format *error-output* "~?~%" format-string args)
  (finish-output *error-output*)
  (sb-ext:exit :code 1))

(defun find-theme (name)
  (or (find name *themes* :key #'theme-name :test #'string=)
      (die "no theme ~S (have: ~{~A~^, ~})" name (mapcar #'theme-name *themes*))))

(defun dark-p (theme)
  (string= (theme-name theme) "dark"))

(defun fixed-colors (theme)
  "The text and comment colors. Solves keep these and make sure the new
colors don't look like them."
  (list (cons "fg" (hex (theme-fg theme)))
        (cons "comment" (hex (theme-comment theme)))))

(defun theme-problem (theme slots targets)
  "A problem for the solver: find SLOTS on THEME's background, TARGETS apart."
  (make-problem :background (hex (theme-bg theme))
                :slots      slots
                :fixed      (fixed-colors theme)
                :targets    targets
                :ceiling    (theme-ceiling theme)
                :grid       (make-grid :light-min (theme-light-min theme)
                                       :light-max (theme-light-max theme))
                :restarts   (theme-restarts theme)))

;;; ----------------------------------------------------------- deployed colors
;;; Reading colors out of the config files.

;; The config file paths above are relative to the directory one level up
;; from this script.
(defparameter *repo-root*
  (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*)))

(defun read-lines (relative-path)
  (with-open-file (stream (merge-pathnames relative-path *repo-root*))
    (loop for line = (read-line stream nil) while line collect line)))

(defun comment-line-p (line)
  "True when LINE is commented out with # or ;."
  (let ((first-visible (position-if-not (lambda (character)
                                          (member character '(#\Space #\Tab)))
                                        line)))
    (and first-visible (member (char line first-visible) '(#\# #\;)))))

(defun section-start-p (line)
  "True when LINE starts a new section: a [header], or a ( at the start of the line."
  (and (plusp (length line)) (member (char line 0) '(#\[ #\())))

(defun section-lines (lines section)
  "The lines inside SECTION, up to where the next one starts. With no SECTION,
all of LINES."
  (if (null section)
      lines
      (let ((lines-after-header
              (rest (member section lines
                            :test (lambda (section-header line)
                                    (string= section-header (string-trim " " line)))))))
        (loop for line in lines-after-header
              until (section-start-p line)
              collect line))))

(defun hex-at-p (line start)
  "True when there's a #rrggbb in LINE at START."
  (and (<= (+ start 7) (length line))
       (char= (char line start) #\#)
       (every (lambda (character) (digit-char-p character 16))
              (subseq line (1+ start) (+ start 7)))))

(defun hex-after (line anchor)
  "The first #rrggbb in LINE after ANCHOR, in lowercase. NIL if there isn't one."
  (let ((anchor-start (search anchor line)))
    (when anchor-start
      (loop for start from (+ anchor-start (length anchor)) below (length line)
            when (hex-at-p line start)
              return (string-downcase (subseq line start (+ start 7)))))))

(defun deployed-hex (file section anchor)
  "The hex FILE uses for ANCHOR right now. NIL if no line matches."
  (loop for line in (section-lines (read-lines file) section)
        for hex-string = (and (not (comment-line-p line)) (hex-after line anchor))
        when hex-string return hex-string))

(defun deployed-colors (theme)
  "Every color THEME uses, read from the config files, plus the text and
comment colors from the theme itself."
  (append (fixed-colors theme)
          (loop for (role file section anchor) in (theme-sources theme)
                for hex-string = (deployed-hex file section anchor)
                unless hex-string
                  do (die "verify: no color for ~A: no uncommented line in ~A~@[ under ~A~] contains ~S"
                          role file section anchor)
                collect (cons role (hex hex-string)))))

;;; ------------------------------------------------------------------ printing

(defun by-role (alist)
  (sort (copy-alist alist) #'string< :key #'car))

;; One line per solved color, then how well the targets were met and which
;; two colors ended up looking most alike.
(defun print-result (theme result)
  (let ((background (hex (theme-bg theme))))
    (format t "theme: ~A (background ~A)~%" (theme-name theme) (theme-bg theme))
    (format t "~%~10A ~9A ~7@A ~9@A ~7@A~%" "role" "hex" "C*" "contrast" "L*")
    (loop for (role . color) in (by-role (result-palette result))
          do (format t "~10A ~9A ~7,1F ~8,2F:1 ~7,1F~%"
                     role (color-hex color) (chroma color)
                     (worst-contrast color background) (lstar color)))
    (format t "~%feasibility: ~,1F% of the tightest pair's target~%"
            (* 100 (result-feasibility result)))
    (format t "weakest pair (worst observer): ~{~A~^/~} at ~,1F dE~%"
            (result-weakest-pair result) (result-weakest-de result))))

(defun solve-and-report (theme &key slots targets)
  (print-result theme (solve (theme-problem theme slots targets))))

;;; ---------------------------------------------------------------------- modes
;;; Each slot below reads (name lowest-hue highest-hue min-contrast
;;; max-saturation min-chroma).

(defun syntax-slots-light ()
  (list (slot "keyword"  272 322 5.0d0 0.78d0 46d0)
        (slot "string"   100 165 5.0d0 0.98d0 44d0)
        (slot "function" 200 238 5.5d0 0.80d0 44d0)
        (slot "type"      28  58 5.0d0 0.98d0 40d0)
        (slot "constant"   0  24 5.0d0 0.98d0 44d0)
        ;; Teal and blue are the hardest colors for the eye to focus sharply,
        ;; so they get a bit more contrast to make up for it.
        (slot "builtin"  172 198 5.5d0 0.95d0 18d0)))

;; The dark theme keeps each token in the same color family as the light
;; theme's configs (orange strings, magenta types), so switching themes
;; doesn't reshuffle what's what.
;;
;; Function is green here rather than blue. Blue functions and violet keywords
;; looked too alike, and those two sit next to each other in every language.
;; Their target is raised to 35 to keep them well apart.
(defun syntax-slots-dark ()
  (list (slot "keyword"  250 300 5.0d0 0.98d0 40d0)
        (slot "string"    18  40 5.0d0 1.00d0 44d0)
        (slot "function" 120 165 5.5d0 0.95d0 40d0)
        (slot "type"     305 335 5.0d0 1.00d0 40d0)
        (slot "constant"   0  14 5.0d0 1.00d0 40d0)
        (slot "builtin"  172 198 5.5d0 0.95d0 18d0)))

;; The most common tokens get the most distinct colors, so keywords are violet
;; rather than the more usual amber.
;;
;; Comments are a plain gray because a warm gray ended up looking too much like
;; the green strings. Making it neutral left the strings room to be much more
;; colorful.
(defun solve-syntax (theme)
  (solve-and-report theme
   :slots (if (dark-p theme) (syntax-slots-dark) (syntax-slots-light))
   :targets (syntax-targets (dark-p theme))))

;; How far apart each pair of syntax colors should look. Keyword and function
;; are 16 on light (20 pushed function to a near-navy) and 35 on dark.
(defun syntax-targets (dark)
  (targets 16 `(("keyword" "string"   22)
                ("keyword" "function" ,(if dark 35 16))
                ("keyword" "constant" 20)
                ("string"  "function" 20)
                ("string"  "constant" 20)
                ("string"  "type"     18)
                ("comment" "string"   14))))

;; Prompt and diff colors are glanced at rather than read, so they only need
;; to clear a contrast minimum (4.6 for the prompt, 5.0 for diffs, a bit more
;; for blue) and can otherwise be as colorful as possible.
;;
;; Blue against orange is the pair that matters most here: added vs removed in
;; a diff, directory vs error in the prompt.

;; git only colors added and removed lines.
(defun solve-diff (theme)
  (solve-and-report theme
   :slots (list (slot "blue" 205 224 5.5d0 0.90d0 40d0)
                (slot "warm"   8  26 5.0d0 1.00d0 44d0))
   :targets (targets 16 '(("blue" "warm" 40)))))

;; The prompt colors the directory, branch, errors and ok. The directory uses
;; the same blue as diffs, so there's one blue everywhere.
(defun solve-prompt (theme)
  (solve-and-report theme
   :slots (list (slot "blue" 205 224 5.5d0 0.90d0 40d0)
                (slot "warm"   8  26 4.6d0 1.00d0 44d0)
                (slot "gold"  34  50 4.6d0 1.00d0 44d0)
                (slot "teal" 188 204 4.6d0 1.00d0 20d0))
   :targets (targets 16 '(("blue" "warm" 40)
                          ("blue" "gold" 30)
                          ("gold" "warm" 14)
                          ("teal" "warm" 30)
                          ("teal" "gold" 20)
                          ("teal" "blue" 14))))
  (format t "~%note: `gold` and `warm` are the collision-prone pair: they both~%~
             collapse toward olive under dichromacy, so they are separated by~%~
             LIGHTNESS rather than hue. Keep one clearly darker than the other.~%"))

;; Terminal colors 1-6. Every terminal program draws with these, so they need
;; the same care as the editor colors. Each one stays close enough to its name
;; that a program asking for "red" gets something reddish, but green leans
;; teal and cyan leans sky blue, which keeps them apart from red and yellow.
;;
;; Red against green matters most: in a terminal that's error vs success.
;;
;; The light theme's terminal colors were picked separately before this mode
;; existed, so this is for the dark theme.
;;
;; Green and magenta have higher chroma minimums so "ok" and "passed" don't
;; look washed out. That costs some distance between colors (cyan and magenta
;; end up closest), which was checked by eye and is fine.
(defun solve-ansi (theme)
  (solve-and-report theme
   :slots (list (slot "red"       0  24 4.6d0 1.00d0 40d0)
                (slot "green"   150 180 4.6d0 1.00d0 50d0)
                (slot "yellow"   34  58 4.6d0 1.00d0 40d0)
                (slot "blue"    210 235 5.1d0 1.00d0 40d0)
                (slot "magenta" 270 320 4.6d0 1.00d0 65d0)
                (slot "cyan"    185 205 4.6d0 1.00d0 25d0))
   :targets (targets 14 '(("red"  "green"   36)
                          ("blue" "magenta" 18)
                          ("red"  "yellow"  18)
                          ("blue" "cyan"    16)))))

;;; --------------------------------------------------------------------- verify

(defun print-measure (measure)
  (format t "~18A ~9A ~8,2F:1 ~7,1F ~7,1F ~A~%"
          (measure-role measure)
          (color-hex (measure-color measure))
          (measure-worst-contrast measure)
          (measure-chroma measure)
          (measure-lstar measure)
          (if (measure-passed-p measure) "" "<-- BELOW AA")))

(defun verify-deployed (theme)
  "Check the colors THEME uses now. Returns how many have too little contrast."
  (format t "~%theme: ~A (background ~A)~%" (theme-name theme) (theme-bg theme))
  (format t "~18A ~9A ~9@A ~7@A ~7@A~%" "role" "hex" "contrast" "C*" "L*")
  (let ((report (assess (hex (theme-bg theme))
                        (by-role (deployed-colors theme))
                        (make-policy :floor +aa+))))
    (mapc #'print-measure (report-measures report))
    (format t "~A~%"
            (if (plusp (report-failures report))
                (format nil "~D color(s) BELOW AA for some observer" (report-failures report))
                "all colors clear AA for normal, protan and deutan observers"))
    (report-failures report)))

;;; ------------------------------------------------------------------------ main

;; solve-palette.lisp [MODE [THEME]]. Verify exits with an error when any color
;; fails, so a pre-commit hook can run it.
(defun main (args)
  (let* ((mode   (or (first args) "verify"))
         (named  (second args))
         (themes (if named (list (find-theme named)) *themes*))
         (one    (find-theme (or named "light"))))
    (handler-case
        (cond ((string= mode "syntax") (solve-syntax one))
              ((string= mode "prompt") (solve-prompt one))
              ((string= mode "diff")   (solve-diff one))
              ((string= mode "ansi")   (solve-ansi one))
              ((string= mode "verify")
               (let ((failures (loop for theme in themes sum (verify-deployed theme))))
                 (sb-ext:exit :code (if (plusp failures) 1 0))))
              (t (die "usage: solve-palette.lisp [syntax|prompt|diff|ansi|verify] [light|dark]")))
      (infeasible-slot (condition) (die "~A" condition)))))

(main (rest sb-ext:*posix-argv*))
