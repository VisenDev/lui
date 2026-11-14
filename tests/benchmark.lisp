(defpackage #:%lui.tests.benchmark
  (:use #:cl)
  (:export #:run-tests))
(in-package #:%lui.tests.benchmark)

(defvar *payload* nil)

(defun measured (frame)
  (let ((%lui.benchmark::*cases* '((:glass :controls)))
        (%lui.benchmark::*frames* 3) (%lui.benchmark::*warmup* 1)
        (%lui.benchmark::*samples* (make-hash-table :test 'equal))
        (%lui.benchmark::*allocations* (make-hash-table :test 'equal)))
    (%lui.benchmark::benchmark-loop frame)
    (assert (= 3 (length (gethash '(:glass :controls)
                                 %lui.benchmark::*samples*))))
    (gethash '(:glass :controls) %lui.benchmark::*allocations*)))

(defun run-tests ()
  ;; Compare known escaping allocations against an empty frame, not host speed.
  #+sbcl
  (let* ((empty (measured (lambda () nil)))
         (large (measured
                 (lambda ()
                   (setf *payload*
                         (make-array (* 1024 1024)
                                     :element-type '(unsigned-byte 8)))
                   (sb-ext:gc))))
         (empty-bytes (reduce #'+ empty
                               :key #'%lui.benchmark::allocation-bytes))
         (large-bytes (reduce #'+ large
                               :key #'%lui.benchmark::allocation-bytes)))
    (assert (= 3 (length large) (length empty)))
    (assert (> large-bytes (+ empty-bytes (* 2 1024 1024))))
    (assert (every (lambda (record)
                     (>= (%lui.benchmark::allocation-bytes record)
                         (* 1024 1024)))
                   large))
    (assert (every (lambda (record)
                     (let ((time (%lui.benchmark::allocation-gc-time record)))
                       (not (minusp time))))
                   large))
    (format t "Allocated bytes: empty=~D large=~D (~D measured frames).~%"
            empty-bytes large-bytes (length large))
    (setf *payload* nil))
  (let* ((records
           (loop :for bytes :in '(3 1 2)
                 :collect (%lui.benchmark::make-allocation :bytes bytes
                                                        :gc-time 0)))
         (text (with-output-to-string (*standard-output*)
                 (%lui.benchmark::report-allocation :test :summary records))))
    (assert (search "bytes_total=6 bytes_mean=2.00 bytes_p95=3" text))
    (assert (search "gc_count=unsupported gc_cpu_ms=0.000" text)))
  (assert (search "status=unsupported"
                  (with-output-to-string (*standard-output*)
                    (%lui.benchmark::report-allocation :test :none nil))))
  (format t "Benchmark allocated bytes, GC CPU accounting and summaries passed.~%")
  t)
