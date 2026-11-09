;;;; test/json.lisp
;;;;
;;;; The JSON reader and writer, and whole requests run through RESPOND, the
;;;; function the executable calls. The requests are the ones worked through in
;;;; the request-format notes.

(in-package :beholder-tests)

(def-suite json :in beholder-tests)
(in-suite json)

;;; ------------------------------------------------------- reading and writing

(test parse-json-reads-each-kind-of-value
  (is (equal '(:object ("a" . 1) ("b" . (:true :false :null)))
             (parse-json "{\"a\": 1, \"b\": [true, false, null]}")))
  (is (equal (format nil "tab~Chere \"quoted\" é" #\Tab)
             (parse-json "\"tab\\there \\\"quoted\\\" \\u00e9\"")))
  (is (equal '() (parse-json "[]")))
  (is (equal '(:object) (parse-json " {} "))))

(test parse-json-reads-numbers
  (is (eql 16 (parse-json "16")))
  (is (eql -3 (parse-json "-3")))
  (is (eql 4.5d0 (parse-json "4.5")))
  (is (eql 0.008d0 (parse-json "8e-3")))
  (is (eql 100d0 (parse-json "1E2"))))

(test parse-json-joins-surrogate-pairs
  (is (string= (string (code-char #x1F600)) (parse-json "\"\\ud83d\\ude00\""))))

(test parse-json-refuses-broken-json
  (dolist (text '("" "{" "[1,]" "{\"a\" 1}" "{\"a\": 1,}" "tru" "1.}" "\"open"
                  "{\"a\": 1, \"a\": 2}" "[1] [2]" "-" "01x"))
    (signals bad-request (parse-json text))))

(test json-text-round-trips
  (let ((value '(:object ("passed" . :true)
                         ("colors" . (:object ("fg" . "#2f2b25")))
                         ("short_pairs")
                         ("de" . 16.088d0)
                         ("note" . "line one
line two"))))
    (is (equal value (parse-json (json-text value))))))

;;; ----------------------------------------------------------- whole requests

(defun respond-json (command request-text)
  "Run a request the way the executable does. Returns the parsed response and
the exit code."
  (multiple-value-bind (response exit-code) (respond command request-text)
    (values (parse-json response) exit-code)))

(defun field-in (json &rest keys)
  (reduce (lambda (value key) (field value key)) keys :initial-value json))

(defparameter *light-syntax-colors*
  "{\"background\": \"#f2e9d8\",
    \"colors\": {\"builtin\": \"#045b80\", \"comment\": \"#6b6862\",
                 \"constant\": \"#780404\", \"function\": \"#1b25e3\",
                 \"keyword\": \"#8620d9\", \"string\": \"#036831\",
                 \"type\": \"#696406\"},
    \"policy\": {\"floor\": 4.5,
                 \"targets\": {\"default\": 16,
                               \"pairs\": [{\"roles\": [\"keyword\", \"string\"], \"de\": 22},
                                           {\"roles\": [\"comment\", \"string\"], \"de\": 14}]}}}")

(test assess-request-that-passes
  (multiple-value-bind (response exit-code) (respond-json "assess" *light-syntax-colors*)
    (is (= 0 exit-code))
    (is (eq :true (field response "passed")))
    (is (string= "#045b80" (field-in response "colors" "builtin" "hex")))
    (is (close-to 5.685d0 (field-in response "colors" "builtin" "worst_contrast") 1d-3))
    (is (equal '("constant" "type") (field-in response "weakest_pair" "roles")))
    (is (close-to 16.088d0 (field-in response "weakest_pair" "de") 1d-3))
    (is (null (field response "short_pairs")))))

(test assess-request-that-fails
  (multiple-value-bind (response exit-code)
      (respond-json "assess"
                    "{\"background\": \"#f2e9d8\",
                      \"colors\": {\"constant\": \"#780404\", \"type\": \"#696406\",
                                   \"error\": \"#e0443a\"},
                      \"policy\": {\"targets\": {\"default\": 16,
                                                 \"pairs\": [{\"roles\": [\"constant\", \"type\"],
                                                              \"de\": 18}]}}}")
    (is (= 1 exit-code))
    (is (eq :false (field response "passed")))
    (is (eq :false (field-in response "colors" "error" "passed")))
    (is (close-to 2.994d0 (field-in response "colors" "error" "contrast" "deutan") 1d-3))
    (is (= 2 (length (field response "short_pairs"))))))

(test assess-request-with-one-color-has-no-weakest-pair
  (let ((response (respond-json "assess"
                                "{\"background\": \"#f2e9d8\", \"colors\": {\"fg\": \"#2f2b25\"}}")))
    (is (eq :null (field response "weakest_pair")))))

(test bad-requests-say-what-is-wrong
  (dolist (case '(("not json"                                           "JSON")
                  ("{\"colors\": {\"fg\": \"#2f2b25\"}}"                 "background")
                  ("{\"background\": \"#f2e9d8\", \"colors\": {\"fg\": \"blue\"}}" "colors.fg")
                  ("{\"background\": \"#f2e9d8\", \"colors\": {\"fg\": \"#2f2b25\"},
                     \"policy\": {\"observers\": [\"tritan\"]}}"        "tritan")
                  ("{\"background\": \"#f2e9d8\", \"colors\": {\"fg\": \"#2f2b25\"},
                     \"polcy\": {}}"                                    "polcy")))
    (destructuring-bind (request-text expected-in-message) case
      (multiple-value-bind (response exit-code) (respond-json "assess" request-text)
        (is (= 2 exit-code))
        (is (string= "bad_request" (field-in response "error" "kind")))
        (is (search expected-in-message (field-in response "error" "message"))
            "~S doesn't mention ~S" (field-in response "error" "message") expected-in-message)))))

(defparameter *two-slot-request*
  "{\"background\": \"#f2e9d8\",
    \"slots\": {\"blue\": {\"hues\": [205, 224], \"floor\": 5.5,
                           \"max_saturation\": 0.9, \"min_chroma\": 40},
                \"warm\": {\"hues\": [8, 26], \"floor\": 5.0, \"min_chroma\": 44}},
    \"fixed\": {\"fg\": \"#2f2b25\"},
    \"targets\": {\"default\": 16, \"pairs\": [{\"roles\": [\"blue\", \"warm\"], \"de\": 40}]},
    \"search\": {\"lightness\": [0.13, 0.58], \"restarts\": 2}}")

(test solve-request-that-passes
  (multiple-value-bind (response exit-code) (respond-json "solve" *two-slot-request*)
    (is (= 0 exit-code))
    (is (eq :true (field response "passed")))
    (is (= 1 (field response "feasibility")))
    (let ((blue-hex (field-in response "palette" "blue")))
      (is (string= blue-hex (field-in response "colors" "blue" "hex")))
      (is (>= (worst-contrast (hex blue-hex) (hex "#f2e9d8")) 5.5d0)))))

(test solve-reports-mean-chroma-of-the-colors-it-returns
  (let* ((response (respond-json "solve" *two-slot-request*))
         (chromas  (list (field-in response "colors" "blue" "chroma")
                         (field-in response "colors" "warm" "chroma"))))
    (is (close-to (/ (reduce #'+ chromas) 2) (field response "mean_chroma")))))

(test solve-request-with-an-empty-slot
  (multiple-value-bind (response exit-code)
      (respond-json "solve"
                    "{\"background\": \"#f2e9d8\",
                      \"slots\": {\"green\": {\"hues\": [150, 180], \"floor\": 4.6,
                                              \"min_chroma\": 50}},
                      \"search\": {\"lightness\": [0.13, 0.58]}}")
    (is (= 1 exit-code))
    (is (string= "infeasible_slot" (field-in response "error" "kind")))
    (is (string= "green" (field-in response "error" "slot")))
    (is (string= "min_chroma" (field-in response "error" "constraint")))))

(test hue-bands-across-red-wrap
  (let ((problem (read-solve-request
                  (parse-json "{\"background\": \"#ffffff\",
                                \"slots\": {\"red\": {\"hues\": [350, 10], \"floor\": 4.5}}}"))))
    (is (= -10 (slot-hue-low (first (problem-slots problem)))))
    (is (= 10 (slot-hue-high (first (problem-slots problem)))))))

;;; ---------------------------------------------------------- the examples
;;; Every file in examples/ has to stay a valid request. The solves aren't run
;;; here (the dark ones take seconds each), but the colors in use are checked.

(defun example-files (name)
  "The JSON files in examples/'s theme directories called NAME, or every one
for :WILD."
  (directory (merge-pathnames (make-pathname :directory '(:relative "examples" :wild)
                                             :name name
                                             :type "json")
                              (asdf:system-source-directory "beholder"))))

(defun file-text (path)
  (with-open-file (stream path :external-format :utf-8)
    (let* ((text   (make-string (file-length stream)))
           (length (read-sequence text stream)))
      (subseq text 0 length))))

(test example-solve-requests-read
  (let ((solve-files (remove "deployed" (example-files :wild)
                             :key #'pathname-name :test #'string=)))
    (is (= 7 (length solve-files)))
    (dolist (path solve-files)
      (is (typep (read-solve-request (parse-json (file-text path))) 'problem)
          "~A doesn't read as a solve request" path))))

(test colors-in-use-pass
  (let ((deployed-files (example-files "deployed")))
    (is (= 2 (length deployed-files)))
    (dolist (path deployed-files)
      (multiple-value-bind (response exit-code) (respond-json "assess" (file-text path))
        (is (= 0 exit-code) "~A fails: ~S" path response)))))

(test a-role-cannot-be-slot-and-fixed
  (signals bad-request
    (read-solve-request
     (parse-json "{\"background\": \"#ffffff\",
                   \"slots\": {\"fg\": {\"hues\": [0, 20], \"floor\": 4.5}},
                   \"fixed\": {\"fg\": \"#000000\"}}"))))
