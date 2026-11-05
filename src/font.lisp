(defpackage #:lui.font
  (:use #:cl #:lui.fn)
  (:export #:font #:open-font #:close-font #:font-size #:font-loader
           #:text-width #:line-height #:baseline #:wrap-text #:glyph-polygons
           #:*font-path*))

(in-package #:lui.font)

(defvar *font-path* nil "Override the default TrueType font pathname.")

(defstruct font
  loader
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
  (zpb-ttf:close-font-loader (font-loader font)))

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
