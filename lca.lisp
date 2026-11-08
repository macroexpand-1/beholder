#!/usr/bin/env -S sbcl --script
;;;; lca.lisp


(defun refractive-power (nm)
  (- 1.68524d0 (/ 633.46d0 (- nm 214.102d0))))

(defparameter +reference-nm+ 555)
(defparameter *reference* (refractive-power +reference-nm+))

(defparameter *bands*
  '(("deep blue" . 450)
    ("blue" . 470)
    ("cyan" . 490)
    ("green" . 530)
    ("yellow-green" . 555)
    ("amber" . 585)
    ("red" . 610)
    ("deep red" . 640)))

(format t "~28A ~6@A  ~8@A~%" "wavelength" "nm" "defocus vs 555nm (D)")

(dolist (band *bands*)
  (destructuring-bind (name . nm) band
    (let ((defocus (- (refractive-power nm) *reference*)))
      (format t "~28A ~6D  ~8,2@F~%" name nm defocus))))
