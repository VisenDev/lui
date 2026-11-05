(defpackage #:lui
  (:use #:cl #:lui.fn)
  (:export #:run #:register-backend #:available-backends #:units #:*backend*
    #:*unit*))

(in-package #:lui)

(defvar *backends* (make-hash-table :test 'eq))

(defvar *backend* nil
  "Default backend override; NIL selects an available backend.")

(defvar *unit* 1 "Layout spacing unit supplied by the active backend.")

(fn (units real) ((count real)) (* count *unit*))

(fn register-backend ((name symbol) (runner function))
  (setf (gethash name *backends*) runner))

(fn (available-backends list) ()
  (loop :for name :in '(:web :win32 :cocoa :wayland :x11 :terminal) :when
    (gethash name *backends*) :collect name))

(fn run
  ((draw function) &key (backend *backend*) ((title string) "LUI") width
    height (interactive t))
  "Run the same immediate-mode DRAW function on any registered backend.
Backend-specific window, DOM, input, frame, and lifetime management stay in LUI.
WIDTH/HEIGHT are optional backend coordinates; omit them for sensible defaults.
INTERACTIVE NIL renders one frame (useful for tests and terminal snapshots)."
  (let*
    ((name (or backend (first (available-backends))))
      (runner (gethash name *backends*)))
    (unless runner
      (error "Backend ~S is not loaded. Available: ~S" name
        (available-backends)))
    (funcall runner draw :title title :width width :height height
      :interactive interactive)))
