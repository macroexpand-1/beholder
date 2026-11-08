#!/usr/bin/env -S sbcl --script
;;;; tradeoff.lisp: how much color can a given background carry?

(load (merge-pathnames "colorlib.lisp" *load-truename*))

(defpackage :tradeoff
  (:use :cl :colorlib))
(in-package :tradeoff)

;; Sweep resolution. It's not meant to be precise.
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

;; Best achievable chroma, averaged over the hue circle, at a given contrast
;; floor. For each hue, search the whole saturation/lightness plane for the most
;; colorful point that still clears the floor, then average those maxima.
(defun avg-max-chroma (bg floor)
  (let ((sum 0.0d0)
        (n 0))
    (loop for hue from 0 below 360 by *hue-step* do
      (let ((best 0.0d0))
        (loop for sat from *sat-min* to *sat-max* by *sat-step* do
          (loop for light from *light-min* to *light-max* by *light-step* do
            (let ((rgb (hsl2lin hue sat light)))
              (when (>= (contrast-ratio rgb bg) floor)
                (let ((c (chroma rgb)))
                  (when (> c best)
                    (setf best c)))))))
        (incf sum best)
        (incf n)))
    (/ sum n)))

(let ((hues (/ 360 *hue-step*)))
  (format t "How much color a background can carry (avg max CIELAB chroma over ~A hues):~%~%" hues)
  (format t "~26A ~6@A   ~14A ~14A~%" "background" "bg L*" "at AA 4.5:1" "at 7:1 (AAA)")
  (dolist (entry *backgrounds*)
    (destructuring-bind (hex note) entry
      (let* ((bg (hex2lin hex))
             (label (if note (format nil "~A  (~A)" hex note) hex)))
        (format t "~26A ~6,1F   ~14A ~14A~%"
                label
                (lstar bg)
                (format nil "~,1F" (avg-max-chroma bg 4.5d0))
                (format nil "~,1F" (avg-max-chroma bg 7.0d0)))))))
