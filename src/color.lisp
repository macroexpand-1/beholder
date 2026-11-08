;;;; color.lisp: the color math everything else builds on.
;;;;
;;;; A color here is a small value you make from a hex string or from HSL.
;;;; Inside, it keeps its red, green and blue as linear light, because that's
;;;; what the contrast and color-difference formulas want.
;;;;
;;;; The measurements are the usual ones: contrast against a background, how
;;;; colorful a color is, and how far apart two colors look. Each can also be
;;;; taken for a few kinds of color vision at once (an "observer" each), keeping
;;;; the worst result. Most of the time you can ignore that and take the
;;;; defaults.

(in-package :beholder)

;;; ---------------------------------------------------------------- the value

;; Red, green and blue as "linear light" from 0 (none) to 1 (full).
;; A color run through an observer can land a little outside 0 to 1.
;; That's fine, and COLOR-HEX clamps it back when printing.
(defstruct (color (:constructor %color (r g b))
                  (:copier nil)
                  (:predicate colorp))
  (r 0d0 :type double-float :read-only t)
  (g 0d0 :type double-float :read-only t)
  (b 0d0 :type double-float :read-only t))

;; Hex codes aren't linear: screens store more steps in the darks than the
;; lights. Any one who has edited photos can tell you that.
;; LIN undoes that (hex value to light), UNLIN redoes it (light to hex
;; value). The numbers are the sRGB standard's.

(defun lin (encoded-channel)
  (if (<= encoded-channel 0.03928d0)
      (/ encoded-channel 12.92d0)
      (expt (/ (+ encoded-channel 0.055d0) 1.055d0) 2.4d0)))

(defun clamp (value)
  (min 1d0 (max 0d0 value)))

(defun unlin (linear-channel)
  (let ((clamped (clamp linear-channel)))
    (if (<= clamped 0.0031308d0)
        (* 12.92d0 clamped)
        (- (* 1.055d0 (expt clamped (/ 1.0d0 2.4d0))) 0.055d0))))

(defun hex (hex-string)
  "Make a color from \"#rrggbb\". The # is optional."
  (let ((hex-digits (string-left-trim "#" hex-string)))
    (flet ((channel-at (start)
             (lin (/ (parse-integer hex-digits :start start :end (+ start 2) :radix 16)
                     255.0d0))))
      (%color (channel-at 0) (channel-at 2) (channel-at 4)))))

(defun color-hex (color)
  "The color as a lowercase \"#rrggbb\"."
  (flet ((channel-byte (linear-channel)
           (floor (+ (* (unlin linear-channel) 255.0d0) 0.5d0))))
    (string-downcase (format nil "#~2,'0x~2,'0x~2,'0x"
                             (channel-byte (color-r color))
                             (channel-byte (color-g color))
                             (channel-byte (color-b color))))))

;; So the REPL shows #<COLOR #f2e9d8> instead of three floats.
(defmethod print-object ((color color) stream)
  (print-unreadable-object (color stream :type t)
    (write-string (color-hex color) stream)))

;; The textbook HSL-to-RGB conversion. HSL is only here because it's an easy
;; space to sweep through; nothing gets judged in it.

(defun hue-channel (low high hue-position)
  (let ((wrapped hue-position))
    (when (< wrapped 0) (incf wrapped))
    (when (> wrapped 1) (decf wrapped))
    (cond ((< wrapped 1/6) (+ low (* (- high low) 6 wrapped)))
          ((< wrapped 1/2) high)
          ((< wrapped 2/3) (+ low (* (- high low) (- 2/3 wrapped) 6)))
          (t low))))

(defun hsl (hue saturation lightness)
  "Make a color from HUE in degrees, and SATURATION and LIGHTNESS from 0 to 1."
  (let* ((hue-fraction (/ (mod hue 360) 360.0d0))
         (high (if (< lightness 0.5d0)
                   (* lightness (+ 1 saturation))
                   (+ lightness (- saturation (* lightness saturation)))))
         (low (- (* 2 lightness) high)))
    (flet ((channel-at (hue-offset) (lin (hue-channel low high hue-offset))))
      (%color (channel-at (+ hue-fraction 1/3))
              (channel-at hue-fraction)
              (channel-at (- hue-fraction 1/3))))))

;;; ------------------------------------------------------------- measurements

;; Standard constants: sRGB to XYZ, and the white point of daylight (D65).
(defparameter +srgb-to-xyz+
  '((0.4124d0 0.3576d0 0.1805d0)
    (0.2126d0 0.7152d0 0.0722d0)
    (0.0193d0 0.1192d0 0.9505d0)))

(defparameter +d65-white+
  '(0.95047d0 1.00000d0 1.08883d0))

;; How bright a color is. Green counts most because our eyes are most
;; sensitive to it.
(defun luminance (color)
  (+ (* 0.2126d0 (color-r color))
     (* 0.7152d0 (color-g color))
     (* 0.0722d0 (color-b color))))

;; The WCAG contrast ratio, from 1 (no contrast) to 21 (black on white).
;; Body text wants at least 4.5. This is for normal vision only
;; (see WORST-CONTRAST for everyone)
(defun contrast-ratio (color-a color-b)
  (let ((luminance-a (luminance color-a))
        (luminance-b (luminance color-b)))
    (if (> luminance-a luminance-b)
        (/ (+ luminance-a 0.05d0) (+ luminance-b 0.05d0))
        (/ (+ luminance-b 0.05d0) (+ luminance-a 0.05d0)))))

;; Multiply a 3x3 matrix (a list of three rows) by a red/green/blue triple.
(defun apply-matrix (matrix red green blue)
  (mapcar (lambda (row)
            (destructuring-bind (weight-red weight-green weight-blue) row
              (+ (* weight-red red) (* weight-green green) (* weight-blue blue))))
          matrix))

;; CIELAB is a color space where equal distances look like equal differences,
;; which is what lets us say how far apart two colors look. L* is lightness,
;; a* runs green to red, and b* runs blue to yellow. LAB-COMPRESS is one step
;; of the standard formula.

(defun lab-compress (component white)
  (let ((ratio (/ component white)))
    (if (> ratio 0.008856d0)
        (expt ratio (/ 1.0d0 3.0d0))
        (+ (* 7.787d0 ratio) (/ 16.0d0 116.0d0)))))

(defun lab (color)
  "The color's (L* a* b*)."
  (let* ((xyz        (apply-matrix +srgb-to-xyz+
                                   (color-r color) (color-g color) (color-b color)))
         (compressed (mapcar #'lab-compress xyz +d65-white+)))
    (destructuring-bind (x-compressed y-compressed z-compressed) compressed
      (list (- (* 116 y-compressed) 16)
            (* 500 (- x-compressed y-compressed))
            (* 200 (- y-compressed z-compressed))))))

;; Lightness, from 0 (black) to 100 (white).
(defun lstar (color)
  (first (lab color)))

;; How colorful a color is: 0 for a gray, and the higher the more vivid.
(defun chroma (color)
  (destructuring-bind (lightness a-star b-star) (lab color)
    (declare (ignore lightness))
    (sqrt (+ (expt a-star 2) (expt b-star 2)))))

;;; ---------------------------------------------------------------- observers
;;; An observer is a matrix that turns a color into the color that kind of eye
;;; actually sees. A protan (red-blind) or deutan (green-blind) eye folds red
;;; and green together, so two colors that look different to normal vision can
;;; look the same to them.
;;;
;;; The matrices come from a paper by Viénot, Brettel & Mollon (1999).
;;; They model full color blindness only though.
;;; Milder versions would need a strength setting, which I guess
;;; would go in this struct.

(defstruct (observer (:constructor make-observer (name matrix))
                     (:copier nil))
  (name   "" :type string :read-only t)
  (matrix () :type list   :read-only t))

(defparameter +normal+
  (make-observer "normal" '((1.0d0 0.0d0 0.0d0)
                            (0.0d0 1.0d0 0.0d0)
                            (0.0d0 0.0d0 1.0d0))))

(defparameter +protan+
  (make-observer "protan" '((0.11238d0 0.88762d0 0.0d0)
                            (0.11238d0 0.88762d0 0.0d0)
                            (0.00401d0 -0.00401d0 1.0d0))))

(defparameter +deutan+
  (make-observer "deutan" '((0.29275d0 0.70725d0 0.0d0)
                            (0.29275d0 0.70725d0 0.0d0)
                            (-0.02234d0 0.02234d0 1.0d0))))

;; Who gets checked when you don't say.
(defparameter +default-observers+ (list +normal+ +protan+ +deutan+))

(defun simulate (observer color)
  "The color as OBSERVER sees it."
  (destructuring-bind (seen-red seen-green seen-blue)
      (apply-matrix (observer-matrix observer)
                    (color-r color) (color-g color) (color-b color))
    (%color seen-red seen-green seen-blue)))

;; Contrast for each observer, keeping the lowest. Reds are where this
;; usually differs from plain CONTRAST-RATIO: they look darker to a protan.
(defun worst-contrast (foreground background &key (observers +default-observers+))
  (loop for observer in observers
        minimize (contrast-ratio (simulate observer foreground)
                                 (simulate observer background))))

;; A color's L* a* b* as each observer sees it, in one flat array.
;; There are three numbers for the first observer, then three for the next, and so on.
;; It's a typed array rather than a list because the solver compares
;; profiles millions of times.
(defun profile (color &key (observers +default-observers+))
  (let ((coordinates (make-array (* 3 (length observers)) :element-type 'double-float)))
    (loop for observer in observers
          for observer-start from 0 by 3
          do (loop for coordinate in (lab (simulate observer color))
                   for position from observer-start
                   do (setf (aref coordinates position) (float coordinate 1d0))))
    coordinates))

;; How far apart two colors look (in dE, plain distance in CIELAB), for
;; whichever observer finds them closest. Both profiles must use the same
;; observers.
(defun separation (profile-a profile-b)
  (declare (type (simple-array double-float (*)) profile-a profile-b))
  (let ((smallest-squared most-positive-double-float))
    (declare (type double-float smallest-squared))
    (loop for observer-start of-type fixnum from 0 below (length profile-a) by 3
          do (let* ((delta-l (- (aref profile-a observer-start)
                                (aref profile-b observer-start)))
                    (delta-a (- (aref profile-a (+ observer-start 1))
                                (aref profile-b (+ observer-start 1))))
                    (delta-b (- (aref profile-a (+ observer-start 2))
                                (aref profile-b (+ observer-start 2))))
                    (squared (+ (* delta-l delta-l) (* delta-a delta-a) (* delta-b delta-b))))
               (when (< squared smallest-squared)
                 (setf smallest-squared squared))))
    (sqrt smallest-squared)))
