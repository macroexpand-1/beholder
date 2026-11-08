;;;; colorlib.lisp

(defpackage :colorlib
  (:use :cl)
  (:export #:hex2lin
           #:lin2hex
           #:hsl2lin
           #:luminance
           #:contrast-ratio
           #:lstar
           #:chroma
           #:worst-contrast
           #:profile-vector
           #:profile
           #:separation))
(in-package :colorlib)

(defparameter *srgb-to-xyz*
  '((0.4124d0 0.3576d0 0.1805d0)
    (0.2126d0 0.7152d0 0.0722d0)
    (0.0193d0 0.1192d0 0.9505d0)))

(defparameter *d65-white*
  '(0.95047d0 1.00000d0 1.08883d0))

;; Viénot, Brettel & Mollon (1999) dichromat simulation, in linear RGB.
(defparameter *obs*
  '(((1.0d0 0.0d0 0.0d0)                                   ; normal
     (0.0d0 1.0d0 0.0d0)
     (0.0d0 0.0d0 1.0d0))
    ((0.11238d0 0.88762d0 0.0d0)                           ; protanope
     (0.11238d0 0.88762d0 0.0d0)
     (0.00401d0 -0.00401d0 1.0d0))
    ((0.29275d0 0.70725d0 0.0d0)                           ; deuteranope
     (0.29275d0 0.70725d0 0.0d0)
     (-0.02234d0 0.02234d0 1.0d0))))

(defun lin (channel)
  (if (<= channel 0.03928d0)
      (/ channel 12.92d0)
      (expt (/ (+ channel 0.055d0) 1.055d0) 2.4d0)))

(defun clamp (num)
  (min 1d0 (max 0d0 num)))

(defun unlin (channel)
  (let ((c (clamp channel)))
    (if (<= c 0.0031308d0)
        (* 12.92d0 c)
        (- (* 1.055d0 (expt c (/ 1.0d0 2.4d0))) 0.055d0))))

(defun hex2lin (hex)
  (let ((s (string-left-trim "#" hex)))
    (loop for i from 0 below 6 by 2
          collect (lin (/ (parse-integer s :start i :end (+ i 2)
                                           :radix 16)
                          255.0d0)))))

(defun lin2hex (rgb)
  (destructuring-bind (r g b)
      (mapcar (lambda (ch) (floor (+ (* (unlin ch) 255.0d0) 0.5d0)))
              rgb)
    (string-downcase (format nil "#~2,'0x~2,'0x~2,'0x" r g b))))

(defun hue-channel (low high pos)
  (let ((p pos))
    (when (< p 0) (incf p))
    (when (> p 1) (decf p))
    (cond ((< p 1/6) (+ low (* (- high low) 6 p)))
          ((< p 1/2) high)
          ((< p 2/3) (+ low (* (- high low) (- 2/3 p) 6)))
          (t low))))

(defun hsl2lin (hue sat light)
  (let* ((hue-norm (/ (mod hue 360) 360.0d0))
         (high (if (< light 0.5d0)
                   (* light (+ 1 sat))
                   (+ light (- sat (* light sat)))))
         (low (- (* 2 light) high)))
    (mapcar (lambda (offset) (lin (hue-channel low high offset)))
            (list (+ hue-norm 1/3) hue-norm (- hue-norm 1/3)))))

(defun luminance (rgb)
  (destructuring-bind (r g b) rgb
    (+ (* 0.2126d0 r) (* 0.7152d0 g) (* 0.0722d0 b))))

(defun contrast-ratio (a b)
  (let ((lum-a (luminance a))
        (lum-b (luminance b)))
    (if (> lum-a lum-b)
        (/ (+ lum-a 0.05d0) (+ lum-b 0.05d0))
        (/ (+ lum-b 0.05d0) (+ lum-a 0.05d0)))))

(defun lab (rgb)
  (destructuring-bind (r g b) rgb
    (let* ((xyz (mapcar (lambda (row)
                          (destructuring-bind (m0 m1 m2) row
                            (+ (* m0 r) (* m1 g) (* m2 b))))
                        *srgb-to-xyz*))
           (f (mapcar (lambda (v w)
                        (let ((ratio (/ v w)))
                          (if (> ratio 0.008856d0)
                              (expt ratio (/ 1.0d0 3.0d0))
                              (+ (* 7.787d0 ratio) (/ 16.0d0 116.0d0)))))
                      xyz *d65-white*)))
      (destructuring-bind (fx fy fz) f
        (list (- (* 116 fy) 16)
              (* 500 (- fx fy))
              (* 200 (- fy fz)))))))

(defun lstar (rgb)
  (first (lab rgb)))

(defun chroma (rgb)
  (let ((lab (lab rgb)))
    (sqrt (+ (expt (second lab) 2)
             (expt (third lab) 2)))))

(defun sim (matrix rgb)
  (destructuring-bind (r g b) rgb
    (mapcar (lambda (row)
              (destructuring-bind (m0 m1 m2) row
                (+ (* m0 r) (* m1 g) (* m2 b))))
            matrix)))

(defun worst-contrast (fg bg)
  (loop for observer in *obs*
        minimize (contrast-ratio (sim observer fg) (sim observer bg))))

;; The CIELAB coordinates of one color as seen by each of the three observers,
;; laid end to end. Flat and typed rather than a list of lists.
;; SEPARATION reads it in the innermost loop of the palette solver.
(deftype profile-vector () '(simple-array double-float (9)))

(defun profile (rgb)
  (let ((out (make-array 9 :element-type 'double-float)))
    (loop for observer in *obs*
          for base from 0 by 3
          do (loop for v in (lab (sim observer rgb))
                   for i from base
                   do (setf (aref out i) (float v 1d0))))
    out))

;; Distance between two colors as the WORST observer sees it: the smallest of
;; the three per-observer dE values. So if a pair collapses, then it's collapsed
;; no matter how far apart it looks to others.
(defun separation (pa pb)
  (declare (type profile-vector pa pb))
  (let ((best most-positive-double-float))
    (declare (type double-float best))
    (loop for base of-type fixnum from 0 below 9 by 3
          do (let* ((dl (- (aref pa base)       (aref pb base)))
                    (da (- (aref pa (+ base 1)) (aref pb (+ base 1))))
                    (db (- (aref pa (+ base 2)) (aref pb (+ base 2))))
                    (d  (+ (* dl dl) (* da da) (* db db))))
               (when (< d best) (setf best d))))
    (sqrt best)))
