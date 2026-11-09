;;;; test/assess.lisp

(in-package :beholder-tests)

(def-suite assess :in beholder-tests)
(in-suite assess)

(defparameter *paper* (hex "#f2e9d8"))

(test target-lookup-ignores-pair-order
  (let ((targets (targets 16 '(("keyword" "string" 22)))))
    (is (= 22d0 (target-for targets "keyword" "string")))
    (is (= 22d0 (target-for targets "string" "keyword")))
    (is (= 16d0 (target-for targets "keyword" "type")))))

(test assess-passes-dark-ink-on-paper
  (let ((report (assess *paper* (list (cons "fg" (hex "#2f2b25"))))))
    (is (report-passed-p report))
    (is (zerop (report-failures report)))))

(test assess-flags-a-color-below-the-floor
  (let* ((report  (assess *paper* (list (cons "fg"    (hex "#2f2b25"))
                                        (cons "faint" (hex "#d8cfbe")))))
         (faint   (find "faint" (report-measures report)
                        :key #'measure-role :test #'string=)))
    (is (= 1 (report-failures report)))
    (is (not (measure-passes-floor-p faint)))
    (is (not (report-passed-p report)))))

(test assess-measures-every-observer
  (let* ((report  (assess *paper* (list (cons "fg" (hex "#2f2b25")))))
         (measure (first (report-measures report))))
    (is (equal '("normal" "protan" "deutan")
               (mapcar #'car (measure-contrasts measure))))))

(test assess-checks-the-ceiling
  (let* ((policy (make-policy :ceiling 5d0))
         (report (assess *paper* (list (cons "fg" (hex "#2f2b25"))) policy)))
    (is (not (measure-under-ceiling-p (first (report-measures report)))))))

(test weakest-pair-names-the-closest-roles
  (let ((report (assess *paper* (list (cons "red"    (hex "#aa2222"))
                                      (cons "maroon" (hex "#992222"))
                                      (cons "blue"   (hex "#2233aa"))))))
    (is (equal '("maroon" "red") (report-weakest-pair report)))))

(test short-pairs-only-with-targets
  (let ((entries (list (cons "red"    (hex "#aa2222"))
                       (cons "maroon" (hex "#992222")))))
    (is (null (report-short-pairs (assess *paper* entries))))
    (let ((report (assess *paper* entries
                          (make-policy :targets (targets 16 '())))))
      (is (= 1 (length (report-short-pairs report))))
      (is (not (report-passed-p report))))))

(test report-json-carries-the-hexes
  (let ((json (report-json (assess *paper* (list (cons "fg" (hex "#2f2b25")))))))
    (is (string= "#f2e9d8" (field json "background")))
    (is (string= "#2f2b25" (field (field (field json "colors") "fg") "hex")))))
