(defpackage #:%lui.benchmark (:use #:cl))
(in-package #:%lui.benchmark)

(load "scripts/setup.lisp")

(defparameter *platform*
  (string-downcase (or (uiop:getenv "PLATFORM") "core")))
(unless (member *platform*
                '("core" "terminal" "gl" "x11" "wayland" "win32" "cocoa")
                :test #'string=)
  (error "Unsupported Lisp benchmark platform ~S." *platform*))
(asdf:load-system (if (string= *platform* "core") "lui/core"
                     (concatenate 'string "lui/" *platform*)))
(asdf:load-system "lui/demo")

(defparameter *gallery* (%lui.example.demo:make-gallery))

(defparameter *cases*
  (loop :for toolkit :in %lui.example.demo::*toolkits*
        :append (loop :for (page title) :in %lui.example.demo::*pages*
                      :append
                      (if (eq page :seven)
                          (loop :for (task label)
                                  :in %lui.example.seven::*tasks*
                                :collect (list toolkit page task))
                          (list (list toolkit page))))))
(let ((name (uiop:getenvp "BENCH_CASE")))
  (when name
    (setf *cases*
          (remove-if-not (lambda (case)
                           (string-equal name (format nil "~{~A~^/~}" case)))
                         *cases*))
    (unless *cases* (error "Unknown BENCH_CASE ~S." name))))

(defparameter *frames*
  (parse-integer (or (uiop:getenv "BENCH_FRAMES") "240")))
(defparameter *warmup* (parse-integer (or (uiop:getenv "WARMUP") "30")))
(defparameter *samples* (make-hash-table :test 'equal))
(defparameter *allocations* (make-hash-table :test 'equal))
(defstruct allocation bytes gc-time)
(defparameter *width*
  (parse-integer (or (uiop:getenv "BENCH_WIDTH")
                     (if (member *platform* '("core" "terminal")
                                 :test #'string=)
                         "100" "720"))))
(defparameter *height*
  (parse-integer (or (uiop:getenv "BENCH_HEIGHT")
                     (if (member *platform* '("core" "terminal")
                                 :test #'string=)
                         "40" "520"))))
(assert (and (plusp *width*) (plusp *height*)))

(defun counters ()
  #+sbcl (values (sb-ext:get-bytes-consed) sb-ext:*gc-run-time*)
  #-sbcl (values nil nil))

(assert (>= *frames* (length *cases*)) ()
        "BENCH_FRAMES must be at least ~D to cover every case."
        (length *cases*))
(assert (>= *warmup* 0))

(defconstant +timer-hz+
  #+(and sbcl unix) 1000000000
  #-(and sbcl unix) internal-time-units-per-second)

(defun ticks ()
  ;; SBCL's portable real-time clock can have millisecond resolution. Use its
  ;; monotonic nanosecond clock when available so microbenchmarks stay useful.
  #+(and sbcl unix)
  (multiple-value-bind (seconds nanos)
      (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ (* seconds +timer-hz+) nanos))
  #-(and sbcl unix)
  (get-internal-real-time))

(defun call (package name &rest arguments)
  (apply #'uiop:symbol-call package name arguments))

(defun select-case (index)
  (let ((case (nth (if (< index *warmup*)
                       (mod index (length *cases*))
                       (floor (* (- index *warmup*) (length *cases*))
                              *frames*))
                   *cases*)))
    (setf (%lui.example.demo::gallery-toolkit *gallery*) (first case)
          (%lui.example.demo::gallery-page *gallery*) (second case))
    (when (third case)
      (setf (%lui.example.seven:state-task
             (%lui.example.demo::gallery-seven *gallery*))
            (third case)))
    case))

(defun sample-since (case duration bytes gc-time)
  ;; Read counters before recording samples, so bookkeeping stays outside.
  (multiple-value-bind (end-bytes end-gc-time) (counters)
    (push duration (gethash case *samples*))
    (when bytes
      (push (make-allocation :bytes (- end-bytes bytes)
                             :gc-time (- end-gc-time gc-time))
            (gethash case *allocations*)))))

(defun benchmark-window ()
  ;; Callback intervals include presentation and event pumping/pacing.
  (let ((index 0) (previous nil) (started 0) (bytes nil) (gc-time nil))
    (catch 'complete
      (lui:run
       (lambda ()
         (let ((now (ticks)))
           (when previous
             (sample-since previous (- now started) bytes gc-time))
           (when (= index (+ *warmup* *frames*)) (throw 'complete nil))
           (let ((case (select-case index)))
             (setf previous (when (>= index *warmup*) case)
                   started now))
           (incf index)
           ;; Case selection and previous-sample storage are excluded.
           (multiple-value-setq (bytes gc-time) (counters))
           (%lui.example.demo:draw *gallery*)))
       :backend (intern (string-upcase *platform*) :keyword)
       :min-fps 240 :max-fps 240
       :title "LUI benchmark" :width *width* :height *height*))))

(defun benchmark-loop (frame)
  (dotimes (index (+ *warmup* *frames*))
    (let* ((case (select-case index))
           (started (ticks)))
      (multiple-value-bind (bytes gc-time) (counters)
        (funcall frame)
        (when (>= index *warmup*)
          (sample-since case (- (ticks) started) bytes gc-time))))))

(%lui.fn:fn benchmark-core ()
  (let ((context
          (%lui.frame:make-context
           :text-mode-p t
           :measure
           (lambda (widget width)
             (let ((lines (%lui.text:wrap-lines
                           (%lui.widgets:widget-terminal-text widget) width
                           (lambda (text start end)
                             (declare (ignore text)) (- end start)))))
               (values (max (if (eq (%lui.widgets:widget-kind widget) :slider)
                      12 0)
                            (loop for line across lines maximize (length
                        line)))
                       (length lines))))))
        (lui:*unit* 1))
    (benchmark-loop
     (lambda ()
       (%lui.frame:with-frame (context *width* *height*)
         (%lui.example.demo:draw *gallery*))))))

(defun benchmark-terminal ()
  (let ((context (call :lui.terminal :make-terminal-context)) (lui:*unit* 1))
    (benchmark-loop
     (lambda ()
       (%lui.frame:with-frame (context *width* *height*)
         (%lui.example.demo:draw *gallery*))
       (call :lui.terminal :render-terminal context)))))

(defun benchmark-gl ()
  (let* ((font (call :lui.font :open-font))
         (gpu nil) (lui:*unit* 8))
    (unwind-protect
         (progn
           (setf gpu (call :%lui.gl :open-gpu nil nil font *width* *height*))
           (let* ((renderer (call :%lui.gl :gpu-renderer gpu))
                  (context
                    (%lui.frame:make-context
                     :measure (lambda (widget width)
                                (call :lui.draw :measure-widget
                                      renderer widget width))))
                  ;; Compile CFFI only on the GL path; CORE stays dependency-free.
                  (finish (compile nil
                            `(lambda ()
                               (,(find-symbol "FOREIGN-FUNCALL" "CFFI")
                                "glFinish" :void)))))
             (benchmark-loop
              (lambda ()
                (%lui.frame:with-frame (context *width* *height*)
                  (%lui.example.demo:draw *gallery*))
                (call :%lui.gl :begin-gpu-frame gpu)
                (call :lui.draw :paint-frame renderer context)
                (call :%lui.gl :present-gpu gpu)
                (funcall finish)))))
      (when gpu (call :%lui.gl :close-gpu gpu))
      (call :lui.font :close-font font))))

(defun percentile (sorted fraction)
  (nth (max 0 (1- (ceiling (* fraction (length sorted))))) sorted))

(defun report-row (toolkit page samples)
  (let* ((sorted (sort (copy-list samples) #'<))
         (count (length sorted))
         (elapsed (/ (reduce #'+ sorted) +timer-hz+))
         (ms (/ 1000.0d0 +timer-hz+)))
    (assert (plusp count) () "No samples for ~A/~A." toolkit page)
    (when (string= *platform* "cocoa")
      (format t "BUDGET toolkit=~(~A~) page=~(~A~) target_fps=170 missed=~D frames=~D~%"
              toolkit page (count-if (lambda (ticks)
                                       (> (* 170 ticks) +timer-hz+))
                                     samples)
              count))
    (format t "RESULT toolkit=~(~A~) page=~(~A~) frames=~D elapsed_s=~,6F fps=~A mean_ms=~,3F p50_ms=~,3F p95_ms=~,3F max_ms=~,3F~%"
            toolkit page count elapsed
            (if (plusp elapsed) (format nil "~,2F" (/ count elapsed))
                "unresolved")
            (/ (* elapsed 1000) count)
            (* ms (percentile sorted 0.5d0))
            (* ms (percentile sorted 0.95d0)) (* ms (car (last sorted))))))

(defun report-allocation (toolkit page records)
  (if records
      (let* ((bytes (sort (mapcar #'allocation-bytes records) #'<))
             (total (reduce #'+ bytes)))
        (format t "ALLOC toolkit=~(~A~) page=~(~A~) frames=~D bytes_total=~D bytes_mean=~,2F bytes_p95=~D gc_count=unsupported gc_cpu_ms=~,3F~%"
                toolkit page (length bytes) total (/ total (length bytes))
                (percentile bytes 0.95d0)
                (* (/ 1000.0d0 internal-time-units-per-second)
                   (reduce #'+ records :key #'allocation-gc-time))))
      (format t "ALLOC toolkit=~(~A~) page=~(~A~) status=unsupported~%"
              toolkit page)))

(defun run-benchmarks ()
  (let ((mode (cond ((string= *platform* "core")
                     "layout only with character-count text metrics")
                    ((string= *platform* "terminal")
                     "layout+terminal-render microbenchmark")
                    ((string= *platform* "gl")
                     "offscreen pipeline + glFinish")
                    (t "paced window loop; not raw GPU speed"))))
    (format t "BENCH backend=~A mode=~S frames=~D warmup=~D requested_size=~A timer_hz=~D~%"
            *platform* mode *frames* *warmup*
            (format nil "~Dx~D" *width* *height*)
            +timer-hz+)
    (format t "ALLOCATION counters=~A scope=process gc_time=cpu sample_storage=excluded~%"
            #+sbcl "SBCL" #-sbcl "unsupported")
    (cond ((string= *platform* "core") (benchmark-core))
          ((string= *platform* "terminal") (benchmark-terminal))
          ((string= *platform* "gl") (benchmark-gl))
          (t (benchmark-window)))
    (assert (= *frames*
               (loop :for values :being :the :hash-values :of *samples*
                     :sum (length values)))
            () "Benchmark ended before every measured frame completed.")
    #+sbcl
    (assert (= *frames*
               (loop :for values :being :the :hash-values :of *allocations*
                     :sum (length values))))
    (dolist (case *cases*)
      (let ((page (if (third case) (format nil "seven/~A" (third case))
                      (second case))))
        (report-row (first case) page (gethash case *samples*))
        (report-allocation (first case) page (gethash case *allocations*))))
    (report-row :all :all
                (loop :for case :in *cases*
                      :append (gethash case *samples*)))
    (report-allocation :all :all
                      (loop :for case :in *cases*
                            :append (gethash case *allocations*)))))

(unless (uiop:getenv "LUI_BENCH_LIBRARY_ONLY") (run-benchmarks))
