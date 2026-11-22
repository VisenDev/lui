;;; SBCL/Linux diagnostic benchmark. Normal Wayland presentation is retained.
;;; Active time is frame construction/layout + clear + painting + glFinish.
;;; Nested build/layout/GPU-finish columns are not additive to active time.
(require :sb-sprof)
(load "scripts/benchmark.lisp")
(defpackage #:%lui.benchmark-wayland (:use #:cl))
(in-package #:%lui.benchmark-wayland)
(assert (string= (uiop:getenv "PLATFORM") "wayland"))
(defparameter *names*
  #(:frame :build :layout :clear :paint-finish :present :gpu-finish))
(defstruct phases
  (ticks (make-array 7 :element-type 'integer :initial-element 0))
  (bytes (make-array 7 :element-type 'integer :initial-element 0))
  (counts (make-array 7 :element-type 'integer :initial-element 0)))
(defparameter *cases* %lui.benchmark:*cases*)
(defparameter *records* (make-hash-table :test #'eq))
(defparameter *current* nil)
(defparameter *restores* nil)
(defparameter *reported-gpu* nil)
(defun ticks ()
  (multiple-value-bind (s ns) (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ (* s 1000000000) ns)))
(defun install (symbol wrapper)
  (let ((original (symbol-function symbol)))
    (push (cons symbol original) *restores*)
    (setf (symbol-function symbol) (funcall wrapper original))))
(defun timer (index)
  (lambda (original)
    (lambda (&rest arguments)
      (declare (dynamic-extent arguments))
      (let ((start (ticks))
            (bytes (sb-ext:get-bytes-consed)))
        (multiple-value-prog1 (apply original arguments)
          (when (= index 4)
            (let ((finish-start (ticks)))
              (cffi:foreign-funcall "glFinish" :void)
              (when *current*
                (incf (aref (phases-ticks *current*) 6)
                      (- (ticks) finish-start))
                (incf (aref (phases-counts *current*) 6)))))
          (let ((end (ticks))
                (end-bytes (sb-ext:get-bytes-consed)))
            (when *current*
              (incf (aref (phases-ticks *current*) index) (- end start))
              (incf (aref (phases-bytes *current*) index) (- end-bytes bytes))
              (incf (aref (phases-counts *current*) index)))))))))
(defun gpu-report (original)
  (lambda (gpu)
    (unless *reported-gpu*
      (setf *reported-gpu* t)
      (format t "DEVICE cpu=~S pixels=~Dx~D logical=~Dx~D gl=~S~%"
              (machine-version) (%lui.gl:gpu-width gpu) (%lui.gl:gpu-height gpu)
              (%lui.gl:gpu-logical-width gpu) (%lui.gl:gpu-logical-height gpu)
              (cffi:foreign-string-to-lisp
               (cffi:foreign-funcall "glGetString" :uint #x1f01 :pointer))))
    (funcall original gpu)))
(defun report ()
  (let ((total (make-phases)))
    (dolist (case *cases*)
      (let ((record (gethash case *records*)))
        (dotimes (i 7)
          (assert (= (aref (phases-counts record) i)
                     (aref (phases-counts record) 0)))
          (incf (aref (phases-ticks total) i) (aref (phases-ticks record) i))
          (incf (aref (phases-bytes total) i) (aref (phases-bytes record) i))
          (incf (aref (phases-counts total) i) (aref (phases-counts record) i)))
        (format t "ACTIVE ~S frames=~D mean_ms=~,6F bytes_mean=~,1F~%"
                case (aref (phases-counts record) 0)
                (/ (loop :for i :in '(0 3 4) :sum (aref (phases-ticks record) i))
                   (* 1000000d0 (aref (phases-counts record) 0)))
                (/ (loop :for i :in '(0 3 4) :sum (aref (phases-bytes record) i))
                   (float (aref (phases-counts record) 0) 1d0)))))
    (dotimes (i 7)
      (format t "PHASE ~A count=~D mean_ms=~,6F bytes_mean=~,1F~%"
              (aref *names* i) (aref (phases-counts total) i)
              (/ (aref (phases-ticks total) i)
                 (* 1000000d0 (aref (phases-counts total) i)))
              (/ (aref (phases-bytes total) i)
                 (float (aref (phases-counts total) i) 1d0))))
    (format t "ACTIVE ALL frames=~D mean_ms=~,6F bytes_mean=~,1F~%"
            (aref (phases-counts total) 0)
            (/ (loop :for i :in '(0 3 4) :sum (aref (phases-ticks total) i))
               (* 1000000d0 (aref (phases-counts total) 0)))
            (/ (loop :for i :in '(0 3 4) :sum (aref (phases-bytes total) i))
               (float (aref (phases-counts total) 0) 1d0)))))
(unwind-protect
     (progn
       (dolist (case *cases*) (setf (gethash case *records*) (make-phases)))
       (install '%lui.benchmark:select-case
                (lambda (original)
                  (lambda (index)
                    (let ((case (funcall original index)))
                      (setf *current* (when (>= index %lui.benchmark:*warmup*)
                                        (gethash case *records*)))
                      case))))
       (loop :for symbol :in '(%lui.frame:call-with-frame
                               %lui.example.demo:draw
                               %lui.layout:solve
                               %lui.gl:begin-gpu-frame
                               lui.draw:%paint-frame
                               %lui.gl:present-gpu)
             :for i :from 0 :do (install symbol (timer i)))
       (install '%lui.gl:begin-gpu-frame #'gpu-report)
       (if (uiop:getenv "LUI_PROFILE")
           (progn
             (eval '(sb-sprof:with-profiling
                        (:max-samples 5000 :sample-interval 0.0005
                         :report :flat :loop nil)
                      ;; else
           (%lui.benchmark:run-benchmarks))))
           ;; else
           (%lui.benchmark:run-benchmarks))
       (report))
  (dolist (pair *restores*) (setf (symbol-function (car pair)) (cdr pair))))
