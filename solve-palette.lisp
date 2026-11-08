#!/usr/bin/env -S sbcl --script
;;;; solve-palette.lisp: regenerate the theme palettes from first principles.
;;;;
;;;;   ./color/solve-palette.lisp syntax [THEME]  # doom/config.el font-lock faces
;;;;   ./color/solve-palette.lisp prompt [THEME]  # starship/starship.toml [palettes.paper|sage]
;;;;   ./color/solve-palette.lisp diff   [THEME]  # theme/THEME/gitconfig [color "diff"]
;;;;   ./color/solve-palette.lisp ansi   [THEME]  # theme/THEME/ghostty slots 1-6
;;;;   ./color/solve-palette.lisp verify [THEME]  # re-measure what is deployed
;;;;
;;;; THEME is light (the default for a solve) or dark; verify with no THEME
;;;; measures both. See *THEMES* for what differs between them.
;;;;
;;;; There are two objectives because sitting down and coding isn't one thing all
;;;; the time.
;;;;
;;;; For things I do longer (read text and syntax) I'm solving for CONTRAST.
;;;; For shorter things (prompts, diffs, statuses) it's CHROMA subject to a FLOOR.
;;;;
;;;; Every ratio above the floor is contrast that's not used. On light backgrounds
;;;; it's paid for in colorfulness. sRGB's most chromatic colors are at middle-ish
;;;; lightness. I've been getting this backwards making themes and it's looked
;;;; absolutely awful.
;;;;
;;;; Hard constraint: Colorblindness so the hue circle collapses into a single
;;;; blue-yellow line.
;;;; Then I scored each palette on its worst-case separation (normal +
;;;; the two red/green colorblindness). The contrast is registered on all three
;;;; too.

(load (merge-pathnames "colorlib.lisp" *load-truename*))

(defpackage :solve-palette
  (:use :cl :colorlib))
(in-package :solve-palette)

(declaim (optimize (speed 3) (safety 1)))

(setf *random-state* (sb-ext:seed-random-state 20260722))

;; HSL sweep grid for each slot's hue band. The lightness band is per theme.
(defparameter +hue-stride+ 3)                          ; keep every 3rd degree because they're near identical
(defparameter +sat-min+    0.34d0)                     ; max is per-slot (smax)
(defparameter +sat-step+   0.05d0)
(defparameter +light-step+ 0.008d0)

;; Search knobs; see the objective note above SLOT-FEASIBILITY. The number of
;; random restarts (the search is not convex) is per theme.
(defparameter +max-passes+         7)      ; coordinate-descent sweeps per restart
(defparameter +improve-eps+        1d-9)   ; ignore float noise when comparing scores
(defparameter +feasibility-weight+ 1000d0) ; >> any achievable mean chroma, so it dominates

(defparameter +aa+ 4.5d0)

;; Re-measure what is actually deployed. Run this after ANY palette edit.
;;
;; Each role names WHERE its color lives, not the color itself: verify reads
;; the hex out of the config file at run time, so it measures what is really
;; deployed. (It used to measure a hand-copied table here, which drifted twice.)
;; A source is (role file section anchor): the first uncommented line in FILE
;; that contains ANCHOR, searched only inside SECTION when one is given, and
;; the first #rrggbb after the anchor on that line.
;;
;; syn:string and syn:type are the hand-tuned faces in doom/config.el (see
;; color/README.md), not the solver's green and olive.
;;
;; tig can only reach the theme through named ANSI slots 0-15 (it rejects hex,
;; and 16-255 is the fixed xterm cube), so its colors ARE the Ghostty slot
;; hexes used as foregrounds on the paper. tig/tigrc maps each role to one of
;; these; measured here so a palette edit that darkens a slot cannot silently
;; push a tig role below AA. Bars in tig invert default/default rather than
;; paint a slot, so they carry the theme's own fg/bg contrast and need no row.
;; tig:del deliberately uses an OFF-PALETTE bright gold (256-cube color220) so
;; removed lines are bright, not near-black, for a color-vision reason (see
;; tig/tigrc); it is not theme-tracked, so no row.
;;
;; Both themes deploy the same roles, so the table is written once and each
;; theme fills in its own files and sections. A section is the line that opens
;; it: a [header] in TOML and gitconfig, or the `(custom-theme-set-faces!' line
;; that scopes a face block to one Doom theme (doom/config.el has one block per
;; theme, with the same face names in each).
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
;;; A theme is a background, the two colors every solve holds fixed without
;;; solving for them (body ink and the comment gray), the HSL lightness band the
;;; sweep covers, an optional contrast CEILING, and where verify finds each
;;; deployed color. Every mode runs against one theme, bound to *THEME*.

(defstruct (theme (:constructor make-theme
                      (&key name bg fg comment light-min light-max ceiling restarts sources)))
  name bg fg comment light-min light-max ceiling restarts sources)

(defparameter *themes*
  (list
   (make-theme
    :name      "light"
    :bg        "#f2e9d8"     ; warm paper; see theme/light/ghostty for the derivation
    :fg        "#2f2b25"
    :comment   "#6b6862"     ; NEUTRAL on purpose; see note in the syntax section
    :light-min 0.13d0
    :light-max 0.58d0
    :ceiling   nil
    ;; The deployed paper values were found at 8; more restarts find a
    ;; different (also feasible) prompt, so raising this would stop the
    ;; solver reproducing what starship.toml ships.
    :restarts  8
    :sources   (deployed-sources :faces     "(custom-theme-set-faces! 'doom-gruvbox-light"
                                 :gitconfig "theme/light/gitconfig"
                                 :palette   "[palettes.paper]"
                                 :ghostty   "theme/light/ghostty"))
   ;; Sage, a muted green-gray (L* 22.1, C* 4.9, hue 126). It replaced
   ;; TokyoNight Storm (#24283b), a navy, on 2026-11-08: a blue field is the
   ;; worst-focused one (theme/light/ghostty, constraint 3), and sage is
   ;; brighter than Storm (L* 22.1 against 16.5), which masks halation further.
   ;; The paper's own warm hue inverted (#37302a) was tried first and read as
   ;; brown at every lightness; sage was picked by eye over graphite, warm
   ;; gray, pine, slate and aubergine. The ink is a faintly tinted off-white at
   ;; ~9:1, Storm's ratio. The comment is a NEUTRAL gray for the same reason
   ;; as on paper, at the same AA floor.
   ;;
   ;; The CEILING is the dark-only constraint: no accent may outshine body text.
   ;; On a dark field a bright glyph blooms (astigmatic halation), and the
   ;; brightest thing on screen blooms most, so a saturated accent brighter than
   ;; the prose would be the blurriest word on the line. Paper has no ceiling:
   ;; dark ink on a light field spreads dark into light, which does not bloom.
   (make-theme
    :name      "dark"
    :bg        "#33362f"
    :fg        "#dbded8"
    :comment   "#9e9e9e"     ; 4.59:1, matching paper's 4.59
    :light-min 0.40d0
    :light-max 0.92d0
    :ceiling   9.04d0        ; the ink's own contrast
    ;; The wider lightness band makes bigger pools; on Storm the ANSI solve
    ;; stopped at 85.1% with 8 restarts and reached 95.7% with 40.
    :restarts  40
    :sources   (deployed-sources :faces     "(custom-theme-set-faces! 'doom-gruvbox"
                                 :gitconfig "theme/dark/gitconfig"
                                 :palette   "[palettes.sage]"
                                 :ghostty   "theme/dark/ghostty"))))

(defvar *theme*)
(defvar *bg*)

(defun find-theme (name)
  (or (find name *themes* :key #'theme-name :test #'string=)
      (die "no theme ~S (have: ~{~A~^, ~})" name (mapcar #'theme-name *themes*))))

(defun call-with-theme (theme fn)
  (let ((*theme* theme)
        (*bg*    (hex2lin (theme-bg theme))))
    (funcall fn)))

(defun fixed-colors ()
  "The colors every solve must stay distinguishable from without solving for
them: the body foreground and the comment gray."
  (list (cons "fg" (theme-fg *theme*)) (cons "comment" (theme-comment *theme*))))

(defparameter *repo-root*
  (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*)))

(defun read-lines (relative-path)
  (with-open-file (in (merge-pathnames relative-path *repo-root*))
    (loop for line = (read-line in nil) while line collect line)))

(defun comment-line-p (line)
  "True when LINE's first non-blank character starts a comment (# or ;)."
  (let ((start (position-if-not (lambda (c) (member c '(#\Space #\Tab))) line)))
    (and start (member (char line start) '(#\# #\;)))))

(defun section-start-p (line)
  "True when LINE opens a section: a [header], or a top-level ( form."
  (and (plusp (length line)) (member (char line 0) '(#\[ #\())))

(defun section-lines (lines section)
  "LINES from just after the SECTION line up to the next section start; all
LINES when SECTION is NIL."
  (if (null section)
      lines
      (let ((after (rest (member section lines
                                 :test (lambda (s l) (string= s (string-trim " " l)))))))
        (loop for line in after
              until (section-start-p line)
              collect line))))

(defun hex-at-p (line pos)
  "True when LINE holds a #rrggbb starting at POS."
  (and (<= (+ pos 7) (length line))
       (char= (char line pos) #\#)
       (every (lambda (c) (digit-char-p c 16)) (subseq line (1+ pos) (+ pos 7)))))

(defun hex-after (line anchor)
  "The first #rrggbb in LINE after ANCHOR, downcased, or NIL."
  (let ((from (search anchor line)))
    (when from
      (loop for pos from (+ from (length anchor)) below (length line)
            when (hex-at-p line pos)
              return (string-downcase (subseq line pos (+ pos 7)))))))

(defun deployed-hex (file section anchor)
  "The hex FILE currently deploys for ANCHOR, or NIL when no line matches."
  (loop for line in (section-lines (read-lines file) section)
        for hex = (and (not (comment-line-p line)) (hex-after line anchor))
        when hex return hex))

(defun deployed-colors ()
  "Every measured role paired with the hex read from its config file. fg and
comment are the solver's own inputs, so they come from the constants above."
  (append (fixed-colors)
          (loop for (role file section anchor) in (theme-sources *theme*)
                for hex = (deployed-hex file section anchor)
                unless hex
                  do (die "verify: no color for ~A: no uncommented line in ~A~@[ under ~A~] contains ~S"
                          role file section anchor)
                collect (cons role hex))))

(defun die (format-string &rest args)
  (format *error-output* "~?~%" format-string args)
  (finish-output *error-output*)
  (sb-ext:exit :code 1))

;;; Sweep each slot's hue band in HSL and keep every color that clears.
;;; I use HSL because it's easy here. All the judging happens in CIELAB.

;; A slot is a hue band plus its hard constraints: a contrast floor every color
;; must clear for the worst observer, a saturation cap, and a chroma minimum.
(defstruct (slot (:constructor slot (name hue-low hue-high floor smax &optional (cmin 0d0))))
  (name     ""  :type string)
  (hue-low  0   :type fixnum)
  (hue-high 0   :type fixnum)
  (floor    0d0 :type double-float)
  (smax     0d0 :type double-float)
  (cmin     0d0 :type double-float))

;; The surviving candidates for one slot: search scores (profile, chroma)
;; and the linear RGB kept to emit the winner.
(defstruct pool
  (profiles #()                                         :type simple-vector)
  (chromas  (make-array 0 :element-type 'double-float)  :type (simple-array double-float (*)))
  (rgbs     #()                                         :type simple-vector))

(defun pool-size (pool)
  (length (pool-profiles pool)))

(defun slot-hues (slot)
  "The hue degrees this slot searches, snapped to the stride."
  (loop for hue from (* +hue-stride+ (ceiling (slot-hue-low slot) +hue-stride+))
          to (slot-hue-high slot) by +hue-stride+
        collect hue))

(defun slot-grid (slot)
  "Every HSL point in the slot's band, as linear RGB."
  (loop for hue in (slot-hues slot)
        nconc (loop for sat from +sat-min+ to (slot-smax slot) by +sat-step+
                    nconc (loop for light from (theme-light-min *theme*)
                                  to (theme-light-max *theme*) by +light-step+
                                collect (hsl2lin hue sat light)))))

(defun under-ceiling-p (rgb)
  "True when RGB is no brighter against the background than the theme allows.
The ceiling is about emitted light, so it uses the normal observer's contrast."
  (let ((ceiling (theme-ceiling *theme*)))
    (or (null ceiling) (<= (contrast-ratio rgb *bg*) ceiling))))

(defun slot-admits-p (slot rgb)
  "The slot's hard constraints. Contrast is checked for the WORST of the three observers"
  (and (>= (worst-contrast rgb *bg*) (slot-floor slot))
       (under-ceiling-p rgb)
       (>= (chroma rgb) (slot-cmin slot))))

(defun candidates-for-slot (slot)
  (let ((kept (remove-if-not (lambda (rgb) (slot-admits-p slot rgb))
                             (slot-grid slot))))
    (when (null kept)
      (die "slot ~A: no candidates; constraints are infeasible" (slot-name slot)))
    (make-pool :profiles (map 'simple-vector #'profile kept)
               :chromas  (map '(simple-array double-float (*)) #'chroma kept)
               :rgbs     (coerce kept 'simple-vector))))

;;; The required dE between a pair of roles, with a default for every pair not
;;; named. Roles are stored in sorted order, so a lookup finds its entry
;;; whichever way round it is asked for.

(defstruct (targets (:constructor make-targets (default table)))
  (default 16d0 :type double-float)
  (table   (make-hash-table :test #'equal) :type hash-table))

(defun pair-key (a b)
  (if (string> a b)
      (format nil "~A|~A" b a)
      (format nil "~A|~A" a b)))

(defun targets (default pairs)
  "PAIRS is a list of (ROLE-A ROLE-B REQUIRED-DE); order within a pair is free."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (pair pairs)
      (destructuring-bind (a b required) pair
        (setf (gethash (pair-key a b) table) (float required 1d0))))
    (make-targets (float default 1d0) table)))

(defun target-for (targets a b)
  (gethash (pair-key a b) (targets-table targets) (targets-default targets)))

;;; One solve, with every string lookup already done ahead of time.
(defstruct problem
  (names          #() :type simple-vector)
  (pools          #() :type simple-vector)
  (fixed-profiles #() :type simple-vector)
  (pair-target    (make-array '(0 0) :element-type 'double-float)
   :type (simple-array double-float (* *)))
  (fixed-target   (make-array '(0 0) :element-type 'double-float)
   :type (simple-array double-float (* *))))

(declaim (inline problem-size problem-n-fixed choice-profile choice-chroma))

(defun problem-size (problem)
  (length (problem-names problem)))

(defun problem-n-fixed (problem)
  (length (problem-fixed-profiles problem)))

;; An assignment (IDX below) is one candidate index per slot; these read the
;; color it currently picks for slot I.
(defun choice-profile (problem idx i)
  (svref (pool-profiles (svref (problem-pools problem) i)) (aref idx i)))

(defun choice-chroma (problem idx i)
  (aref (pool-chromas (svref (problem-pools problem) i)) (aref idx i)))

(defun choice-rgb (problem idx i)
  (svref (pool-rgbs (svref (problem-pools problem) i)) (aref idx i)))

(defun pair-target-table (names targets)
  "Required dE between every two solved roles."
  (let ((table (make-array (list (length names) (length names))
                           :element-type 'double-float :initial-element 0d0)))
    (dotimes (i (length names) table)
      (loop for j from (1+ i) below (length names)
            do (setf (aref table i j)
                     (target-for targets (svref names i) (svref names j)))))))

(defun fixed-target-table (names fixed targets)
  "Required dE between every solved role and every fixed color."
  (let ((table (make-array (list (length names) (length fixed))
                           :element-type 'double-float :initial-element 0d0)))
    (dotimes (i (length names) table)
      (loop for f from 0 below (length fixed)
            do (setf (aref table i f)
                     (target-for targets (svref names i) (car (nth f fixed))))))))

(defun build-problem (slots targets fixed)
  (let ((names (map 'simple-vector #'slot-name slots)))
    (make-problem
     :names          names
     :pools          (map 'simple-vector #'candidates-for-slot slots)
     :fixed-profiles (map 'simple-vector (lambda (f) (profile (hex2lin (cdr f)))) fixed)
     :pair-target    (pair-target-table names targets)
     :fixed-target   (fixed-target-table names fixed targets))))

;;; So it optimizes this (after filtering the constraints)
;;;     feasibility * 1000 + mean_chroma
;;;
;;; Feasibility obviously dominates (don't bark up the wrong tree). So the search first satisfies
;;; every pairwise separation target and only then spends what is left on colorfulness.

(defun slot-feasibility (problem idx i)
  "Worst ratio of achieved separation to required separation between slot I's
pick and everything it is measured against: the fixed colors, and the slots
after it (so each unordered pair is visited once)."
  (let ((p     (choice-profile problem idx i))
        (worst most-positive-double-float))
    (declare (type double-float worst))
    (dotimes (f (problem-n-fixed problem))
      (setf worst (min worst (/ (separation p (svref (problem-fixed-profiles problem) f))
                                (aref (problem-fixed-target problem) i f)))))
    (loop for j from (1+ i) below (problem-size problem)
          do (setf worst (min worst (/ (separation p (choice-profile problem idx j))
                                       (aref (problem-pair-target problem) i j)))))
    worst))

(defun feasibility (problem idx)
  "The worst such ratio over the whole assignment, so 1.0 means every target is
met. SCORE caps it at 1, so overshooting one pair cannot buy slack elsewhere."
  (let ((worst most-positive-double-float))
    (declare (type double-float worst))
    (dotimes (i (problem-size problem) worst)
      (setf worst (min worst (slot-feasibility problem idx i))))))

(defun mean-chroma (problem idx)
  (/ (loop for i below (problem-size problem)
           sum (choice-chroma problem idx i))
     (problem-size problem)))

(defun score (problem idx)
  "Feasibility first; only once it is capped does mean chroma break the tie."
  (+ (* (min (feasibility problem idx) 1d0) +feasibility-weight+)
     (mean-chroma problem idx)))

(defun random-assignment (problem)
  "A random candidate index per slot: where one restart starts from."
  (let ((idx (make-array (problem-size problem) :element-type 'fixnum)))
    (dotimes (i (problem-size problem) idx)
      (setf (aref idx i) (random (pool-size (svref (problem-pools problem) i)))))))

(defun improve-slot (problem idx i current)
  "Coordinate descent: hold every other slot fixed and try every candidate for
slot I, leaving IDX on the winner. Returns the score that winner scored."
  (let ((best-k (aref idx i))
        (best   current))
    (dotimes (k (pool-size (svref (problem-pools problem) i)))
      (setf (aref idx i) k)
      (let ((s (score problem idx)))
        (when (> s (+ best +improve-eps+))
          (setf best   s
                best-k k))))
    (setf (aref idx i) best-k)                 ; put the slot back on its winner
    best))

(defun sweep (problem idx current)
  "One descent pass over every slot. Returns the score after it."
  (dotimes (i (problem-size problem) current)
    (setf current (improve-slot problem idx i current))))

(defun descend (problem idx)
  "Sweep until a pass changes nothing (further passes then change nothing
either). Returns the final score, with IDX left on the assignment that earned it."
  (let ((current (score problem idx)))
    (dotimes (pass +max-passes+ current)
      (let ((next (sweep problem idx current)))
        (when (<= next (+ current +improve-eps+))
          (return next))                       ; converged
        (setf current next)))))

(defun palette (problem idx)
  (loop for i below (problem-size problem)
        collect (cons (svref (problem-names problem) i)
                      (lin2hex (choice-rgb problem idx i)))))

(defun solve (&key slots targets fixed)
  "Fill SLOTS subject to TARGETS. FIXED is an alist of (ROLE . HEX) for colors we
are not solving for but must stay distinguishable from. Returns an alist of
(ROLE . HEX), the winning score, and that score's feasibility."
  (let ((problem    (build-problem slots targets fixed))
        (best-idx   nil)
        (best-score -1d0))
    (dotimes (restart (theme-restarts *theme*))
      (let* ((idx   (random-assignment problem))
             (final (descend problem idx)))
        (when (> final best-score)
          (setf best-score final
                best-idx   idx))))
    (values (palette problem best-idx)
            best-score
            (/ (- best-score (mean-chroma problem best-idx)) +feasibility-weight+))))

(defun closest-pair (entries)
  "The closest pair in ENTRIES (an alist of (ROLE . HEX)) as seen by whichever
observer sees them as closest. Returns its label and its dE."
  (let ((roles    (map 'simple-vector #'car entries))
        (profiles (map 'simple-vector (lambda (e) (profile (hex2lin (cdr e)))) entries))
        (closest  most-positive-double-float)
        (pair     ""))
    (dotimes (i (length roles))
      (loop for j from (1+ i) below (length roles)        ; each unordered pair once
            for d = (separation (svref profiles i) (svref profiles j))
            when (< d closest)
              do (setf closest d
                       pair    (format nil "~A/~A" (svref roles i) (svref roles j)))))
    (values pair closest)))

(defun by-role (alist)
  (sort (copy-alist alist) #'string< :key #'car))

;; Print the solved colors, then the single closest pair in the whole palette
;; (solved plus fixed).
(defun report (out fixed feasibility)
  (format t "~%~10A ~9A ~7@A ~9@A ~7@A~%" "role" "hex" "C*" "contrast" "L*")
  (dolist (entry (by-role out))
    (let ((c (hex2lin (cdr entry))))
      (format t "~10A ~9A ~7,1F ~8,2F:1 ~7,1F~%"
              (car entry) (cdr entry) (chroma c) (worst-contrast c *bg*) (lstar c))))
  (multiple-value-bind (pair closest)
      (closest-pair (by-role (append out fixed)))
    (format t "~%feasibility: ~,1F% of the tightest pair's target~%" (* 100 feasibility))
    (format t "weakest pair (worst observer): ~A at ~,1F dE~%" pair closest)))

(defun solve-and-report (&key slots targets)
  (multiple-value-bind (out score feasibility)
      (solve :slots slots :targets targets :fixed (fixed-colors))
    (declare (ignore score))
    (format t "theme: ~A (background ~A)~%" (theme-name *theme*) (theme-bg *theme*))
    (report out (fixed-colors) feasibility)))

;;; ---------------------------------------------------------------------- modes

(defun syntax-slots-light ()
  (list (slot "keyword"  272 322 5.0d0 0.78d0 46d0)
        (slot "string"   100 165 5.0d0 0.98d0 44d0)
        (slot "function" 200 238 5.5d0 0.80d0 44d0)
        (slot "type"      28  58 5.0d0 0.98d0 40d0)
        (slot "constant"   0  24 5.0d0 0.98d0 44d0)
        ;; builtin/teal keeps a raised floor: at 450-490nm it
        ;; sits 0.4-0.8 D behind best focus, so only its
        ;; luminance edge survives the blur.
        (slot "builtin"  172 198 5.5d0 0.95d0 18d0)))

;; Dark solves the hue assignment paper actually DEPLOYS (orange strings and
;; magenta types, hand-tuned there; see color/README.md), not the bands the
;; light solve above started from, so a token keeps its hue family when the
;; theme flips. Keyword and function get wider bands than paper's: under the
;; brightness ceiling every accent sits in a strip about 17 L* wide below
;; the ink, and that strip has to hold violet and indigo apart. Measured
;; 2026-11-08 on the earlier Storm background: paper's bands reached 93.8%
;; (weakest function/keyword, 15.0 dE), these 98.2%. (Since superseded for
;; function; see below.)
;;
;; Function then LEFT the blue family on sage (2026-11-08): keyword and
;; function still merged by eye, because violet is blue plus the red channel a
;; dichromat loses, and these two sit side by side in every language. Function
;; takes green, which a dichromat sees as yellow, the far end of the one axis
;; left, and the pair's target is raised to 35 (see `syntax-targets'). Raising
;; the target with function still blue reached only 52.6%; green reaches 93.7%.
(defun syntax-slots-dark ()
  (list (slot "keyword"  250 300 5.0d0 0.98d0 40d0)
        (slot "string"    18  40 5.0d0 1.00d0 44d0)
        (slot "function" 120 165 5.5d0 0.95d0 40d0)
        (slot "type"     305 335 5.0d0 1.00d0 40d0)
        (slot "constant"   0  14 5.0d0 1.00d0 40d0)
        (slot "builtin"  172 198 5.5d0 0.95d0 18d0)))

(defun solve-syntax ()
  ;; Hue bands are assigned BY TOKEN FREQUENCY, not by tradition. Because
  ;; my colorblindness flattens hue to one axis, the richest and most separable bands
  ;; must go to the stuff I look at most. Keywords therefore take VIOLET
  ;; rather than the customary amber, and types take the olive slot; swapping
  ;; those two was worth +302% chroma on keywords and moved the solution from
  ;; 97% to 100% of its separation targets.
  ;;
  ;; Comments are fixed to a NEUTRAL gray. A warm comment and a green string
  ;; both land on olive under deuteranope simulation, which capped strings at
  ;; +12% chroma; neutralizing the comment freed the entire green band.
  (let ((dark (string= (theme-name *theme*) "dark")))
    (solve-and-report
     :slots (if dark (syntax-slots-dark) (syntax-slots-light))
     :targets (syntax-targets dark))))

(defun syntax-targets (dark)
  (targets 16 `(("keyword" "string"   22)
                ;; Paper: 16, not 20: the deployed violet/blue pair measures
                ;; 16.2 for the worst observer and reads fine in daily use; 20
                ;; forced a near-navy function color. Dark: 35, since 13-18
                ;; merged by eye (see `syntax-slots-dark').
                ("keyword" "function" ,(if dark 35 16))
                ("keyword" "constant" 20)
                ("string"  "function" 20)
                ("string"  "constant" 20)
                ("string"  "type"     18)
                ("comment" "string"   14))))

;; Prompt and diff: glanced-at surfaces. Chroma is the objective here and
;; contrast is only a floor: 4.6 for the prompt (a few bold words), 5.0 for
;; diffs (bulk text). Blue gets +0.5 on top, for the same focus reason as the
;; builtin slot. Each mode models exactly the roles its surface paints.
;;
;; blue-vs-warm is the pair that must never fail: added/removed in a diff,
;; directory/error in a prompt. It rides the blue-yellow axis, which red/green
;; deficiency leaves fully intact.

;; git paints two content colors (git/.gitconfig: new and old; meta and frag are
;; neutral on purpose), so there is no gold here to push warm darker.
(defun solve-diff ()
  (solve-and-report
   :slots (list (slot "blue" 205 224 5.5d0 0.90d0 40d0)
                (slot "warm"   8  26 5.0d0 1.00d0 44d0))
   :targets (targets 16 '(("blue" "warm" 40)))))

;; starship paints dir, branch, alert/err and ok (starship/starship.toml). dir
;; shares the diff's cobalt, so its floor is the diff blue's 5.5, not 4.6 + 0.5:
;; one blue across git, Emacs and the prompt.
(defun solve-prompt ()
  (solve-and-report
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

;; Ghostty's ANSI slots 1-6. Every TUI reaches the theme through these (tig,
;; ls, git's named meta/frag colors), so they carry the same collision risk as
;; the editor and must be solved the same way. The hue bands keep each slot's
;; NAME honest enough that a program asking for "red" still gets a warm color,
;; but green is a teal and cyan a sky blue, which moves both onto the
;; blue-yellow axis that red/green deficiency leaves intact.
;;
;; red/green is the pair that matters most: in a terminal it is error vs
;; success. blue/magenta is next: TokyoNight Storm's stock pair, the dark
;; palette before this one, measured 0.1 dE for a protan observer, i.e. one
;; color.
;;
;; theme/light/ghostty predates this mode and was solved separately; treat its
;; values as authoritative and run this for the dark theme.
;;
;; Green and magenta carry raised chroma minimums, chosen by eye on sage
;; (2026-11-08). Without them the solve reaches 94% by keeping both pale (green
;; C* 33), and "ok" and "passed" read washed out. With them it reaches 75.5%:
;; blue moves to a sky blue to make room, and the closest pair is cyan/magenta
;; at 11.0 dE for the worst observer. That pair was looked at and does not
;; clash for me, so the separation is spent on color here on purpose.
(defun solve-ansi ()
  (solve-and-report
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

(defun measure (role hex)
  "Print one measured row. Returns T if it clears AA for every observer."
  (let* ((c    (hex2lin hex))
         (r    (worst-contrast c *bg*))
         (pass (>= r +aa+)))
    (format t "~18A ~9A ~8,2F:1 ~7,1F ~7,1F ~A~%"
            role hex r (chroma c) (lstar c) (if pass "" "<-- BELOW AA"))
    pass))

(defun verify-deployed ()
  "Measure the bound theme. Returns the number of colors below AA."
  (format t "~%theme: ~A (background ~A)~%" (theme-name *theme*) (theme-bg *theme*))
  (format t "~18A ~9A ~9@A ~7@A ~7@A~%" "role" "hex" "contrast" "C*" "L*")
  (let ((failures (count-if-not (lambda (entry) (measure (car entry) (cdr entry)))
                                (by-role (deployed-colors)))))
    (format t "~A~%"
            (if (plusp failures)
                (format nil "~D color(s) BELOW AA for some observer" failures)
                "all colors clear AA for normal, protan and deutan observers"))
    failures))

;; solve-palette.lisp [MODE [THEME]]. A solve defaults to light; verify with no
;; THEME measures every theme, which is what the pre-commit hook runs.
(let* ((mode   (or (second sb-ext:*posix-argv*) "verify"))
       (named  (third sb-ext:*posix-argv*))
       (themes (if named (list (find-theme named)) *themes*))
       (one    (find-theme (or named "light"))))
  (flet ((solve-with (fn) (call-with-theme one fn)))
    (cond ((string= mode "syntax") (solve-with #'solve-syntax))
          ((string= mode "prompt") (solve-with #'solve-prompt))
          ((string= mode "diff")   (solve-with #'solve-diff))
          ((string= mode "ansi")   (solve-with #'solve-ansi))
          ((string= mode "verify")
           (let ((failures (loop for theme in themes
                                 sum (call-with-theme theme #'verify-deployed))))
             (sb-ext:exit :code (if (plusp failures) 1 0))))
          (t (die "usage: solve-palette.lisp [syntax|prompt|diff|ansi|verify] [light|dark]")))))
