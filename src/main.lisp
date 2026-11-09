;;;; main.lisp: the beholder command.
;;;;
;;;;   beholder assess [REQUEST-FILE]   # check colors you have
;;;;   beholder solve  [REQUEST-FILE]   # have colors found for you
;;;;
;;;; Each reads a JSON request from REQUEST-FILE, or from standard input when
;;;; there isn't one, and writes a JSON response to standard output. The exit
;;;; code says how it went:
;;;;
;;;;   0   the colors passed (assess), or every target was met (solve)
;;;;   1   they didn't, or a slot couldn't be filled at all
;;;;   2   the request itself is bad: not JSON, a missing field, a bad hex
;;;;
;;;; A bad request still gets a JSON response, with an "error" field, so a
;;;; caller always has one stream to read.
;;;;
;;;; RESPOND does all the work and is what the tests call. MAIN only reads the
;;;; command line and the request and sets the exit code; it's the one place
;;;; that touches SBCL directly.

(in-package :beholder)

(defun answer-assess (request)
  (multiple-value-bind (background entries policy) (read-assess-request request)
    (let ((report (assess background entries policy)))
      (values (report-json report)
              (if (report-passed-p report) 0 1)))))

(defun answer-solve (request)
  (let* ((problem (read-solve-request request))
         (result  (solve problem)))
    (values (result-json result problem)
            (if (>= (result-feasibility result) 1d0) 0 1))))

(defun respond (command request-text)
  "Answer REQUEST-TEXT, a JSON request for COMMAND (\"assess\" or \"solve\").
Returns the response as JSON text, and the exit code."
  (multiple-value-bind (response exit-code)
      (handler-case
          (let ((request (parse-json request-text)))
            (cond ((string= command "assess") (answer-assess request))
                  ((string= command "solve")  (answer-solve request))
                  (t (error "no command ~S" command))))
        (bad-request (condition)
          (values (bad-request-json condition) 2))
        (infeasible-slot (condition)
          (values (infeasible-slot-json condition) 1)))
    (values (json-text response) exit-code)))

;;; ----------------------------------------------------------------- the edge

(defun read-everything (stream)
  (with-output-to-string (text)
    (loop for line = (read-line stream nil)
          while line
          do (write-line line text))))

(defun request-text (file)
  "The request, from FILE or, with no FILE, from standard input. NIL when
FILE can't be read."
  (if file
      (handler-case (with-open-file (stream file :external-format :utf-8)
                      (read-everything stream))
        (file-error () nil))
      (read-everything *standard-input*)))

(defun usage ()
  (format *error-output* "usage: beholder assess|solve [REQUEST-FILE]~%~
                          Reads a JSON request from REQUEST-FILE, or from standard input~%~
                          without one, and writes a JSON response to standard output.~%"))

(defun main ()
  "The executable's entry point."
  (sb-ext:disable-debugger)
  (destructuring-bind (&optional command file &rest extra) (rest sb-ext:*posix-argv*)
    (unless (and (member command '("assess" "solve") :test #'equal)
                 (null extra))
      (usage)
      (sb-ext:exit :code 2))
    (let ((text (request-text file)))
      (if (null text)
          (progn
            (write-string (json-text (error-json "bad_request"
                                                 (format nil "can't read ~A" file))))
            (sb-ext:exit :code 2))
          (multiple-value-bind (response exit-code) (respond command text)
            (write-string response)
            (sb-ext:exit :code exit-code))))))
