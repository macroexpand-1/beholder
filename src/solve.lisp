;;;; solve.lisp: find colors for you.
;;;;
;;;; You describe each color you want as a slot ("a blue, at least this much
;;;; contrast") and say how far apart the colors should look. SOLVE tries a
;;;; lot of candidates and hands back the most colorful set that meets every
;;;; target, or the closest it could get.
;;;;
;;;; If some slot can't be filled at all, you get an INFEASIBLE-SLOT error
;;;; saying which rule knocked out every candidate.

(in-package :beholder)

(declaim (optimize (speed 3) (safety 1)))
#+sbcl (declaim (sb-ext:muffle-conditions sb-ext:compiler-note))

;; Search settings. The search can settle on a so-so answer, so it starts over
;; from several random places and keeps the best (RESTARTS, in the problem).
(defparameter +max-passes+         7)      ; most times to go over every slot in one run
(defparameter +improve-eps+        1d-9)   ; smaller score changes are rounding noise
(defparameter +feasibility-weight+ 1000d0) ; makes meeting targets matter far more than color

;;; -------------------------------------------------------------- the inputs

;; One color to find: a range of hues in degrees, the contrast it needs at
;; least (FLOOR), how saturated it may get (SMAX, 0 to 1), and optionally how
;; colorful it has to be at least (CMIN, in chroma).
(defstruct (slot (:constructor slot (name hue-low hue-high floor smax &optional (cmin 0d0))))
  (name     ""  :type string)
  (hue-low  0   :type fixnum)
  (hue-high 0   :type fixnum)
  (floor    0d0 :type double-float)
  (smax     0d0 :type double-float)
  (cmin     0d0 :type double-float))

;; Which colors get tried. The solver steps through HSL: every 3rd hue,
;; saturation in steps of 0.05, lightness in steps of 0.008. Narrow LIGHT-MIN
;; and LIGHT-MAX to keep a theme's colors in a sensible band.
(defstruct grid
  (light-min  0d0     :type double-float)
  (light-max  1d0     :type double-float)
  (hue-stride 3       :type fixnum)
  (sat-min    0.34d0  :type double-float) ; the top end is each slot's SMAX
  (sat-step   0.05d0  :type double-float)
  (light-step 0.008d0 :type double-float))

;; Everything SOLVE needs. FIXED are colors you already have (body text, say)
;; that the new ones have to stay clear of. CEILING is an optional maximum
;; contrast.
(defstruct problem
  (background (hex "#ffffff")       :type color)
  (slots      ()                    :type list)
  (fixed      ()                    :type list)   ; a list of (ROLE . COLOR)
  (targets    (targets 16 ())       :type targets)
  (ceiling    nil                   :type (or null real))
  (grid       (make-grid)           :type grid)
  (restarts   8                     :type (integer 1))
  (observers  +default-observers+   :type list))

;; What SOLVE found.
(defstruct result
  palette          ; a list of (ROLE . COLOR), one per slot
  feasibility      ; 1.0 means every target was met; 0.8 means the tightest pair got 80% there
  mean-chroma      ; how colorful the palette is on average
  weakest-pair     ; the two colors that look most alike, fixed colors included
  weakest-de)      ; and how far apart they are

(define-condition infeasible-slot (error)
  ((slot       :initarg :slot       :reader infeasible-slot-slot)
   (constraint :initarg :constraint :reader infeasible-slot-constraint))
  (:documentation "No candidate in a slot passed. CONSTRAINT says which rule
knocked them all out: :FLOOR, :CEILING or :CHROMA-MIN.")
  (:report (lambda (condition stream)
             (format stream "slot ~A: no candidates; ~A"
                     (slot-name (infeasible-slot-slot condition))
                     (ecase (infeasible-slot-constraint condition)
                       (:floor      "nothing in its band clears the contrast floor")
                       (:ceiling    "nothing above the floor stays under the ceiling")
                       (:chroma-min "nothing that clears the contrast floor reaches the chroma minimum"))))))

;;; ---------------------------------------------------------- the candidates

;; The candidates that passed for one slot. Their profiles and chromas are
;; worked out once here so the search doesn't keep redoing them.
(defstruct pool
  (profiles #()                                         :type simple-vector)
  (chromas  (make-array 0 :element-type 'double-float)  :type (simple-array double-float (*)))
  (colors   #()                                         :type simple-vector))

(defun pool-size (pool)
  (length (pool-profiles pool)))

(defun slot-hues (slot grid)
  "The hues this slot tries."
  (let ((stride (grid-hue-stride grid)))
    (loop for hue from (* stride (ceiling (slot-hue-low slot) stride))
            to (slot-hue-high slot) by stride
          collect hue)))

(defun slot-saturations (slot grid)
  "The saturations this slot tries."
  (loop for saturation from (grid-sat-min grid) to (slot-smax slot) by (grid-sat-step grid)
        collect saturation))

(defun grid-lightnesses (grid)
  "The lightnesses every slot tries."
  (loop for lightness from (grid-light-min grid) to (grid-light-max grid)
          by (grid-light-step grid)
        collect lightness))

(defun slot-grid (slot grid)
  "Every color this slot tries: each hue, at each saturation, at each lightness.
Each is rounded to its nearest hex code, since the hex is what you'd actually
use. That way the search judges exactly the colors it hands back, and a
target it meets stays met."
  (let ((saturations (slot-saturations slot grid))
        (lightnesses (grid-lightnesses grid))
        (points      '()))
    (dolist (hue (slot-hues slot grid))
      (dolist (saturation saturations)
        (dolist (lightness lightnesses)
          (let ((exact (hsl hue saturation lightness)))
            (push (hex (color-hex exact)) points)))))
    (nreverse points)))

(defun candidates-for-slot (problem slot)
  "Every color this slot tries that has enough contrast, isn't over the
ceiling, and is colorful enough."
  (let ((background (problem-background problem))
        (observers  (problem-observers problem)))
    (flet ((clears-floor-p (candidate)
             (let ((contrast (worst-contrast candidate background :observers observers)))
               (>= contrast (slot-floor slot))))
           (stays-under-ceiling-p (candidate)
             (under-ceiling-p candidate background (problem-ceiling problem)))
           (colorful-enough-p (candidate)
             (>= (chroma candidate) (slot-cmin slot)))
           (candidate-profile (candidate)
             (profile candidate :observers observers)))
      (let* ((every-point   (slot-grid slot (problem-grid problem)))
             (above-floor   (remove-if-not #'clears-floor-p every-point))
             (under-ceiling (remove-if-not #'stays-under-ceiling-p above-floor))
             (kept          (remove-if-not #'colorful-enough-p under-ceiling)))
        (when (null above-floor)
          (error 'infeasible-slot :slot slot :constraint :floor))
        (when (null under-ceiling)
          (error 'infeasible-slot :slot slot :constraint :ceiling))
        (when (null kept)
          (error 'infeasible-slot :slot slot :constraint :chroma-min))
        (make-pool :profiles (map 'simple-vector #'candidate-profile kept)
                   :chromas  (map '(simple-array double-float (*)) #'chroma kept)
                   :colors   (coerce kept 'simple-vector))))))

;;; ------------------------------------------------------ the compiled problem
;;; The problem turned into arrays and lookup tables, so the search's inner
;;; loop never walks a list or compares strings.

(defstruct (compiled (:constructor %compiled))
  (names          #() :type simple-vector)
  (pools          #() :type simple-vector)
  (fixed-profiles #() :type simple-vector)
  (pair-target    (make-array '(0 0) :element-type 'double-float)
   :type (simple-array double-float (* *)))
  (fixed-target   (make-array '(0 0) :element-type 'double-float)
   :type (simple-array double-float (* *))))

(declaim (inline compiled-size compiled-n-fixed choice-profile choice-chroma))

(defun compiled-size (compiled)
  (length (compiled-names compiled)))

(defun compiled-n-fixed (compiled)
  (length (compiled-fixed-profiles compiled)))

;; While searching, the current guess is an "assignment": one candidate
;; number per slot. These look up what the guess picked for one slot.

(defun choice-profile (compiled assignment slot-index)
  (svref (pool-profiles (svref (compiled-pools compiled) slot-index))
         (aref assignment slot-index)))

(defun choice-chroma (compiled assignment slot-index)
  (aref (pool-chromas (svref (compiled-pools compiled) slot-index))
        (aref assignment slot-index)))

(defun choice-color (compiled assignment slot-index)
  (svref (pool-colors (svref (compiled-pools compiled) slot-index))
         (aref assignment slot-index)))

(defun pair-target-table (names targets)
  "How far apart each pair of slots has to be."
  (let ((table (make-array (list (length names) (length names))
                           :element-type 'double-float :initial-element 0d0)))
    (dotimes (slot-index (length names) table)
      (loop for other-index from (1+ slot-index) below (length names)
            do (setf (aref table slot-index other-index)
                     (target-for targets (svref names slot-index) (svref names other-index)))))))

(defun fixed-target-table (names fixed targets)
  "How far each slot has to be from each fixed color."
  (let ((table (make-array (list (length names) (length fixed))
                           :element-type 'double-float :initial-element 0d0)))
    (dotimes (slot-index (length names) table)
      (loop for fixed-index from 0 below (length fixed)
            do (setf (aref table slot-index fixed-index)
                     (target-for targets (svref names slot-index)
                                 (car (nth fixed-index fixed))))))))

(defun compile-problem (problem)
  (let ((names (map 'simple-vector #'slot-name (problem-slots problem)))
        (fixed (problem-fixed problem)))
    (%compiled
     :names          names
     :pools          (map 'simple-vector
                          (lambda (slot) (candidates-for-slot problem slot))
                          (problem-slots problem))
     :fixed-profiles (map 'simple-vector
                          (lambda (fixed-entry)
                            (profile (cdr fixed-entry) :observers (problem-observers problem)))
                          fixed)
     :pair-target    (pair-target-table names (problem-targets problem))
     :fixed-target   (fixed-target-table names fixed (problem-targets problem)))))

;;; ------------------------------------------------------------ the objective
;;; How a guess is scored:
;;;
;;;     min(feasibility, 1) * 1000 + mean chroma
;;;
;;; Feasibility is how close the guess comes to meeting every target, where 1
;;; means all of them are met. Multiplying by 1000 makes that matter far more
;;; than anything else, so the search meets the targets first and only then
;;; goes for the most colorful colors.

(defun slot-feasibility (compiled assignment slot-index)
  "How well one slot's pick does: its worst ratio of actual distance to target
distance, against the fixed colors and the slots after it. (Only the slots
after it, so each pair is counted once.)"
  (let ((pick-profile (choice-profile compiled assignment slot-index))
        (worst-ratio  most-positive-double-float))
    (declare (type double-float worst-ratio))
    (flet ((note-pair (other-profile required-de)
             (let ((achieved-de (separation pick-profile other-profile)))
               (setf worst-ratio (min worst-ratio (/ achieved-de required-de))))))
      (dotimes (fixed-index (compiled-n-fixed compiled))
        (note-pair (svref (compiled-fixed-profiles compiled) fixed-index)
                   (aref (compiled-fixed-target compiled) slot-index fixed-index)))
      (loop for other-index from (1+ slot-index) below (compiled-size compiled)
            do (note-pair (choice-profile compiled assignment other-index)
                          (aref (compiled-pair-target compiled) slot-index other-index))))
    worst-ratio))

(defun feasibility (compiled assignment)
  "The worst of those across all the slots. SCORE caps it at 1, so beating one
target by a lot can't make up for missing another."
  (let ((worst-ratio most-positive-double-float))
    (declare (type double-float worst-ratio))
    (dotimes (slot-index (compiled-size compiled) worst-ratio)
      (setf worst-ratio (min worst-ratio (slot-feasibility compiled assignment slot-index))))))

(defun mean-chroma (compiled assignment)
  (/ (loop for slot-index below (compiled-size compiled)
           sum (choice-chroma compiled assignment slot-index))
     (compiled-size compiled)))

(defun score (compiled assignment)
  "The number the search tries to raise; see the formula above."
  (+ (* (min (feasibility compiled assignment) 1d0) +feasibility-weight+)
     (mean-chroma compiled assignment)))

;;; --------------------------------------------------------------- the search
;;; Start from a random guess. Then, one slot at a time, try every candidate
;;; for that slot with the others held still, and keep the best. Repeat until
;;; nothing improves.

(defun random-assignment (compiled)
  "A random starting guess."
  (let ((assignment (make-array (compiled-size compiled) :element-type 'fixnum)))
    (dotimes (slot-index (compiled-size compiled) assignment)
      (setf (aref assignment slot-index)
            (random (pool-size (svref (compiled-pools compiled) slot-index)))))))

(defun improve-slot (compiled assignment slot-index current-score)
  "Try every candidate for one slot, keep the best, and return its score."
  (let ((best-candidate (aref assignment slot-index))
        (best-score     current-score))
    (dotimes (candidate-index (pool-size (svref (compiled-pools compiled) slot-index)))
      (setf (aref assignment slot-index) candidate-index)
      (let ((candidate-score (score compiled assignment)))
        (when (> candidate-score (+ best-score +improve-eps+))
          (setf best-score     candidate-score
                best-candidate candidate-index))))
    (setf (aref assignment slot-index) best-candidate)
    best-score))

(defun sweep (compiled assignment current-score)
  "Improve each slot once, in order. Returns the new score."
  (dotimes (slot-index (compiled-size compiled) current-score)
    (setf current-score (improve-slot compiled assignment slot-index current-score))))

(defun descend (compiled assignment)
  "Keep sweeping until nothing improves. Returns the final score, and leaves
ASSIGNMENT on the guess that got it."
  (let ((current-score (score compiled assignment)))
    (dotimes (pass +max-passes+ current-score)
      (declare (ignorable pass))
      (let ((next-score (sweep compiled assignment current-score)))
        (when (<= next-score (+ current-score +improve-eps+))
          (return next-score))
        (setf current-score next-score)))))

(defun solve (problem)
  "Find colors for PROBLEM's slots. Runs the search from several random
starting guesses and keeps the best. Returns a RESULT."
  (let ((compiled        (compile-problem problem))
        (best-assignment nil)
        (best-score      -1d0))
    (dotimes (restart (problem-restarts problem))
      (declare (ignorable restart))
      (let* ((assignment  (random-assignment compiled))
             (final-score (descend compiled assignment)))
        (when (> final-score best-score)
          (setf best-score      final-score
                best-assignment assignment))))
    ;; The candidates are already hex codes (see SLOT-GRID), so these numbers
    ;; describe exactly the colors handed back.
    (let ((palette (loop for slot-index below (compiled-size compiled)
                         for role = (svref (compiled-names compiled) slot-index)
                         collect (cons role (choice-color compiled best-assignment slot-index)))))
      (multiple-value-bind (closest-pair closest-de)
          (weakest-pair (append palette (problem-fixed problem))
                        :observers (problem-observers problem))
        (make-result :palette palette
                     :feasibility (min (feasibility compiled best-assignment) 1d0)
                     :mean-chroma (mean-chroma compiled best-assignment)
                     :weakest-pair closest-pair
                     :weakest-de closest-de)))))
