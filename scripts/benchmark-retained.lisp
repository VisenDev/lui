(defpackage #:%lui.benchmark-retained (:use #:cl))
(in-package #:%lui.benchmark-retained)
#-sbcl (error "The retained allocation benchmark requires SBCL.")
(load "scripts/setup.lisp")
(asdf:load-system "lui/retained")
(load "tests/support.lisp")

(defparameter *frames* (parse-integer (or (uiop:getenv "BENCH_FRAMES") "2000")))
(defparameter *warmup* (parse-integer (or (uiop:getenv "WARMUP") "300")))
(defparameter *samples* (parse-integer (or (uiop:getenv "BENCH_SAMPLES") "7")))
(defparameter *width* 120)
(defparameter *height* 2000)
(defparameter *grow* (lui:grow))
(defparameter *slider-width* (lui:fixed 20))
(defparameter *modes*
  (make-array 3 :element-type 'keyword
                :initial-contents '(:immediate :retained-object :retained-id)))
(assert (and (plusp *frames*) (plusp *samples*) (>= *warmup* 0)))

(defstruct fixture
  (kind :labels :type keyword)
  (mode :immediate :type keyword)
  (context (%lui.tests.support:make-test-context) :type %lui.frame:context)
  (texts (make-array 0 :element-type 'string) :type (vector string))
  (leaves (make-array 0 :element-type 'lui.retained:node)
          :type (vector lui.retained:node))
  (root nil :type (or null lui.retained:node))
  (index 0 :type fixnum)
  (calls 0 :type fixnum))

(defun key-for (mode key)
  "Use the same explicit key data, or default retained object identity."
  (when (eq mode :retained-id) key))

(defun make-row (mode index text callback)
  "Build one retained row matching the immediate declarations in DRAW-ROWS."
  (lui.retained:make-row
   :id (key-for mode index) :gap 1 :width *grow*
   :children
   (lui.retained:nodes
    (lui.retained:make-label :id (key-for mode :label) :text text :padding 1)
    (lui.retained:make-text-field
     :id (key-for mode :editor) :default-value "Editable"
     :padding 1 :width *grow* :on-change callback)
    (lui.retained:make-checkbox
     :id (key-for mode :check) :text "Ready" :on-change callback)
    (lui.retained:make-button
     :id (key-for mode :button) :text "Run" :on-activate callback)
    (lui.retained:make-slider
     :id (key-for mode :slider) :default-value 50
     :minimum 0 :maximum 100 :step 1 :width *slider-width* :on-change callback))))

(defun build-fixture (kind mode)
  "Build model, sizing and retained data outside the measured frame loop."
  (let* ((count (if (eq kind :nested) 25 100))
         (fixture (make-fixture :kind kind :mode mode))
         (texts (make-array count :element-type 'string :initial-element ""))
         (nodes (make-array count :element-type 'lui.retained:node
                            :initial-element (lui.retained:make-spacer)))
         (callback (lambda (&optional value)
                     (declare (ignore value)) (incf (fixture-calls fixture)))))
    (dotimes (index count)
      (setf (aref texts index) (format nil "Item ~D" index)))
    (setf (fixture-texts fixture) texts)
    (unless (eq mode :immediate)
      (dotimes (index count)
        (setf (aref nodes index)
              (if (eq kind :nested)
                  (make-row mode index (aref texts index) callback)
                  (lui.retained:make-label
                   :id (key-for mode index) :text (aref texts index)
                   :padding 1 :font-weight :bold :foreground "#223344"))))
      (setf (fixture-leaves fixture) nodes
            (fixture-root fixture)
            (if (eq kind :nested)
                (lui.retained:make-panel
                 :id (key-for mode :root) :padding 2 :gap 1
                 :width *grow* :children nodes)
                (lui.retained:make-column
                 :id (key-for mode :root) :gap 1 :children nodes))))
    fixture))

(defun draw-labels (texts)
  "Declare styled labels with ordinary immediate-mode instance keys."
  (lui:column (:id :root :gap 1)
    (dotimes (index (length texts))
      (lui:label (aref texts index) :id index :padding 1
                 :font-weight :bold :foreground "#223344"))))

(defun draw-rows (fixture)
  "Declare the same controls, ownership, sizing and actions as MAKE-ROW."
  (let ((texts (fixture-texts fixture)))
    (lui:panel (:id :root :padding 2 :gap 1 :width *grow*)
      (dotimes (index (length texts))
        (lui:row (:id index :gap 1 :width *grow*)
          (lui:label (aref texts index) :id :label :padding 1)
          (multiple-value-bind (value changed)
              (lui:text-field :id :editor :default-value "Editable"
                              :padding 1 :width *grow*)
            (declare (ignore value))
            (when changed (incf (fixture-calls fixture))))
          (multiple-value-bind (value changed)
              (lui:checkbox "Ready" :id :check)
            (declare (ignore value))
            (when changed (incf (fixture-calls fixture))))
          (when (lui:button "Run" :id :button)
            (incf (fixture-calls fixture)))
          (multiple-value-bind (value changed)
              (lui:slider :id :slider :default-value 50
                          :minimum 0 :maximum 100 :step 1 :width *slider-width*)
            (declare (ignore value))
            (when changed (incf (fixture-calls fixture)))))))))

(defun frame (fixture)
  "Update one model slot if requested, then construct and solve one frame."
  (when (eq (fixture-kind fixture) :update)
    (let* ((index (incf (fixture-index fixture)))
           (slot (mod index 100))
           (text (if (evenp (floor index 100)) "Updated A" "Updated B")))
      (if (eq (fixture-mode fixture) :immediate)
          (setf (aref (fixture-texts fixture) slot) text)
          (setf (lui.retained:label-text
                 (aref (fixture-leaves fixture) slot)) text))))
  (let ((lui:*unit* 1))
    (lui:with-frame ((fixture-context fixture) *width* *height*)
      (lui:with-toolkit (:qt)
        (lui:with-palette (:default)
          (cond ((not (eq (fixture-mode fixture) :immediate))
                 (lui.retained:draw (fixture-root fixture)))
                ((eq (fixture-kind fixture) :nested) (draw-rows fixture))
                (t (draw-labels (fixture-texts fixture)))))))))

(defun box-data (box)
  "Collect geometry for untimed parity checks."
  (list (%lui.layout:box-x box) (%lui.layout:box-y box)
        (%lui.layout:box-width box) (%lui.layout:box-height box)))

(defun snapshot (fixture)
  "Compare all solved content and clips, excluding opaque identity shapes."
  (let ((result nil))
    (%lui.layout:walk-elements
     (%lui.frame:context-root (fixture-context fixture))
     (lambda (element)
       (let ((widget (%lui.layout:element-content element)))
         (push (list (box-data (%lui.layout:element-box element))
                     (box-data (%lui.layout:element-clip element))
                     (when (%lui.widgets:widget-p widget)
                       (list (%lui.widgets:widget-kind widget)
                             (%lui.widgets:widget-text widget)
                             (%lui.widgets:widget-value widget)))) result))))
    (nreverse result)))

(defconstant +timer-hz+
  #+unix 1000000000
  #-unix internal-time-units-per-second)

(defun ticks ()
  "Use a monotonic high-resolution clock where SBCL provides one."
  #+unix
  (multiple-value-bind (seconds nanos)
      (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ (* seconds +timer-hz+) nanos))
  #-unix (get-internal-real-time))

(defun sample (fixture)
  "Measure complete frames, including any GC triggered during the sample."
  (sb-ext:gc :full t)
  (let ((start (ticks))
        (bytes (sb-ext:get-bytes-consed))
        (gc-time sb-ext:*gc-run-time*))
    (dotimes (i *frames*) (frame fixture))
    (list (/ (* 1000d0 (- (ticks) start)) (* *frames* +timer-hz+))
          (/ (- (sb-ext:get-bytes-consed) bytes) (float *frames* 1d0))
          (/ (* 1000d0 (- sb-ext:*gc-run-time* gc-time))
             (* *frames* internal-time-units-per-second)))))

(defun median (values)
  "Return the median of an unordered sample list."
  (let* ((sorted (sort (copy-list values) #'<))
         (size (length sorted)))
    (/ (+ (nth (floor size 2) sorted)
          (nth (floor (1- size) 2) sorted)) 2)))

(defun benchmark-case (kind)
  "Verify parity, warm all modes, then measure in rotating order."
  (let ((fixtures (map '(vector fixture)
                       (lambda (mode) (build-fixture kind mode)) *modes*))
        (results (make-array 3 :element-type 'list :initial-element nil)))
    (loop :for fixture :across fixtures :do (frame fixture))
    (assert (every (lambda (fixture)
                     (equalp (snapshot (aref fixtures 0)) (snapshot fixture)))
                   (coerce fixtures 'list)))
    (format t "PARITY ~A matched content, values, bounds, clips (~D elements).~%"
            kind (length (snapshot (aref fixtures 0))))
    (loop :for fixture :across fixtures
          :do (dotimes (i *warmup*) (frame fixture)))
    (dotimes (repeat *samples*)
      ;; Rotate order to distribute thermal/GC/order effects across variants.
      (dotimes (offset 3)
        (let* ((index (mod (+ repeat offset) 3))
               (fixture (aref fixtures index))
               (sample (sample fixture)))
          (push sample (aref results index))
          (format t "SAMPLE ~A ~A ~D ms/frame=~,6F bytes/frame=~,1F gc-cpu-ms/frame=~,6F~%"
                  kind (fixture-mode fixture) repeat
                  (first sample) (second sample) (third sample)))))
    (dotimes (index 3)
      (let* ((samples (aref results index))
             (times (mapcar #'first samples)))
        (format t "RESULT ~A ~A median-ms=~,6F range-ms=~,6F..~,6F median-bytes=~,1F median-gc-cpu-ms=~,6F~%"
                kind (aref *modes* index) (median times)
                (reduce #'min times) (reduce #'max times)
                (median (mapcar #'second samples))
                (median (mapcar #'third samples)))))
    (assert (every (lambda (fixture)
                     (equalp (snapshot (aref fixtures 0)) (snapshot fixture)))
                   (coerce fixtures 'list)))))

(defun run-benchmarks ()
  "Report reproducible core timings and process-wide Lisp allocation counts."
  (format t "ENV ~A ~A ~A ~A commit=~A source=~A~%"
          (lisp-implementation-type) (lisp-implementation-version)
          (machine-type) (machine-version)
          (string-trim '(#\Newline)
                       (uiop:run-program '("git" "rev-parse" "HEAD")
                                         :output :string))
          (string-trim '(#\Newline)
                       (uiop:run-program
                        '("git" "hash-object" "src/17-retained.lisp")
                        :output :string)))
  (format t "CONFIG Qt/Default core-only deterministic text metrics, ~Dx~D, frames=~D warmup=~D samples=~D timer_hz=~D~%"
          *width* *height* *frames* *warmup* *samples* +timer-hz+)
  (format t "No painting, presentation, input events or pacing. Stored trees, text data and sizing objects built outside timing for both APIs. SBCL process-wide allocation; not retained heap/foreign memory. GC during samples included; full GC before each sample excluded.~%")
  (dolist (kind '(:labels :nested :update)) (benchmark-case kind)))

(unless (uiop:getenv "LUI_RETAINED_BENCH_LIBRARY_ONLY") (run-benchmarks))
