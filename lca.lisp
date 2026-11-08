#!/usr/bin/env -S sbcl --script
;;;; lca.lisp: which colors the eye can't focus sharply.
;;;;
;;;; The eye bends each wavelength of light a little differently, so it can't
;;;; focus every color at once. It focuses yellow-green best. This prints how
;;;; far out of focus each other color is, in diopters. Blues come out worst,
;;;; which is why blue text gets a little extra contrast in the themes.


;; How strongly the eye bends light of a given wavelength (in nm).
(defun refractive-power (nm)
  (- 1.68524d0 (/ 633.46d0 (- nm 214.102d0))))

;; Yellow-green, the color the eye focuses best.
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
