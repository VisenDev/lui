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
  ((setting :initarg :setting :reader error-setting
            :documentation
            "Configuration setting that could not be resolved.")
   (value :initarg :value :initform nil :reader error-value
          :documentation
          "Requested value for the invalid or missing setting."))
  (:documentation
    "An invalid or unavailable backend, toolkit, palette, control, rendering callback, or widget key.
ERROR-SETTING identifies the setting and ERROR-VALUE contains its requested
value. Configure or load the missing capability before retrying the operation.
For ambiguous widget keys, use the resolved ID returned by the widget.
Repeated control declarations signal this condition with operation :DECLARE-WIDGET
and setting :ID. Supply distinct OPT :id keys or WITH-KEY scopes for instances."))

(define-condition backend-error (lui-error)
  ((backend :initarg :backend :reader error-backend
            :documentation
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
