;;;; test/package.lisp

(defpackage :beholder-tests
  (:use :cl :beholder)
  (:import-from :fiveam #:def-suite #:in-suite #:test #:is #:signals))
(in-package :beholder-tests)

(def-suite beholder-tests :description "Everything in beholder.")

;; True when two numbers are equal give or take a little rounding.

(defun close-to (expected actual &optional (tolerance 1d-6))
  (< (abs (- expected actual)) tolerance))
