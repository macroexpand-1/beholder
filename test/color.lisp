;;;; test/color.lisp

(in-package :beholder-tests)

(def-suite color :in beholder-tests)
(in-suite color)

(test hex-round-trips
  (dolist (hex-string '("#000000" "#ffffff" "#f2e9d8" "#8620d9" "#036831"))
    (is (string= hex-string (color-hex (hex hex-string))))))

(test hex-accepts-uppercase-and-no-hash
  (is (string= "#f2e9d8" (color-hex (hex "F2E9D8")))))

(test black-on-white-is-21-to-1
  (is (close-to 21d0 (contrast-ratio (hex "#000000") (hex "#ffffff")))))

(test contrast-ratio-is-symmetric
  (let ((ink   (hex "#2f2b25"))
        (paper (hex "#f2e9d8")))
    (is (= (contrast-ratio ink paper) (contrast-ratio paper ink)))))

(test hsl-primaries
  (is (string= "#ff0000" (color-hex (hsl 0 1d0 0.5d0))))
  (is (string= "#00ff00" (color-hex (hsl 120 1d0 0.5d0))))
  (is (string= "#0000ff" (color-hex (hsl 240 1d0 0.5d0)))))

(test grays-have-no-chroma
  ;; Not exactly zero: the standard constants are rounded, which leaves a
  ;; gray with about 0.01 chroma. Nobody could see that.
  (dolist (hex-string '("#202020" "#808080" "#ffffff"))
    (is (close-to 0d0 (chroma (hex hex-string)) 0.05d0))))

(test worst-contrast-is-at-most-the-normal-observers
  (let ((paper (hex "#f2e9d8")))
    (dolist (hex-string '("#780404" "#036831" "#1b25e3"))
      (let ((ink (hex hex-string)))
        (is (<= (worst-contrast ink paper) (contrast-ratio ink paper)))))))

(test pure-red-loses-contrast-for-a-protan
  ;; Red looks darker to a protan than to normal vision.
  (let ((red   (hex "#ff0000"))
        (black (hex "#000000")))
    (is (< (worst-contrast red black)
           (worst-contrast red black :observers (list +normal+))))))

(test separation-is-symmetric
  (let ((violet (profile (hex "#8620d9")))
        (blue   (profile (hex "#1b25e3"))))
    (is (= (separation violet blue) (separation blue violet)))))

(test separation-is-the-closest-observers-distance
  (let* ((red   (hex "#cc3333"))
         (green (hex "#33aa33"))
         (each-observer (loop for observer in +default-observers+
                              collect (separation
                                       (profile red :observers (list observer))
                                       (profile green :observers (list observer))))))
    (is (close-to (reduce #'min each-observer)
                  (separation (profile red) (profile green))))))

(test a-color-is-zero-from-itself
  (let ((teal (profile (hex "#045b80"))))
    (is (zerop (separation teal teal)))))
