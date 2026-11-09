;;;; json.lisp: requests in and results out, as JSON.
;;;;
;;;; Programs in other languages talk to beholder in JSON. This file reads a
;;;; request into the values ASSESS and SOLVE take, and turns what they return
;;;; back into JSON. It is a small JSON reader and writer of its own, so
;;;; beholder needs nothing beyond SBCL.
;;;;
;;;; A JSON value looks like this on the Lisp side:
;;;;
;;;;     object          (:object ("key" . value) ...), keys in the order written
;;;;     array           a list
;;;;     string          a string
;;;;     number          an integer if written without a point or exponent,
;;;;                     otherwise a double-float
;;;;     true, false     :true, :false
;;;;     null            :null
;;;;
;;;; An object and an array can't be confused: no JSON value reads as the
;;;; keyword :OBJECT, so a list starting with it is always an object.

(in-package :beholder)

;;; ------------------------------------------------------------- bad requests

(define-condition bad-request (error)
  ((message :initarg :message :reader bad-request-message))
  (:documentation "The request can't be answered as written: it isn't JSON, a
field is missing or the wrong type, a color isn't a hex code, and so on.")
  (:report (lambda (condition stream)
             (write-string (bad-request-message condition) stream))))

(defun bad-request (format-string &rest args)
  (error 'bad-request :message (apply #'format nil format-string args)))

;;; ------------------------------------------------------------------ reading

(defun whitespace-p (character)
  (member character '(#\Space #\Tab #\Newline #\Return)))

(defun skip-whitespace (stream)
  (loop while (whitespace-p (peek-char nil stream nil))
        do (read-char stream)))

(defun next-char (stream)
  "Skip whitespace and look at the next character without taking it."
  (skip-whitespace stream)
  (or (peek-char nil stream nil)
      (bad-request "the JSON ends too soon")))

(defun expect-char (stream expected)
  (let ((found (read-char stream nil)))
    (unless (eql found expected)
      (bad-request "the JSON has ~:[nothing~;~:*~S~] where ~S should be" found expected))))

(defun read-json-value (stream)
  (let ((character (next-char stream)))
    (cond ((char= character #\{) (read-json-object stream))
          ((char= character #\[) (read-json-array stream))
          ((char= character #\") (read-json-string stream))
          ((or (char= character #\-) (digit-char-p character)) (read-json-number stream))
          ((char= character #\t) (read-json-word stream "true" :true))
          ((char= character #\f) (read-json-word stream "false" :false))
          ((char= character #\n) (read-json-word stream "null" :null))
          (t (bad-request "the JSON has ~S where a value should be" character)))))

(defun read-json-object (stream)
  (expect-char stream #\{)
  (let ((members '()))
    (unless (char= (next-char stream) #\})
      (loop
        (unless (char= (next-char stream) #\")
          (bad-request "an object key in the JSON isn't a string"))
        (let ((key (read-json-string stream)))
          (when (assoc key members :test #'string=)
            (bad-request "the key ~S appears twice in one object" key))
          (next-char stream)
          (expect-char stream #\:)
          (push (cons key (read-json-value stream)) members))
        (if (char= (next-char stream) #\,)
            (read-char stream)
            (return))))
    (expect-char stream #\})
    (cons :object (nreverse members))))

(defun read-json-array (stream)
  (expect-char stream #\[)
  (let ((elements '()))
    (unless (char= (next-char stream) #\])
      (loop
        (push (read-json-value stream) elements)
        (if (char= (next-char stream) #\,)
            (read-char stream)
            (return))))
    (expect-char stream #\])
    (nreverse elements)))

(defun read-four-hex-digits (stream)
  (let ((digits (make-string 4)))
    (dotimes (index 4)
      (let ((character (read-char stream nil)))
        (unless (and character (digit-char-p character 16))
          (bad-request "a \\u escape in the JSON needs four hex digits"))
        (setf (char digits index) character)))
    (parse-integer digits :radix 16)))

(defun read-unicode-escape (stream)
  "The character after a \\u. Characters outside the Basic Multilingual Plane
come as two escapes in a row (a surrogate pair), which join into one."
  (let ((code (read-four-hex-digits stream)))
    (if (<= #xD800 code #xDBFF)
        (progn
          (expect-char stream #\\)
          (expect-char stream #\u)
          (let ((low-code (read-four-hex-digits stream)))
            (unless (<= #xDC00 low-code #xDFFF)
              (bad-request "a \\u escape in the JSON is half of a surrogate pair"))
            (code-char (+ #x10000
                          (ash (- code #xD800) 10)
                          (- low-code #xDC00)))))
        (code-char code))))

(defun read-escape (stream)
  "The character a backslash escape stands for."
  (let ((character (read-char stream nil)))
    (case character
      (#\" #\")
      (#\\ #\\)
      (#\/ #\/)
      (#\b #\Backspace)
      (#\f #\Page)
      (#\n #\Newline)
      (#\r #\Return)
      (#\t #\Tab)
      (#\u (read-unicode-escape stream))
      (t (bad-request "the JSON has an unknown escape \\~:[~;~:*~A~]" character)))))

(defun read-json-string (stream)
  (expect-char stream #\")
  (with-output-to-string (text)
    (loop for character = (read-char stream nil)
          do (cond ((null character)
                    (bad-request "a string in the JSON never ends"))
                   ((char= character #\")
                    (return))
                   ((char= character #\\)
                    (write-char (read-escape stream) text))
                   ((< (char-code character) 32)
                    (bad-request "a string in the JSON has a raw control character"))
                   (t
                    (write-char character text))))))

(defun read-digits (stream)
  "One or more digits, as a string."
  (let ((digits (with-output-to-string (text)
                  (loop while (digit-char-p (or (peek-char nil stream nil) #\x))
                        do (write-char (read-char stream) text)))))
    (when (zerop (length digits))
      (bad-request "a number in the JSON is missing its digits"))
    digits))

(defun read-json-number (stream)
  "Worked out exactly as a fraction first, then turned into a float, so the
number isn't rounded twice."
  (flet ((take-if (&rest characters)
           (when (member (peek-char nil stream nil) characters)
             (read-char stream))))
    (let* ((sign            (if (take-if #\-) -1 1))
           (whole-digits    (read-digits stream))
           (fraction-digits (if (take-if #\.) (read-digits stream) ""))
           (has-exponent    (take-if #\e #\E))
           (exponent-sign   (if (and has-exponent (eql (take-if #\+ #\-) #\-)) -1 1))
           (exponent-digits (if has-exponent (read-digits stream) "0"))
           (exponent        (* exponent-sign (parse-integer exponent-digits))))
      (when (> (abs exponent) 400)
        (bad-request "a number in the JSON is too large or too small"))
      (let ((exact (* sign
                      (parse-integer (concatenate 'string whole-digits fraction-digits))
                      (expt 10 (- exponent (length fraction-digits))))))
        (if (or has-exponent (plusp (length fraction-digits)))
            (float exact 1d0)
            exact)))))

(defun read-json-word (stream word value)
  (loop for expected across word
        do (unless (eql (read-char stream nil) expected)
             (bad-request "the JSON has a misspelled ~A" word)))
  value)

(defun parse-json (text)
  "Read TEXT, which holds one JSON value and nothing else."
  (with-input-from-string (stream text)
    (let ((value (read-json-value stream)))
      (skip-whitespace stream)
      (when (peek-char nil stream nil)
        (bad-request "the JSON has more after its end"))
      value)))

;;; ------------------------------------------------------------------ writing
;;; Indented two spaces per level, so a person can read it too.

(defun json-object (&rest keys-and-values)
  "Build an object: (json-object \"passed\" :true \"de\" 16.1)."
  (cons :object (loop for (key value) on keys-and-values by #'cddr
                      collect (cons key value))))

(defun json-boolean (true-p)
  (if true-p :true :false))

(defun json-object-p (value)
  (and (consp value) (eq (first value) :object)))

(defun write-json-string (string stream)
  (write-char #\" stream)
  (loop for character across string
        for code = (char-code character)
        do (cond ((char= character #\") (write-string "\\\"" stream))
                 ((char= character #\\) (write-string "\\\\" stream))
                 ((char= character #\Newline) (write-string "\\n" stream))
                 ((char= character #\Return) (write-string "\\r" stream))
                 ((char= character #\Tab) (write-string "\\t" stream))
                 ((< code 32) (format stream "\\u~4,'0x" code))
                 (t (write-char character stream))))
  (write-char #\" stream))

(defun write-json-number (number stream)
  (if (integerp number)
      (format stream "~D" number)
      ;; With doubles as the default, Lisp prints 65.3 rather than 65.3d0.
      (let ((*read-default-float-format* 'double-float))
        (prin1 (float number 1d0) stream))))

(defun write-newline-and-indent (depth stream)
  (terpri stream)
  (dotimes (step depth)
    (write-string "  " stream)))

(defun write-json-value (value stream depth)
  (cond ((eq value :true)  (write-string "true" stream))
        ((eq value :false) (write-string "false" stream))
        ((eq value :null)  (write-string "null" stream))
        ((stringp value)   (write-json-string value stream))
        ((realp value)     (write-json-number value stream))
        ((json-object-p value)
         (if (null (rest value))
             (write-string "{}" stream)
             (progn
               (write-char #\{ stream)
               (loop for ((key . member-value) . later) on (rest value)
                     do (write-newline-and-indent (1+ depth) stream)
                        (write-json-string key stream)
                        (write-string ": " stream)
                        (write-json-value member-value stream (1+ depth))
                        (when later (write-char #\, stream)))
               (write-newline-and-indent depth stream)
               (write-char #\} stream))))
        ((listp value)
         (cond
           ((null value)
            (write-string "[]" stream))
           ;; A list of plain values, like ["keyword", "string"], fits on one line.
           ((notany #'consp value)
            (write-char #\[ stream)
            (loop for (element . later) on value
                  do (write-json-value element stream depth)
                     (when later (write-string ", " stream)))
            (write-char #\] stream))
           (t
            (write-char #\[ stream)
            (loop for (element . later) on value
                  do (write-newline-and-indent (1+ depth) stream)
                     (write-json-value element stream (1+ depth))
                     (when later (write-char #\, stream)))
            (write-newline-and-indent depth stream)
            (write-char #\] stream))))
        (t (error "~S has no JSON form" value))))

(defun json-text (value)
  "VALUE as JSON text, ending in a newline."
  (with-output-to-string (stream)
    (write-json-value value stream 0)
    (terpri stream)))

;;; -------------------------------------------------------- reading a request
;;; Each reader names where in the request it is looking (WHERE, such as
;;; "slots.keyword.floor"), so a bad request says which field is wrong.

(defun field (object key)
  "The value under KEY in OBJECT, and whether it was there."
  (let ((member (assoc key (rest object) :test #'string=)))
    (values (cdr member) (and member t))))

(defun field-path (where key)
  (if where (format nil "~A.~A" where key) key))

(defun check-object (value where allowed-keys)
  "Make sure VALUE is an object with no keys beyond ALLOWED-KEYS. A misspelled
key would otherwise be quietly ignored."
  (unless (json-object-p value)
    (bad-request "~A should be an object" (or where "the request")))
  (loop for (key . member-value) in (rest value)
        unless (member key allowed-keys :test #'string=)
          do (bad-request "~A has an unknown field ~S (it takes ~{~A~^, ~})"
                          (or where "the request") key allowed-keys))
  value)

(defun required-field (object key where)
  (multiple-value-bind (value present-p) (field object key)
    (unless present-p
      (bad-request "~A is missing" (field-path where key)))
    value))

(defun optional-field (object key default)
  "The value under KEY, or DEFAULT when it's missing or null."
  (multiple-value-bind (value present-p) (field object key)
    (if (or (not present-p) (eq value :null))
        default
        value)))

(defun read-number (value where &key (minimum nil) (maximum nil))
  (unless (realp value)
    (bad-request "~A should be a number" where))
  (when (and minimum (< value minimum))
    (bad-request "~A is ~A; it can't be below ~A" where value minimum))
  (when (and maximum (> value maximum))
    (bad-request "~A is ~A; it can't be above ~A" where value maximum))
  (float value 1d0))

(defun read-positive-number (value where)
  (let ((number (read-number value where)))
    (unless (plusp number)
      (bad-request "~A is ~A; it has to be above 0" where value))
    number))

(defun read-integer (value where &key (minimum nil))
  (unless (integerp value)
    (bad-request "~A should be a whole number" where))
  (when (and minimum (< value minimum))
    (bad-request "~A is ~A; it can't be below ~A" where value minimum))
  value)

(defun hex-code-p (string)
  "True for \"#rrggbb\", with the # optional."
  (let ((digits (string-left-trim "#" string)))
    (and (= (length digits) 6)
         (<= (- (length string) (length digits)) 1)
         (every (lambda (character) (digit-char-p character 16)) digits))))

(defun read-color (value where)
  (unless (and (stringp value) (hex-code-p value))
    (bad-request "~A should be a color like \"#f2e9d8\"" where))
  (hex value))

(defun read-colors (value where)
  "An object of role to hex, as a list of (ROLE . COLOR)."
  (unless (json-object-p value)
    (bad-request "~A should be an object of role to color" where))
  (loop for (role . hex-string) in (rest value)
        collect (cons role (read-color hex-string (field-path where role)))))

(defun read-pair (value where)
  "A two-number list, such as [272, 322]."
  (unless (and (listp value) (not (json-object-p value)) (= (length value) 2))
    (bad-request "~A should be a list of two numbers" where))
  value)

(defparameter +observers-by-name+
  (list +normal+ +protan+ +deutan+))

(defun read-observers (value where)
  (unless (and (listp value) (not (json-object-p value)) value)
    (bad-request "~A should be a list of observer names" where))
  (loop for name in value
        for observer = (and (stringp name)
                            (find name +observers-by-name+
                                  :key #'observer-name :test #'string=))
        unless observer
          do (bad-request "~A has ~S; the observers are ~{~A~^, ~}"
                          where name (mapcar #'observer-name +observers-by-name+))
        collect observer))

(defun read-targets (value where)
  "{\"default\": 16, \"pairs\": [{\"roles\": [a, b], \"de\": 22}, ...]}"
  (check-object value where '("default" "pairs"))
  (let ((default (read-positive-number (optional-field value "default" 16)
                                       (field-path where "default")))
        (pairs   (optional-field value "pairs" '())))
    (unless (and (listp pairs) (not (json-object-p pairs)))
      (bad-request "~A should be a list" (field-path where "pairs")))
    (targets default
             (loop for pair in pairs
                   for index from 0
                   for pair-where = (format nil "~A.pairs[~D]" where index)
                   collect (progn
                             (check-object pair pair-where '("roles" "de"))
                             (let ((roles (required-field pair "roles" pair-where)))
                               (unless (and (listp roles)
                                            (= (length roles) 2)
                                            (every #'stringp roles))
                                 (bad-request "~A.roles should be two role names" pair-where))
                               (list (first roles)
                                     (second roles)
                                     (read-positive-number (required-field pair "de" pair-where)
                                                           (field-path pair-where "de")))))))))

(defun read-ceiling (value where)
  "NIL (no ceiling) when the request leaves it out or gives null."
  (and value (read-positive-number value where)))

;;; ----------------------------------------------------- the assess request

(defun read-policy (value)
  (check-object value "policy" '("floor" "ceiling" "targets" "observers"))
  (let ((targets (optional-field value "targets" nil)))
    (make-policy
     :floor     (read-number (optional-field value "floor" 4.5d0) "policy.floor")
     :ceiling   (read-ceiling (optional-field value "ceiling" nil) "policy.ceiling")
     :targets   (and targets (read-targets targets "policy.targets"))
     :observers (read-observers (optional-field value "observers" '("normal" "protan" "deutan"))
                                "policy.observers"))))

(defun read-assess-request (request)
  "The background, the (ROLE . COLOR) entries and the policy ASSESS takes."
  (check-object request nil '("background" "colors" "policy"))
  (let ((colors (read-colors (required-field request "colors" nil) "colors")))
    (when (null colors)
      (bad-request "colors is empty; there's nothing to check"))
    (values (read-color (required-field request "background" nil) "background")
            colors
            (read-policy (optional-field request "policy" (json-object))))))

;;; ------------------------------------------------------ the solve request

(defun read-hue-band (value where)
  "Hues in degrees as (LOW HIGH). A band across red, such as [350, 10], wraps:
it becomes -10 to 10."
  (destructuring-bind (low high) (read-pair value where)
    (let ((low  (read-integer low where))
          (high (read-integer high where)))
      (if (> low high)
          (list (- low 360) high)
          (list low high)))))

(defun read-slot (role value grid)
  (let ((where (field-path "slots" role)))
    (check-object value where '("hues" "floor" "max_saturation" "min_chroma"))
    (destructuring-bind (hue-low hue-high)
        (read-hue-band (required-field value "hues" where) (field-path where "hues"))
      (let ((max-saturation (read-number (optional-field value "max_saturation" 1d0)
                                         (field-path where "max_saturation")
                                         :minimum 0 :maximum 1)))
        (when (< max-saturation (grid-sat-min grid))
          (bad-request "~A is ~A, below search.saturation_min (~A), so nothing would be tried"
                       (field-path where "max_saturation") max-saturation (grid-sat-min grid)))
        (slot role hue-low hue-high
              (read-number (required-field value "floor" where) (field-path where "floor"))
              max-saturation
              (read-number (optional-field value "min_chroma" 0d0)
                           (field-path where "min_chroma") :minimum 0))))))

(defun read-slots (value grid)
  (unless (and (json-object-p value) (rest value))
    (bad-request "slots should be an object of role to slot, with at least one slot"))
  (loop for (role . slot-value) in (rest value)
        collect (read-slot role slot-value grid)))

(defun read-search (value)
  "The grid of colors tried, and how many restarts."
  (check-object value "search" '("lightness" "restarts" "hue_step" "saturation_min"
                                 "saturation_step" "lightness_step"))
  (destructuring-bind (light-min light-max)
      (read-pair (optional-field value "lightness" '(0 1)) "search.lightness")
    (let ((light-min (read-number light-min "search.lightness" :minimum 0 :maximum 1))
          (light-max (read-number light-max "search.lightness" :minimum 0 :maximum 1)))
      (when (> light-min light-max)
        (bad-request "search.lightness runs from ~A down to ~A; put the lower one first"
                     light-min light-max))
      (values
       (make-grid :light-min  light-min
                  :light-max  light-max
                  :hue-stride (read-integer (optional-field value "hue_step" 3)
                                            "search.hue_step" :minimum 1)
                  :sat-min    (read-number (optional-field value "saturation_min" 0.34d0)
                                           "search.saturation_min" :minimum 0 :maximum 1)
                  :sat-step   (read-positive-number (optional-field value "saturation_step" 0.05d0)
                                                    "search.saturation_step")
                  :light-step (read-positive-number (optional-field value "lightness_step" 0.008d0)
                                                    "search.lightness_step"))
       (read-integer (optional-field value "restarts" 8) "search.restarts" :minimum 1)))))

(defun read-solve-request (request)
  "The PROBLEM that SOLVE takes."
  (check-object request nil '("background" "slots" "fixed" "targets" "ceiling"
                              "observers" "search"))
  (multiple-value-bind (grid restarts)
      (read-search (optional-field request "search" (json-object)))
    (let* ((slots   (read-slots (required-field request "slots" nil) grid))
           (fixed   (read-colors (optional-field request "fixed" (json-object)) "fixed"))
           (targets (optional-field request "targets" nil)))
      (loop for (role . color) in fixed
            when (find role slots :key #'slot-name :test #'string=)
              do (bad-request "~S is both a slot and a fixed color" role))
      (make-problem
       :background (read-color (required-field request "background" nil) "background")
       :slots      slots
       :fixed      fixed
       :targets    (if targets (read-targets targets "targets") (targets 16 '()))
       :ceiling    (read-ceiling (optional-field request "ceiling" nil) "ceiling")
       :grid       grid
       :restarts   restarts
       :observers  (read-observers (optional-field request "observers"
                                                   '("normal" "protan" "deutan"))
                                   "observers")))))

;;; ---------------------------------------------------------- writing results

(defun measure-json (measure &key (with-passed t))
  (let ((contrasts (loop for (observer-name . ratio) in (measure-contrasts measure)
                         append (list observer-name ratio))))
    (apply #'json-object
           "hex"            (color-hex (measure-color measure))
           "contrast"       (apply #'json-object contrasts)
           "worst_contrast" (measure-worst-contrast measure)
           "chroma"         (measure-chroma measure)
           "lstar"          (measure-lstar measure)
           (and with-passed
                (list "passed" (json-boolean (measure-passed-p measure)))))))

(defun measures-json (report &key (with-passed t))
  "Each color's measurements, keyed by role."
  (apply #'json-object
         (loop for measure in (report-measures report)
               append (list (measure-role measure)
                            (measure-json measure :with-passed with-passed)))))

(defun weakest-pair-json (roles distance)
  "NIL roles means fewer than two colors, so there's no pair."
  (if roles
      (json-object "roles" roles "de" distance)
      :null))

(defun report-json (report)
  "What ASSESS found, as the JSON `beholder assess` writes."
  (json-object
   "passed"       (json-boolean (report-passed-p report))
   "background"   (color-hex (report-background report))
   "colors"       (measures-json report)
   "weakest_pair" (weakest-pair-json (report-weakest-pair report)
                                     (report-weakest-de report))
   "short_pairs"  (loop for (role-a role-b distance target) in (report-short-pairs report)
                        collect (json-object "roles"  (list role-a role-b)
                                             "de"     distance
                                             "target" target))))

(defun result-json (result problem)
  "What SOLVE found, as the JSON `beholder solve` writes. The colors are
measured the same way ASSESS measures them."
  (let* ((palette (result-palette result))
         (report  (assess (problem-background problem)
                          palette
                          (make-policy :observers (problem-observers problem)))))
    (json-object
     "passed"       (json-boolean (>= (result-feasibility result) 1d0))
     "background"   (color-hex (problem-background problem))
     "palette"      (apply #'json-object
                           (loop for (role . color) in palette
                                 append (list role (color-hex color))))
     "colors"       (measures-json report :with-passed nil)
     "feasibility"  (result-feasibility result)
     "mean_chroma"  (result-mean-chroma result)
     "weakest_pair" (weakest-pair-json (result-weakest-pair result)
                                       (result-weakest-de result)))))

(defun error-json (kind message &rest more-fields)
  (json-object "passed" :false
               "error"  (apply #'json-object "kind" kind
                               (append more-fields (list "message" message)))))

(defun bad-request-json (condition)
  (error-json "bad_request" (bad-request-message condition)))

(defun infeasible-slot-json (condition)
  (error-json "infeasible_slot" (princ-to-string condition)
              "slot"       (slot-name (infeasible-slot-slot condition))
              "constraint" (ecase (infeasible-slot-constraint condition)
                             (:floor      "floor")
                             (:ceiling    "ceiling")
                             (:chroma-min "min_chroma"))))
