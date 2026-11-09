#!/usr/bin/env -S sbcl --script
;;;; build.lisp: build the beholder executable.
;;;;
;;;;   ./build.lisp        # writes bin/beholder
;;;;
;;;; It loads beholder into SBCL and saves the whole image as one file you can
;;;; run, so the executable needs nothing installed, not even SBCL. Building
;;;; it needs only SBCL.

(require :asdf)
(asdf:load-asd (merge-pathnames "beholder.asd" *load-truename*))
(asdf:load-system "beholder")

;; The repo directory, without this file's name and .lisp type, so neither
;; leaks into the executable's name.
(let* ((repo-directory (make-pathname :name nil :type nil :defaults *load-truename*))
       (executable     (merge-pathnames "bin/beholder" repo-directory)))
  (ensure-directories-exist executable)
  (format t "writing ~A~%" (namestring executable))
  (finish-output)
  ;; SAVE-RUNTIME-OPTIONS keeps SBCL from reading options such as --help off
  ;; the command line, so every argument reaches MAIN.
  (sb-ext:save-lisp-and-die executable
                            :executable t
                            :toplevel #'beholder:main
                            :save-runtime-options t))
