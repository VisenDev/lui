(defpackage #:lui.font
  (:use #:cl #:lui.fn)
  (:import-from #:lui.js #:property #:invoke #:global)
  (:export #:font #:open-font #:close-font #:font-size #:font-loader
           #:text-width #:line-height #:baseline #:wrap-text #:glyph-polygons
           #:*font-path* #:*font-paths* #:*font-directories*
           #:*font-names* #:font-face #:font-css))

(in-package #:lui.font)

(lui::expose-api font open-font close-font font-size text-width line-height
                 baseline wrap-text glyph-polygons *font-path* *font-paths*
                 *font-directories* *font-names* font-face)

(defvar *font-path* nil)
(defvar *font-paths* nil)
(defvar *font-directories* nil)
(defvar *font-names* nil)

(defstruct font
  "A browser font face with a Canvas context for measuring text." loader owner
  (faces (make-array 4 :initial-element nil))
  (size 16)
  (family :sans-serif)
  (weight :normal) css-value css-size
  (metrics (make-hash-table :test 'equal))
  (wrapped (make-hash-table :test 'equal)))

(fn (open-font font) (&optional path ((size real) 16))
  "Create a browser font at SIZE; PATH is accepted for API compatibility."
  (declare (ignore path))
  (let ((canvas (invoke (global "document") "createElement" "canvas")))
    (make-font :loader (invoke canvas "getContext" "2d") :size size)))

(fn (close-font null) ((font font))
  (dotimes (index (length (font-faces font)))
    (setf (aref (font-faces font) index) nil))
  (clrhash (font-metrics font))
  (clrhash (font-wrapped font))
  (setf (font-loader font) nil))

(fn (font-face font) ((font font) (family symbol) (weight symbol))
  (let ((owner (or (font-owner font) font))
        (index (+ (ecase family (:sans-serif 0) (:monospace 2))
                  (ecase weight (:normal 0) (:bold 1)))))
    (if (zerop index) owner
        (or (aref (font-faces owner) index)
            (setf (aref (font-faces owner) index)
                  (make-font :loader (font-loader owner) :owner owner
                             :size (font-size owner)
                             :family family :weight weight))))))

(fn (font-css string) ((font font))
  "Return the CSS font shorthand used by measurement and drawing."
  (unless (eql (font-css-size font) (font-size font))
    (setf (font-css-size font) (font-size font)
          (font-css-value font)
          (format nil "~A ~Apx ~A"
                  (if (eq (font-weight font) :bold) "bold" "normal")
                  (invoke (global) "String" (font-size font))
                  (if (eq (font-family font) :monospace)
                      "monospace" "sans-serif"))))
  (font-css-value font))

(fn (measure-text t) ((font font) (text string))
  (let ((css (font-css font))
        (cache (font-metrics font))
        (key (list (font-size font) text)))
    (or (gethash key cache)
        (let ((context (font-loader font)))
          (when (>= (hash-table-count cache) 2048) (clrhash cache))
          (setf (property context "font") css)
          (setf (gethash key cache)
                (invoke context "measureText" text))))))

(fn (text-width real) ((font font) (text string))
  (property (measure-text font text) "width"))

(fn (baseline real) ((font font))
  (let ((ascent (property (measure-text font "Mg") "fontBoundingBoxAscent")))
    (if (and (numberp ascent) (plusp ascent))
        ascent (* (font-size font) 0.8f0))))

(fn (line-height real) ((font font))
  (let* ((metrics (measure-text font "Mg"))
         (ascent (property metrics "fontBoundingBoxAscent"))
         (descent (property metrics "fontBoundingBoxDescent")))
    (if (and (numberp ascent) (numberp descent)
             (plusp (+ ascent descent)))
        (max (* (font-size font) 1.2f0) (+ ascent descent))
        (* (font-size font) 1.2f0))))

(fn (glyph-polygons nil) ((font font) (char character))
  (declare (ignore font char))
  (error "Browser text is drawn by the renderer text callback."))

(fn (uncached-wrap-text (vector string)) ((font font) (text string) width)
  "Split TEXT into lines at newlines and spaces; NIL width preserves explicit breaks."
  (lui.text:wrap-lines text width
                       (lambda (text start end)
                         (text-width font (subseq text start end)))))


(fn (wrap-text (vector string)) ((font font) (text string) (width (or null
                                                                      real)))
  (let ((cache (font-wrapped font))
        (key (list (font-size font) text width)))
    (cond ((gethash key cache))
          (t
           (when (>= (hash-table-count cache) 512) (clrhash cache))
           (setf (gethash key cache)
                 (uncached-wrap-text font text width))))))
