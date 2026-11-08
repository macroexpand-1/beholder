;;;; test/solve.lisp

(in-package :beholder-tests)

(def-suite solve :in beholder-tests)
(in-suite solve)

(defun two-slot-problem (&key (blue-floor 5.5d0))
  "A small problem to solve: a blue and an orange on a cream background,
looking 40 apart."
  (make-problem :background (hex "#f2e9d8")
                :slots (list (slot "blue" 205 224 blue-floor 0.90d0 40d0)
                             (slot "warm"   8  26 5.0d0      1.00d0 44d0))
                :fixed (list (cons "fg" (hex "#2f2b25")))
                :targets (targets 16 '(("blue" "warm" 40)))
                :grid (make-grid :light-min 0.13d0 :light-max 0.58d0)
                :restarts 2))

(test solve-fills-every-slot
  (let ((result (solve (two-slot-problem))))
    (is (equal '("blue" "warm") (mapcar #'car (result-palette result))))
    (is (every #'colorp (mapcar #'cdr (result-palette result))))))

(test solve-meets-easy-targets
  (is (= 1d0 (result-feasibility (solve (two-slot-problem))))))

(test solved-colors-clear-their-floors
  (let* ((background (hex "#f2e9d8"))
         (palette    (result-palette (solve (two-slot-problem))))
         (blue       (cdr (assoc "blue" palette :test #'string=))))
    (is (>= (worst-contrast blue background) 5.5d0))))

(test an-impossible-floor-signals-infeasible-slot
  (signals infeasible-slot (solve (two-slot-problem :blue-floor 30d0))))

(test infeasible-slot-names-the-constraint
  (handler-case (progn (solve (two-slot-problem :blue-floor 30d0))
                       (is nil "expected INFEASIBLE-SLOT"))
    (infeasible-slot (condition)
      (is (eq :floor (infeasible-slot-constraint condition)))
      (is (string= "blue" (slot-name (infeasible-slot-slot condition)))))))
