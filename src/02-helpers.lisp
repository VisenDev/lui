(defpackage #:lui.conditions
  (:use #:cl)
  (:export #:lui-error #:configuration-error #:backend-error #:font-error
           #:frame-state-error #:error-operation #:error-setting
           #:error-value #:error-backend #:error-font-request))
(in-package #:lui.conditions)

(define-condition lui-error (simple-error)
  ((operation :initarg :operation :initform nil :reader error-operation
              :documentation
              "Operation that failed, or NIL when unspecified."))
  (:documentation
   "Base class for LUI failures. The inherited SIMPLE-CONDITION format control
and arguments retain the diagnostic message; ERROR-OPERATION identifies the
operation. Catch a more specific subtype when recovery depends on the cause."))

(define-condition configuration-error (lui-error)
  ((setting :initarg :setting :reader error-setting :documentation
            "Configuration setting that could not be resolved.")
   (value :initarg :value :initform nil :reader error-value :documentation
          "Requested value for the invalid or missing setting."))
  (:documentation
   "An invalid or unavailable backend, toolkit, palette, control, or rendering callback.
ERROR-SETTING identifies the setting and ERROR-VALUE contains its requested
value. Configure or load the missing capability before retrying the operation."))

(define-condition backend-error (lui-error)
  ((backend :initarg :backend :reader error-backend :documentation
            "Backend keyword whose platform operation failed."))
  (:documentation
   "A platform operation failed during initialization, input, rendering, or cleanup.
ERROR-BACKEND identifies the platform and ERROR-OPERATION names the failing
operation. The inherited diagnostic includes any available platform status."))

(define-condition font-error (backend-error)
  ((request :initarg :request :reader error-font-request
            :documentation "Font family/weight request that could not be loaded."))
  (:documentation
   "No usable font was found for ERROR-FONT-REQUEST. Configure a matching font
path or font directory before opening the next graphical window."))

(define-condition frame-state-error (lui-error) ()
  (:documentation
   "An operation requires a completed frame or another unavailable frame state.
ERROR-OPERATION identifies the attempted operation; complete a frame before
retrying an operation that reads its solved layout."))

(defpackage #:lui.text
  (:use #:cl #:lui.fn)
  (:export #:wrap-lines))
(in-package #:lui.text)

(fn (wrap-lines (vector string))
    ((text string) (width (or null real)) (measure function))
  "Wrap at spaces and newlines. MEASURE takes TEXT and a start/end range.
Preserve empty lines and allow words wider than WIDTH to overflow."
  (let ((start 0) (length (length text))
        (lines (make-array 0 :element-type 'string :adjustable t
                           :fill-pointer 0)))
    (loop
     (let ((end (or (position #\Newline text :start start) length)))
       (when width
         (let ((previous nil) (cursor (min end (1+ start))))
           (loop
            (let ((space (position #\Space text :start cursor :end end)))
              (cond
                ((<= (funcall measure text start (or space end)) width)
                 (unless space (return))
                 (setf previous space cursor (1+ space)))
                ((or previous space)
                 (let ((split (or previous space)))
                   (vector-push-extend (subseq text start split) lines)
                   (setf start (1+ split) previous nil
                         cursor (min end (1+ start)))))
                (t (return)))))))
       (vector-push-extend (subseq text start end) lines)
       (when (= end length) (return))
       (setf start (1+ end))))
    lines))
