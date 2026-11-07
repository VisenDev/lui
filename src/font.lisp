(defpackage #:lui.font
  (:use #:cl #:lui.fn)
  (:export #:font #:open-font #:close-font #:font-size #:font-loader
           #:text-width #:line-height #:baseline #:wrap-text #:glyph-polygons
           #:*font-path* #:*font-paths* #:*font-directories*
           #:*font-names* #:font-face))

(in-package #:lui.font)

(defvar *font-path* nil "Override the default TrueType font pathname.")

(defvar *font-paths* nil
  "Optional ((family weight) . pathname) overrides for additional font faces.")

(defstruct font
  "An open TrueType face, its pixel size, and cached glyph outlines."
  loader
  owner
  (faces (make-array 4 :initial-element nil) :type simple-vector)
  (size 16 :type real)
  (cache (make-hash-table) :type hash-table))

(defvar *font-directories*
  '("/usr/share/fonts/dejavu-sans-fonts/"
    "/usr/share/fonts/dejavu-sans-mono-fonts/"
    "/usr/share/fonts/truetype/dejavu/"
    "/usr/share/fonts/liberation-sans-fonts/"
    "/usr/share/fonts/liberation-mono-fonts/"
    "/usr/share/fonts/truetype/liberation2/"
    "/usr/share/fonts/truetype/liberation/"
    "C:/Windows/Fonts/" "/System/Library/Fonts/Supplemental/")
  "Ordered font directories, as directory pathnames or namestrings.")

(defvar *font-names*
  '(((:sans-serif :normal) "DejaVuSans.ttf" "arial.ttf" "Arial.ttf"
     "LiberationSans-Regular.ttf")
    ((:sans-serif :bold) "DejaVuSans-Bold.ttf" "arialbd.ttf" "Arial Bold.ttf"
     "LiberationSans-Bold.ttf")
    ((:monospace :normal) "LiberationMono-Regular.ttf" "DejaVuSansMono.ttf"
     "cour.ttf" "Courier New.ttf")
    ((:monospace :bold) "LiberationMono-Bold.ttf" "DejaVuSansMono-Bold.ttf"
     "courbd.ttf" "Courier New Bold.ttf"))
  "Candidate filenames in preference order for each (family weight).")

(fn resolve-face ((family symbol) (weight symbol))
  (let ((key (list family weight)))
    (or (cdr (assoc key *font-paths* :test #'equal))
        (loop :with extra := (uiop:getenvp "LUI_FONT_DIR")
              :with dirs := (if extra
                                (cons (uiop:ensure-directory-pathname extra)
                                      *font-directories*)
                                *font-directories*)
              :for name :in (cdr (assoc key *font-names* :test #'equal))
              :thereis (loop :for dir :in dirs
                             :thereis (probe-file
                                       (merge-pathnames name dir))))
        (error "No TrueType font for ~S. Set LUI.FONT:*FONT-PATHS*." key))))

(fn default-font ()
  (or *font-path* (uiop:getenvp "LUI_FONT")
      (resolve-face :sans-serif :normal)))

(fn (open-font font) (&optional path ((size real) 16))
  "Open a TrueType file at SIZE; a missing PATH uses the configured base face."
  (make-font :loader (zpb-ttf:open-font-loader (or path (default-font)))
             :size size))

(fn close-font ((font font))
  "Release the loader, cached faces, and glyph outlines owned by FONT."
  (dotimes (index 4)
    (let ((face (aref (font-faces font) index)))
      (when face (close-font face))))
  (fill (font-faces font) nil)
  (when (font-loader font)
    (zpb-ttf:close-font-loader (font-loader font))
    (setf (font-loader font) nil))
  (clrhash (font-cache font)))

(fn (font-face font) ((font font) (family symbol) (weight symbol))
  "Resolve a sans-serif or monospace face at normal or bold weight; reuse it until the owner is closed."
  (let* ((owner (or (font-owner font) font))
         (index (+ (ecase family (:sans-serif 0) (:monospace 2))
                   (ecase weight (:normal 0) (:bold 1)))))
    (if (zerop index) owner
        (or (aref (font-faces owner) index)
            (let* ((path (resolve-face family weight))
                   (face (open-font path (font-size owner))))
              (setf (font-owner face) owner
                    (aref (font-faces owner) index) face))))))

(fn (scale-font real) ((font font))
  (/ (font-size font) (zpb-ttf:units/em (font-loader font))))

(fn (baseline real) ((font font))
  "Return the ascent from the top of a line to its baseline."
  (* (scale-font font) (zpb-ttf:ascender (font-loader font))))

(fn (line-height real) ((font font))
  "Return baseline-to-baseline spacing including the font’s line gap."
  (* (scale-font font)
     (+ (zpb-ttf:ascender (font-loader font))
        (- (zpb-ttf:descender (font-loader font)))
        (zpb-ttf:line-gap (font-loader font)))))

(fn (text-width real) ((font font) (text string))
  "Measure a string using glyph advances and pair kerning at the current size."
  (let ((previous nil)
        (width 0))
    (loop :for char :across text
          :do (incf width
                    (+ (zpb-ttf:advance-width
                        (zpb-ttf:find-glyph char (font-loader font)))
                       (if previous
                           (zpb-ttf:kerning-offset
                            previous char (font-loader font))
                           0)))
              (setf previous char))
    (* (scale-font font) width)))

(fn (wrap-text list) ((font font) (text string) width)
  "Split TEXT into lines at newlines and spaces; NIL width preserves explicit breaks."
  (lui.text:wrap-lines text width
                      (lambda (text start end)
                        (text-width font (subseq text start end)))))

(fn (glyph-polygons list) ((font font) (char character))
  "Flatten TrueType curves into geometric contours, never pixels. Cache in font units."
  (or (gethash char (font-cache font))
      (setf (gethash char (font-cache font))
            (let ((polygons nil))
              (zpb-ttf:do-contours
                  (contour (zpb-ttf:find-glyph char (font-loader font)))
                (let ((points nil))
                  (zpb-ttf:do-contour-segments (p0 p1 p2) contour
                    (if p1
                        (loop :for i :from 1 :to 12
                              :for u := (/ i 12.0f0)
                              :for v := (- 1 u)
                              :do (push
                                   (cons
                                    (+ (* v v (zpb-ttf:x p0))
                                       (* 2 u v (zpb-ttf:x p1))
                                       (* u u (zpb-ttf:x p2)))
                                    (+ (* v v (zpb-ttf:y p0))
                                       (* 2 u v (zpb-ttf:y p1))
                                       (* u u (zpb-ttf:y p2))))
                                   points))
                        (push (cons (zpb-ttf:x p2) (zpb-ttf:y p2))
                              points)))
                  (when points (push (nreverse points) polygons))))
              (nreverse polygons)))))
