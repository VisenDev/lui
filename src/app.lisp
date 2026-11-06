(defpackage #:lui
  (:use #:cl #:lui.fn)
  (:export #:run #:register-backend #:available-backends #:units #:*backend*
           #:*unit* #:with-toolkit #:current-toolkit #:toolkit-defaults
           #:opt #:panel #:label #:button #:tab #:checkbox #:slider
           #:text-field #:cell #:list-item #:gauge #:canvas))

(in-package #:lui)

(defvar *backends* (make-hash-table :test 'eq))

(defvar *backend* nil
  "Default backend override; NIL selects an available backend.")

(defvar *unit* 1 "Layout spacing unit supplied by the active backend.")

(fn (units real) ((count real))
  (* count *unit*))

(fn register-backend ((name symbol) (runner function))
  (setf (gethash name *backends*) runner))

(fn (available-backends list) ()
  (loop :for name :in '(:web :win32 :cocoa :wayland :x11 :terminal)
        :when (gethash name *backends*)
          :collect name))

(fn run
    ((draw function) &key (backend *backend*) ((title string) "LUI") width
     height (interactive t))
  "Run the same immediate-mode DRAW function on any registered backend.
Backend-specific window, DOM, input, frame, and lifetime management stay in LUI.
WIDTH/HEIGHT are optional backend coordinates; omit them for sensible defaults.
INTERACTIVE NIL renders one frame (useful for tests and terminal snapshots)."
  (let* ((name (or backend (first (available-backends))))
         (runner (gethash name *backends*)))
    (unless runner
      (error "Backend ~S is not loaded. Available: ~S" name
             (available-backends)))
    (funcall runner draw :title title :width width :height height
             :interactive interactive)))

(defvar *collection* :glass)

(defun current-toolkit () *collection*)

(defun toolkit-defaults (&optional (toolkit *collection*))
  (ecase toolkit
    (:glass lui.glass:*defaults*)
    (:motif lui.motif:*defaults*)
    (:garnet lui.garnet:*defaults*)))

(defmacro with-toolkit ((designator) &body body)
  "Draw BODY with the named collection; nested bindings restore on exit."
  `(let ((*collection* ,designator))
     (toolkit-defaults *collection*)
     ,@body))

(defmacro opt (&rest forms &key width height padding gap align cross-align
               id direction clip-p scroll-p floating-p offset-x offset-y
               interactive-p keyboard-focus-p pointer-focus-p
               foreground background radius frost minimum maximum step
               font-size font-family font-weight opacity accent disabled-p
               painter selected-p text)
  "Build widget options, preserving order, explicit NIL, and omitted keys."
  (declare (ignore width height padding gap align cross-align id direction
                   clip-p scroll-p floating-p offset-x offset-y interactive-p
                   keyboard-focus-p pointer-focus-p foreground background
                   radius frost minimum maximum step font-size font-family
                   font-weight opacity accent disabled-p painter selected-p
                   text))
  `(list ,@forms))

(defmacro panel (options &body body)
  `(let ((lui.frame:*parent*
           (lui.widgets:declare-panel
            *collection* (append ,options (toolkit-defaults)))))
     ,@body))

(defmacro define-control (name args glass motif garnet)
  `(defun ,name (,@args &optional options)
     (apply (ecase *collection*
              (:glass #',glass) (:motif #',motif) (:garnet #',garnet))
            ,@args options)))

(define-control label (text)
  lui.glass:label lui.motif:label lui.garnet:label)

(define-control button (id text)
  lui.glass:button lui.motif:button lui.garnet:button)

(define-control tab (id text)
  lui.glass:tab lui.motif:tab lui.garnet:tab)

(define-control checkbox (id value text)
  lui.glass:checkbox lui.motif:checkbox lui.garnet:checkbox)

(define-control slider (id value)
  lui.glass:slider lui.motif:slider lui.garnet:slider)

(define-control text-field (id value)
  lui.glass:text-field lui.motif:text-field lui.garnet:text-field)

(define-control cell (id text)
  lui.glass:cell lui.motif:cell lui.garnet:cell)

(define-control list-item (id text)
  lui.glass:list-item lui.motif:list-item lui.garnet:list-item)

(define-control gauge (id fraction)
  lui.glass:gauge lui.motif:gauge lui.garnet:gauge)

(define-control canvas (id commands)
  lui.glass:canvas lui.motif:canvas lui.garnet:canvas)
