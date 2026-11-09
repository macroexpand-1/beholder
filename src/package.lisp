;;;; package.lisp

(defpackage :beholder
  (:use :cl)
  (:export
   ;; Colors and measuring them (color.lisp)
   #:color #:colorp #:color-r #:color-g #:color-b
   #:hex #:hsl #:color-hex
   #:luminance #:contrast-ratio #:lab #:lstar #:chroma
   #:observer #:make-observer #:observer-name #:observer-matrix
   #:+normal+ #:+protan+ #:+deutan+ #:+default-observers+
   #:simulate #:worst-contrast
   #:profile #:separation

   ;; Checking a palette you have (assess.lisp)
   #:targets #:make-targets #:targets-default #:target-for
   #:under-ceiling-p #:weakest-pair
   #:policy #:make-policy #:policy-floor #:policy-ceiling
   #:policy-targets #:policy-observers
   #:role-measure #:measure-role #:measure-color #:measure-contrasts
   #:measure-worst-contrast #:measure-chroma #:measure-lstar
   #:measure-passes-floor-p #:measure-under-ceiling-p #:measure-passed-p
   #:report #:report-background #:report-measures #:report-weakest-pair
   #:report-weakest-de #:report-short-pairs #:report-failures
   #:report-passed-p
   #:assess

   ;; Finding a palette (solve.lisp)
   #:slot #:slot-name #:slot-hue-low #:slot-hue-high #:slot-floor
   #:slot-smax #:slot-cmin
   #:grid #:make-grid #:grid-light-min #:grid-light-max #:grid-hue-stride
   #:grid-sat-min #:grid-sat-step #:grid-light-step
   #:problem #:make-problem #:problem-background #:problem-slots
   #:problem-fixed #:problem-targets #:problem-ceiling #:problem-grid
   #:problem-restarts #:problem-observers
   #:result #:result-palette #:result-feasibility #:result-mean-chroma
   #:result-weakest-pair #:result-weakest-de
   #:infeasible-slot #:infeasible-slot-slot #:infeasible-slot-constraint
   #:solve

   ;; Requests and results as JSON (json.lisp)
   #:bad-request #:bad-request-message
   #:parse-json #:json-text #:json-object #:json-object-p #:field
   #:read-assess-request #:read-solve-request
   #:report-json #:result-json

   ;; The command (main.lisp)
   #:respond #:main))
