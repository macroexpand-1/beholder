;;;; assess.lisp: check a palette you already have.
;;;;
;;;; Give it a background and some named colors, and it tells you how each one
;;;; measures (contrast, how colorful, how light) and which two colors look
;;;; most alike. It never prints anything; that's up to whoever calls it.
;;;;
;;;; If you only want to check colors, this is probably all you need. The
;;;; solver is for when you want colors found for you.

(in-package :beholder)

;;; ------------------------------------------------------------------ targets
;;; How far apart two roles should look, in dE. Name the pairs you care about
;;; and every other pair gets the default. ("keyword" "string") and ("string"
;;; "keyword") are the same pair.

(defstruct (targets (:constructor make-targets (default table)))
  (default 16d0 :type double-float)
  (table   (make-hash-table :test #'equal) :type hash-table))

(defun pair-key (role-a role-b)
  (if (string> role-a role-b)
      (format nil "~A|~A" role-b role-a)
      (format nil "~A|~A" role-a role-b)))

(defun targets (default pairs)
  "For example, (targets 16 '((\"keyword\" \"string\" 22))) wants keyword and
string 22 apart, and every other pair 16."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (pair pairs)
      (destructuring-bind (role-a role-b required-de) pair
        (setf (gethash (pair-key role-a role-b) table) (float required-de 1d0))))
    (make-targets (float default 1d0) table)))

(defun target-for (targets role-a role-b)
  (gethash (pair-key role-a role-b) (targets-table targets) (targets-default targets)))

;;; ----------------------------------------------------------- shared checks

;; A ceiling is for dark themes: an accent brighter than the body text looks
;; like it's glowing. NIL means no ceiling.
(defun under-ceiling-p (color background ceiling)
  (or (null ceiling) (<= (contrast-ratio color background) ceiling)))

(defun by-role (entries)
  (sort (copy-list entries) #'string< :key #'car))

(defun weakest-pair (entries &key (observers +default-observers+))
  "The two colors in ENTRIES, a list of (ROLE . COLOR), that look most alike.
Returns their two roles and how far apart they are."
  (let* ((sorted-entries (by-role entries))
         (roles          (map 'simple-vector #'car sorted-entries))
         (profiles       (map 'simple-vector
                              (lambda (entry) (profile (cdr entry) :observers observers))
                              sorted-entries))
         (closest-de     most-positive-double-float)
         (closest-pair   nil))
    (dotimes (first-index (length roles))
      (loop for second-index from (1+ first-index) below (length roles) ; each pair once
            for distance = (separation (svref profiles first-index)
                                       (svref profiles second-index))
            when (< distance closest-de)
              do (setf closest-de   distance
                       closest-pair (list (svref roles first-index)
                                          (svref roles second-index)))))
    (values closest-pair closest-de)))

;;; ------------------------------------------------------------------- policy

;; What counts as passing. FLOOR is the minimum contrast (4.5 is the usual bar
;; for text). CEILING is an optional maximum. TARGETS, when given, also checks
;; that every pair looks far enough apart.
(defstruct policy
  (floor     4.5d0               :type real)
  (ceiling   nil                 :type (or null real))
  (targets   nil                 :type (or null targets))
  (observers +default-observers+ :type list))

;;; ------------------------------------------------------------------- report

;; How one named color measured.
(defstruct (role-measure (:conc-name measure-))
  role
  color
  contrasts          ; (OBSERVER-NAME . RATIO) for each observer
  worst-contrast     ; the lowest of those; the floor is checked against this
  chroma
  lstar
  passes-floor-p
  under-ceiling-p)

(defun measure-passed-p (measure)
  (and (measure-passes-floor-p measure) (measure-under-ceiling-p measure)))

;; Everything ASSESS found.
(defstruct report
  background
  measures           ; one ROLE-MEASURE per color, in the order you gave them
  weakest-pair       ; the two roles that look most alike
  weakest-de         ; and how far apart they are
  short-pairs        ; (ROLE-A ROLE-B DE REQUIRED-DE) for pairs closer than their target
  failures)          ; how many colors missed the floor or went over the ceiling

(defun report-passed-p (report)
  (and (zerop (report-failures report))
       (null (report-short-pairs report))))

(defun contrast-by-observer (color background observers)
  (loop for observer in observers
        for seen-color = (simulate observer color)
        for seen-background = (simulate observer background)
        collect (cons (observer-name observer)
                      (contrast-ratio seen-color seen-background))))

(defun measure-entry (role color background policy)
  (let* ((observers (policy-observers policy))
         (worst     (worst-contrast color background :observers observers)))
    (make-role-measure
     :role role
     :color color
     :contrasts (contrast-by-observer color background observers)
     :worst-contrast worst
     :chroma (chroma color)
     :lstar (lstar color)
     :passes-floor-p (>= worst (policy-floor policy))
     :under-ceiling-p (under-ceiling-p color background (policy-ceiling policy)))))

(defun short-pairs (entries policy)
  "Pairs that look closer together than their target says they should."
  (let ((targets   (policy-targets policy))
        (observers (policy-observers policy))
        (short     '()))
    (when targets
      (loop for ((role . color) . later-entries) on (by-role entries)
            do (loop for (other-role . other-color) in later-entries
                     for distance = (separation (profile color :observers observers)
                                                (profile other-color :observers observers))
                     for required-de = (target-for targets role other-role)
                     when (< distance required-de)
                       do (push (list role other-role distance required-de) short))))
    (nreverse short)))

(defun assess (background entries &optional (policy (make-policy)))
  "Check ENTRIES, a list of (ROLE . COLOR), against BACKGROUND. POLICY says what
counts as passing; by default that's a contrast of at least 4.5 and nothing else."
  (let ((measures (loop for (role . color) in entries
                        collect (measure-entry role color background policy))))
    (multiple-value-bind (closest-pair closest-de)
        (weakest-pair entries :observers (policy-observers policy))
      (make-report :background background
                   :measures measures
                   :weakest-pair closest-pair
                   :weakest-de (and closest-pair closest-de)
                   :short-pairs (short-pairs entries policy)
                   :failures (count-if-not #'measure-passed-p measures)))))

;;; REPORT-JSON in json.lisp gives the same report as JSON for other languages.
