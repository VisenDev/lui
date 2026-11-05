(defpackage #:lui.benchmark (:use #:cl))
(in-package #:lui.benchmark)

(load "scripts/setup.lisp")

(defparameter *platform*
  (string-downcase (or (uiop:getenv "PLATFORM") "core")))
(unless (member *platform*
                '("core" "terminal" "gl" "x11" "wayland" "win32" "cocoa")
                :test #'string=)
  (error "Unsupported Lisp benchmark platform ~S." *platform*))
(asdf:load-system (if (string= *platform* "core") "lui"
                     (concatenate 'string "lui/" *platform*)))
(load "examples/demo.lisp")

(defparameter *cases*
  (loop :for toolkit :in '(:glass :motif)
        :append (loop :for (page title) :in lui.example::*pages*
                      :collect (list toolkit page))))
(defparameter *frames*
  (parse-integer (or (uiop:getenv "BENCH_FRAMES") "240")))
(defparameter *warmup* (parse-integer (or (uiop:getenv "WARMUP") "30")))
(defparameter *samples* (make-hash-table :test 'equal))
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
    (setf lui.example::*toolkit* (first case)
          lui.example::*page* (second case))
    case))

(defun sample (case ticks)
  (push ticks (gethash case *samples*)))

(defun benchmark-window ()
  ;; Consecutive callback entries enclose drawing, layout, rendering, swap,
  ;; and backend event pumping/pacing. The final interval is observed before
  ;; throwing out of RUN, whose cleanup closes only this benchmark's window.
  (let ((index 0) (previous nil) (started 0))
    (catch 'complete
      (lui:run
       (lambda ()
         (let ((now (ticks)))
           (when previous (sample previous (- now started)))
           (when (= index (+ *warmup* *frames*)) (throw 'complete nil))
           (let ((case (select-case index)))
             (setf previous (when (>= index *warmup*) case)
                   started now))
           (incf index)
           (lui.example:draw)))
       :backend (intern (string-upcase *platform*) :keyword)
       :title "LUI benchmark" :width 720 :height 520))))

(defun benchmark-loop (frame)
  (dotimes (index (+ *warmup* *frames*))
    (let* ((case (select-case index))
           (started (ticks)))
      (funcall frame)
      (when (>= index *warmup*)
        (sample case (- (ticks) started))))))

(defun benchmark-terminal ()
  (let ((context (lui.terminal:make-terminal-context)) (lui:*unit* 1))
    (benchmark-loop
     (lambda ()
       (lui.frame:with-frame (context 100 40) (lui.example:draw))
       (lui.terminal:render-terminal context)))))

(defun benchmark-gl ()
  (let* ((font (call :lui.font :open-font))
         (gpu nil) (lui:*unit* 8))
    (unwind-protect
         (progn
           (setf gpu (call :lui.gl :open-gpu nil nil font 720 520))
           (let* ((renderer (call :lui.gl :gpu-renderer gpu))
                  (context
                    (lui.frame:make-context
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
                (lui.frame:with-frame (context 720 520) (lui.example:draw))
                (call :lui.gl :begin-gpu-frame gpu)
                (call :lui.draw :paint-frame renderer context)
                (call :lui.gl :present-gpu gpu)
                (funcall finish)))))
      (when gpu (call :lui.gl :close-gpu gpu))
      (call :lui.font :close-font font))))

(defun percentile (sorted fraction)
  (nth (max 0 (1- (ceiling (* fraction (length sorted))))) sorted))

(defun report-row (toolkit page samples)
  (let* ((sorted (sort (copy-list samples) #'<))
         (count (length sorted))
         (elapsed (/ (reduce #'+ sorted) +timer-hz+))
         (ms (/ 1000.0d0 +timer-hz+)))
    (assert (plusp count) () "No samples for ~A/~A." toolkit page)
    (format t "RESULT toolkit=~(~A~) page=~(~A~) frames=~D elapsed_s=~,6F fps=~A mean_ms=~,3F p50_ms=~,3F p95_ms=~,3F max_ms=~,3F~%"
            toolkit page count elapsed
            (if (plusp elapsed) (format nil "~,2F" (/ count elapsed))
                "unresolved")
            (/ (* elapsed 1000) count)
            (* ms (percentile sorted 0.5d0))
            (* ms (percentile sorted 0.95d0)) (* ms (car (last sorted))))))

(let ((mode (cond ((member *platform* '("core" "terminal") :test #'string=)
                   "layout+terminal-render microbenchmark")
                  ((string= *platform* "gl") "offscreen pipeline + glFinish")
                  (t "paced window loop; not raw GPU speed"))))
  (format t "BENCH backend=~A mode=~S frames=~D warmup=~D requested_size=~A timer_hz=~D~%"
          *platform* mode *frames* *warmup*
          (if (member *platform* '("core" "terminal") :test #'string=)
              "100x40" "720x520")
          +timer-hz+)
  (cond ((member *platform* '("core" "terminal") :test #'string=)
         (benchmark-terminal))
        ((string= *platform* "gl") (benchmark-gl))
        (t (benchmark-window)))
  (assert (= *frames* (loop :for values :being :the :hash-values :of *samples*
                           :sum (length values)))
          () "Benchmark ended before every measured frame completed.")
  (dolist (case *cases*)
    (report-row (first case) (second case) (gethash case *samples*)))
  (report-row :all :all
              (loop :for case :in *cases* :append (gethash case *samples*))))
