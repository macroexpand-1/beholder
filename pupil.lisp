#!/usr/bin/env -S sbcl --script
;;;;
;;;; pupil.lisp


(defparameter *peak* 150)               ; typical laptop/desktop SDR white, cd/m^2
(defparameter *area* (* 30 18))         ; ~27" display at 24 inches, deg^2
(defparameter *defocus* 0.50d0)         ; residual defocus in diopters
(defparameter *pi* 3.14159265d0)

(defparameter +themes+
  '(("#24283b" "Storm (previous dark)")
    ("#1a1b26" "TokyoNight Night")
    ("#f2e9d8" "warm paper (deployed)")
    ("#f4efe3" "house-light.css")
    ("#ffffff" "plain white")))


;; sRGB gamma decode with one channel
(defun lin (channel)
  (if (<= channel 0.03928d0)
      (/ channel 12.92d0)
      (expt (/ (+ channel 0.055d0) 1.055d0) 2.4d0)))

;; Relative luminance (0..1) of a "#rrggbb" string
(defun relative-luminance (hex)
  (destructuring-bind (r g b)
      (let ((s (string-left-trim "#" hex)))
        (loop for i from 0 below 6 by 2
              collect (/ (parse-integer s :start i :end (+ i 2) :radix 16)
                         255.0d0)))
    (+ (* 0.2126d0 (lin r))
       (* 0.7152d0 (lin g))
       (* 0.0722d0 (lin b)))))

;; Pupil diameter. Stanley & Davies (1995) pupil, unified later by Watson & Yellott (2012).
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
             ;; Geometric blur circle: angular diameter (radians) is pupil
             ;; diameter (meters) * defocus (diopters); converted to arcminutes.
             (blur-rad (* (/ pupil 1000) *defocus*))
             (blur-arcmin (* blur-rad (* (/ 180 *pi*) 60))))
        (format t "~22A ~,3F  ~6,1F   ~5,2F    ~5,1F~%"
                name rel-lum cd-m2 pupil blur-arcmin)))))

(print-math)
