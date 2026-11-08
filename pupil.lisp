#!/usr/bin/env -S sbcl --script
;;;; pupil.lisp: how blurry text gets on bright vs dark backgrounds.
;;;;
;;;; A brighter screen makes your pupil smaller, and a smaller pupil blurs
;;;; less (the same reason a camera gets sharper when you stop it down). This
;;;; estimates pupil size for a few backgrounds, and how much blur that means
;;;; for someone whose eyes are slightly out of focus.


(defparameter *peak* 150)               ; how bright white is on a normal screen, cd/m^2
(defparameter *area* (* 30 18))         ; how much of your view a 27" screen fills at 24", deg^2
(defparameter *defocus* 0.50d0)         ; how far out of focus the eye is, in diopters
(defparameter *pi* 3.14159265d0)

(defparameter +themes+
  '(("#24283b" "Storm (previous dark)")
    ("#1a1b26" "TokyoNight Night")
    ("#f2e9d8" "warm paper (deployed)")
    ("#f4efe3" "house-light.css")
    ("#ffffff" "plain white")))


;; A hex channel (0 to 1) as linear light.
(defun lin (channel)
  (if (<= channel 0.03928d0)
      (/ channel 12.92d0)
      (expt (/ (+ channel 0.055d0) 1.055d0) 2.4d0)))

;; How bright a "#rrggbb" color is, from 0 (black) to 1 (white).
(defun relative-luminance (hex)
  (destructuring-bind (r g b)
      (let ((s (string-left-trim "#" hex)))
        (loop for i from 0 below 6 by 2
              collect (/ (parse-integer s :start i :end (+ i 2) :radix 16)
                         255.0d0)))
    (+ (* 0.2126d0 (lin r))
       (* 0.7152d0 (lin g))
       (* 0.0722d0 (lin b)))))

;; Pupil size in mm for a given brightness and screen size. The formula is
;; from Stanley & Davies (1995), as used by Watson & Yellott (2012).
(defun pupil-diameter-mm (luminance-cd-m2 field-area-deg2)
  (let ((x (expt (/ (* luminance-cd-m2 field-area-deg2) 846) 0.41d0)))
    (- 7.75d0 (* 5.75d0 (/ x (+ x 2))))))

(defun print-math ()
  (format t "field           rel.lum   cd/m^2   pupil    geometric blur from ~,2F D~%" *defocus*)
  (format t "                                    (mm)    residual defocus (arcmin)~%")
  (dolist (theme +themes+)
    (destructuring-bind (hex name) theme
      (let* ((rel-lum (relative-luminance hex))
             (cd-m2 (* rel-lum *peak*))
             (pupil (pupil-diameter-mm cd-m2 *area*))
             ;; How big the blur spot is: pupil size (in meters) times how far
             ;; out of focus, which gives an angle. Then radians to arcminutes.
             (blur-rad (* (/ pupil 1000) *defocus*))
             (blur-arcmin (* blur-rad (* (/ 180 *pi*) 60))))
        (format t "~22A ~,3F  ~6,1F   ~5,2F    ~5,1F~%"
                name rel-lum cd-m2 pupil blur-arcmin)))))

(print-math)
