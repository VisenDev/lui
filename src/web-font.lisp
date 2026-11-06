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

(defstruct* font
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

(defun open-font (&optional path (size 16))
  "Create a browser font at SIZE; PATH is accepted for API compatibility."
  (declare (ignore path))
  (let ((canvas (#j:document:createElement #j"canvas")))
    (make-font :loader ((jscl/ffi:oget canvas "getContext") #j"2d")
               :size size)))

(defun close-font (font)
  (dotimes (index 4)
    (setf (aref (font-faces font) index) nil))
  (clrhash (font-metrics font))
  (clrhash (font-wrapped font))
  (setf (font-loader font) nil))

(defun font-face (font family weight)
  (let* ((owner (or (font-owner font) font))
         (index (+ (ecase family (:sans-serif 0) (:monospace 2))
                   (ecase weight (:normal 0) (:bold 1)))))
    (if (zerop index) owner
        (or (aref (font-faces owner) index)
            (setf (aref (font-faces owner) index)
                  (make-font :loader (font-loader owner) :owner owner
                             :size (font-size owner)
                             :family family :weight weight))))))

(defun font-css (font)
  "Return the CSS font shorthand used by measurement and drawing."
  (unless (eql (font-css-size font) (font-size font))
    (clrhash (font-metrics font))
    (clrhash (font-wrapped font))
    (setf (font-css-size font) (font-size font)
          (font-css-value font)
          (format nil "~A ~Apx ~A"
                  (if (eq (font-weight font) :bold) "bold" "normal")
                  (jscl/ffi:clstring (#j:String (font-size font)))
                  (if (eq (font-family font) :monospace)
                      "monospace" "sans-serif"))))
  (font-css-value font))

(defun measure-text (font text)
  (let* ((css (font-css font))
         (cache (font-metrics font)))
    (or (gethash text cache)
        (let ((context (font-loader font)))
          (when (>= (hash-table-count cache) 2048) (clrhash cache))
          (setf (jscl/ffi:oget context "font") (jscl/ffi:jsstring css))
          (setf (gethash text cache)
                ((jscl/ffi:oget context "measureText")
                 (jscl/ffi:jsstring text)))))))

(defun text-width (font text)
  (jscl/ffi:oget (measure-text font text) "width"))

(defun baseline (font)
  (let ((ascent (jscl/ffi:oget (measure-text font "Mg")
                                "fontBoundingBoxAscent")))
    (if (and (numberp ascent) (plusp ascent))
        ascent (* (font-size font) 0.8))))

(defun line-height (font)
  (let* ((metrics (measure-text font "Mg"))
         (ascent (jscl/ffi:oget metrics "fontBoundingBoxAscent"))
         (descent (jscl/ffi:oget metrics "fontBoundingBoxDescent")))
    (if (and (numberp ascent) (numberp descent)
             (plusp (+ ascent descent)))
        (max (* (font-size font) 1.2) (+ ascent descent))
        (* (font-size font) 1.2))))

(defun glyph-polygons (font char)
  (declare (ignore font char))
  (error "Browser text is drawn by the renderer text callback."))

(fn (uncached-wrap-text list) ((font font) (text string) width)
  "Split TEXT into lines at newlines and spaces; NIL width preserves only explicit breaks."
  (let ((start 0)
        (lines nil)
        (length (length text)))
    (loop
      (let ((end (or (position #\Newline text :start start) length)))
        (when width
          (loop :while (> (text-width font (subseq text start end)) width)
                :do (let ((break nil))
                      (loop :for space :=
                              (position #\Space text
                                        :start (1+ start) :end end)
                            :then (position #\Space text
                                            :start (1+ space) :end end)
                            :while space
                            :do (if (<= (text-width
                                         font (subseq text start space))
                                        width)
                                    (setf break space)
                                    (return)))
                      (unless break
                        (setf break
                              (position #\Space text
                                        :start (min end (1+ start))
                                        :end end)))
                      (unless break (return))
                      (push (subseq text start break) lines)
                      (setf start (1+ break)))))
        (push (subseq text start end) lines)
        (when (= end length) (return))
        (setf start (1+ end))))
    (nreverse lines)))


(defun wrap-text (font text width)
  ;; FONT-CSS invalidates all size-dependent entries before cache lookup.
  (font-css font)
  (let* ((cache (font-wrapped font))
         (key (list text width)))
    (or (gethash key cache)
        (progn
          (when (>= (hash-table-count cache) 512) (clrhash cache))
          (setf (gethash key cache) (uncached-wrap-text font text width))))))
