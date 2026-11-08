#!/usr/bin/env -S sbcl --script
;;;; tradeoff.lisp: how colorful can text get on a given background?
;;;;
;;;; For each background, this finds the most colorful text color at each hue
;;;; that still has enough contrast, and averages them. It does that twice:
;;;; once at 4.5 contrast (the usual minimum) and once at 7.

(require :asdf)
(asdf:load-asd (merge-pathnames "beholder.asd" *load-truename*))
(asdf:load-system "beholder")

(defpackage :tradeoff
  (:use :cl :beholder))
(in-package :tradeoff)

;; Which colors get tried. A rough sweep is enough for a comparison.
(defparameter *hue-step* 15)            ; degrees; 360/15 = 24 hues
(defparameter *sat-min* 0.40d0)
(defparameter *sat-max* 1.00d0)
(defparameter *sat-step* 0.05d0)
(defparameter *light-min* 0.10d0)
(defparameter *light-max* 0.75d0)
(defparameter *light-step* 0.01d0)

(defparameter *backgrounds*
  '(("#24283b" "old dark")
    ("#f2e9d8" "current")
    ("#f4efe3" "house CSS")
    ("#f7f2e6" nil)
    ("#faf6ec" nil)
    ("#ffffff" nil)))

;; For each hue, the most colorful color that still has FLOOR contrast against
;; BACKGROUND. Returns the average over all the hues.
(defun avg-max-chroma (background floor)
  (let ((chroma-sum 0.0d0)
        (hue-count 0))
    (loop for hue from 0 below 360 by *hue-step* do
      (let ((best-chroma 0.0d0))
        (loop for saturation from *sat-min* to *sat-max* by *sat-step* do
          (loop for lightness from *light-min* to *light-max* by *light-step* do
            (let ((color (hsl hue saturation lightness)))
              (when (>= (contrast-ratio color background) floor)
                (let ((color-chroma (chroma color)))
                  (when (> color-chroma best-chroma)
                    (setf best-chroma color-chroma)))))))
        (incf chroma-sum best-chroma)
        (incf hue-count)))
    (/ chroma-sum hue-count)))

(let ((hues (/ 360 *hue-step*)))
  (format t "How much color a background can carry (avg max CIELAB chroma over ~A hues):~%~%" hues)
  (format t "~26A ~6@A   ~14A ~14A~%" "background" "bg L*" "at AA 4.5:1" "at 7:1 (AAA)")
  (dolist (entry *backgrounds*)
    (destructuring-bind (hex-string note) entry
      (let* ((background (hex hex-string))
             (label (if note (format nil "~A  (~A)" hex-string note) hex-string)))
        (format t "~26A ~6,1F   ~14A ~14A~%"
                label
                (lstar background)
                (format nil "~,1F" (avg-max-chroma background 4.5d0))
                (format nil "~,1F" (avg-max-chroma background 7.0d0)))))))
