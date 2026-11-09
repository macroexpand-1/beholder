;;;; beholder.asd

(defsystem "beholder"
  :description "Check a color palette, or have one found for you. Measures
contrast, colorfulness and how far apart colors look, and searches for the most
colorful set that meets your targets. No dependencies."
  :author "Real Limoges"
  :license "BSD-2-Clause"
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "color")
                             (:file "assess")
                             (:file "solve")
                             (:file "json")
                             (:file "main"))))
  :in-order-to ((test-op (test-op "beholder/tests"))))

(defsystem "beholder/tests"
  :description "Tests for beholder. Run them with (asdf:test-system \"beholder\")."
  :depends-on ("beholder" "fiveam")
  :serial t
  :components ((:module "test"
                :components ((:file "package")
                             (:file "color")
                             (:file "assess")
                             (:file "solve")
                             (:file "json"))))
  :perform (test-op (o c)
                    (declare (ignore o c))
                    (unless (uiop:symbol-call :fiveam :run!
                                              (uiop:find-symbol* :beholder-tests
                                                                 :beholder-tests))
                      (error "beholder tests failed"))))
