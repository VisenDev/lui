(defpackage #:lui.font
  (:use #:cl #:lui.fn)
  (:export #:font #:open-font #:close-font #:font-size #:font-loader
           #:text-width #:line-height #:baseline #:wrap-text #:glyph-polygons
           #:*font-path* #:*font-paths* #:*font-directories*
           #:*font-names* #:font-face #:font-css))

(in-package #:lui.font)

(defvar *font-path* nil)
(defvar *font-paths* nil)
(defvar *font-directories* nil)
(defvar *font-names* nil)

(defstruct font
  "A browser font face with a Canvas context for measuring text."
  loader
  owner
  (faces (make-array 4 :initial-element nil))
  (size 16)
  (family :sans-serif)
  (weight :normal)
  css-value css-size
  (metrics (make-hash-table :test 'equal))
  (wrapped (make-hash-table :test 'equal)))

(fn (open-font font) (&optional path ((size real) 16))
  "Create a browser font at SIZE; PATH is accepted for API compatibility."
  (declare (ignore path))
  (let ((canvas (#j:document:createElement #j"canvas")))
    (make-font :loader ((jscl/ffi:oget canvas "getContext") #j"2d")
               :size size)))

(fn (close-font null) ((font font))
  (fill (font-faces font) nil)
  (clrhash (font-metrics font))
  (clrhash (font-wrapped font))
  (setf (font-loader font) nil))

(fn (font-face font) ((font font) (family symbol) (weight symbol))
  (let* ((owner (or (font-owner font) font))
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
                  (jscl/ffi:clstring (#j:String (font-size font)))
                  (if (eq (font-family font) :monospace)
                      "monospace" "sans-serif"))))
  (font-css-value font))

(fn (measure-text t) ((font font) (text string))
  (let* ((css (font-css font))
         (cache (font-metrics font))
         (key (list (font-size font) text)))
    (or (gethash key cache)
        (let ((context (font-loader font)))
          (when (>= (hash-table-count cache) 2048) (clrhash cache))
          (setf (jscl/ffi:oget context "font") (jscl/ffi:jsstring css))
          (setf (gethash key cache)
                ((jscl/ffi:oget context "measureText")
                 (jscl/ffi:jsstring text)))))))

(fn (text-width real) ((font font) (text string))
  (jscl/ffi:oget (measure-text font text) "width"))

(fn (baseline real) ((font font))
  (let ((ascent (jscl/ffi:oget (measure-text font "Mg")
                                "fontBoundingBoxAscent")))
    (if (and (numberp ascent) (plusp ascent))
        ascent (* (font-size font) 0.8))))

(fn (line-height real) ((font font))
  (let* ((metrics (measure-text font "Mg"))
         (ascent (jscl/ffi:oget metrics "fontBoundingBoxAscent"))
         (descent (jscl/ffi:oget metrics "fontBoundingBoxDescent")))
    (if (and (numberp ascent) (numberp descent)
             (plusp (+ ascent descent)))
        (max (* (font-size font) 1.2) (+ ascent descent))
        (* (font-size font) 1.2))))

(fn (glyph-polygons nil) ((font font) (char character))
  (declare (ignore font char))
  (error "Browser text is drawn by the renderer text callback."))

(fn (uncached-wrap-text (vector string)) ((font font) (text string) width)
  "Split TEXT into lines at newlines and spaces; NIL width preserves explicit breaks."
  (lui.text:wrap-lines text width
                      (lambda (text start end)
                        (text-width font (subseq text start end)))))


(fn (wrap-text (vector string)) ((font font) (text string) (width (or null real)))
  (let* ((cache (font-wrapped font))
         (key (list (font-size font) text width)))
    (or (gethash key cache)
        (progn
          (when (>= (hash-table-count cache) 512) (clrhash cache))
          (setf (gethash key cache) (uncached-wrap-text font text width))))))
