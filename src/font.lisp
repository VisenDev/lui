(defpackage #:lui.font
  (:use #:cl #:lui.fn)
  (:export #:font #:open-font #:close-font #:font-size #:font-loader
           #:text-width #:line-height #:baseline #:wrap-text #:glyph-polygons
           #:*font-path* #:*font-paths* #:font-face))

(in-package #:lui.font)

(defvar *font-path* nil "Override the default TrueType font pathname.")

(defvar *font-paths* nil
  "Optional ((family weight) . pathname) overrides for additional font faces.")

(defstruct font
  loader
  owner
  (faces (make-array 4 :initial-element nil) :type simple-vector)
  (size 16 :type real)
  (cache (make-hash-table) :type hash-table))

(fn default-font ()
  (or *font-path*
      (find-if #'probe-file
               '("/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
                 "C:/Windows/Fonts/arial.ttf"
                 "/System/Library/Fonts/Supplemental/Arial.ttf"))
      (error "Set LUI.FONT:*FONT-PATH* to a TrueType font.")))

(fn (open-font font) (&optional path ((size real) 16))
  (make-font :loader (zpb-ttf:open-font-loader (or path (default-font)))
             :size size))

(fn close-font ((font font))
  (dotimes (index 4)
    (let ((face (aref (font-faces font) index)))
      (when face (close-font face))))
  (fill (font-faces font) nil)
  (when (font-loader font)
    (zpb-ttf:close-font-loader (font-loader font))
    (setf (font-loader font) nil))
  (clrhash (font-cache font)))

(fn (font-face font) ((font font) (family symbol) (weight symbol))
  (let* ((owner (or (font-owner font) font))
         (index (+ (ecase family (:sans-serif 0) (:monospace 2))
                   (ecase weight (:normal 0) (:bold 1)))))
    (if (zerop index) owner
        (or (aref (font-faces owner) index)
            (let* ((key (list family weight))
                   (names
                     (ecase index
                       (1 '("DejaVuSans-Bold.ttf" "arialbd.ttf"
                            "Arial Bold.ttf"))
                       (2 '("DejaVuSansMono.ttf" "cour.ttf"
                            "Courier New.ttf"))
                       (3 '("DejaVuSansMono-Bold.ttf" "courbd.ttf"
                            "Courier New Bold.ttf"))))
                   (path
                     (or (cdr (assoc key *font-paths* :test #'equal))
                         (when (> index 1)
                           (let ((name (if (= index 2)
                                           "LiberationMono-Regular.ttf"
                                           "LiberationMono-Bold.ttf")))
                             (find-if #'probe-file
                                      (mapcar
                                       (lambda (directory)
                                         (concatenate 'string directory name))
                                       '("/usr/share/fonts/liberation-mono-fonts/"
                                         "/usr/share/fonts/truetype/liberation2/"
                                         "/usr/share/fonts/truetype/liberation/")))))
                         (find-if
                          #'probe-file
                          (list
                           (concatenate 'string
                            "/usr/share/fonts/dejavu-sans-mono-fonts/"
                            (first names))
                           (concatenate 'string
                            "/usr/share/fonts/dejavu-sans-fonts/"
                            (first names))
                           (concatenate 'string
                            "/usr/share/fonts/truetype/dejavu/" (first names))
                           (concatenate 'string "C:/Windows/Fonts/"
                                        (second names))
                           (concatenate 'string
                            "/System/Library/Fonts/Supplemental/"
                            (third names))))
                         (error "Set LUI.FONT:*FONT-PATHS* for ~S." key)))
                   (face (open-font path (font-size owner))))
              (setf (font-owner face) owner
                    (aref (font-faces owner) index) face))))))

(fn (scale-font real) ((font font))
  (/ (font-size font) (zpb-ttf:units/em (font-loader font))))

(fn (baseline real) ((font font))
  (* (scale-font font) (zpb-ttf:ascender (font-loader font))))

(fn (line-height real) ((font font))
  (* (scale-font font)
     (+ (zpb-ttf:ascender (font-loader font))
        (- (zpb-ttf:descender (font-loader font)))
        (zpb-ttf:line-gap (font-loader font)))))

(fn (text-width real) ((font font) (text string))
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
