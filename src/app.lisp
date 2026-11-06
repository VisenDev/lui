(defpackage #:lui
  (:use #:cl #:lui.fn #:lui.widgets #:lui.frame)
  (:export #:run #:register-backend #:available-backends #:units #:*backend*
           #:*unit* #:with-toolkit #:current-toolkit #:toolkit-defaults
           #:register-toolkit #:toolkit-revision #:toolkit-surface
           #:control #:map-toolkit-web-styles
           #:toolkit-web-style #:define-collection #:opt #:panel #:label
           #:button #:tab #:checkbox #:slider
           #:text-field #:cell #:list-item #:gauge #:canvas))

(in-package #:lui)

(defvar *backends* (make-hash-table :test 'eq))

(defvar *backend* nil
  "Default backend override; NIL selects an available backend.")

(defvar *unit* 1 "Layout spacing unit supplied by the active backend.")

(fn (units real) ((count real))
  "Convert spacing units to backend coordinates: terminal cells or graphical units."
  (* count *unit*))

(fn register-backend ((name symbol) (runner function))
  "Install a RUN implementation under NAME; normally called by a backend."
  (setf (gethash name *backends*) runner))

(fn (available-backends list) ()
  "List the backends loaded in this Lisp image, in default selection order."
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
(defvar *definition* nil)

(defstruct collection parent defaults controls web-style)
(defvar *collections* (make-hash-table :test 'eq))

(defvar *toolkit-revision* 0)
(defun toolkit-revision ()
  "Return the generation used to invalidate cached toolkit styles."
  *toolkit-revision*)

(defun collection (name)
  (or (gethash name *collections*) (error "Unknown toolkit ~S." name)))

(defun register-toolkit (name &key parent defaults controls web-style
                                   (surface (if parent
                                                (toolkit-surface parent)
                                                :glass)))
  "Register a collection. DEFAULTS is a plist or a zero-argument function.
CONTROLS maps control names to functions taking the public arguments and options.
WEB-STYLE, when provided, takes the DOM node, widget and layout element."
  (loop :for ancestor := parent
          :then (collection-parent (collection ancestor))
        :while ancestor :when (eq ancestor name)
          :do (error "Circular toolkit inheritance at ~S." name))
  (incf *toolkit-revision*)
  (register-surface name surface)
  (setf (gethash name *collections*)
        (make-collection :parent parent :defaults defaults
                         :controls controls :web-style web-style))
  name)

(defun current-toolkit ()
  "Return the toolkit name active in this drawing scope."
  *collection*)

(defun defaults-of (entry)
  (let* ((parent (collection-parent entry))
         (source (collection-defaults entry))
         (defaults (if (functionp source) (funcall source) source)))
    (if parent (append defaults (defaults-of (collection parent))) defaults)))

(defun toolkit-defaults (&optional (name *collection*))
  "Return appearance defaults with child overrides before inherited values."
  (defaults-of (collection name)))

(defun toolkit-web-style (name)
  "Read or replace a toolkit’s DOM styling callback. Inherited callbacks run first."
  (collection-web-style (collection name)))

(defun (setf toolkit-web-style) (callback name)
  (incf *toolkit-revision*)
  (setf (collection-web-style (collection name)) callback))

(defun map-toolkit-web-styles (name function)
  "Call FUNCTION on each registered DOM styling callback, from parent to child."
  (let* ((entry (collection name)) (parent (collection-parent entry))
         (style (collection-web-style entry)))
    (when parent (map-toolkit-web-styles parent function))
    (when style (funcall function style))))

(defun override (kind entry)
  (or (cdr (assoc kind (collection-controls entry)))
      (let ((parent (collection-parent entry)))
        (when parent (override kind (collection parent))))))

(defun control (kind &rest arguments)
  "Invoke a user-defined control from the current toolkit or its ancestors."
  (apply (or (override kind (or *definition* (collection *collection*)))
             (error "No ~S control in toolkit ~S." kind *collection*))
         arguments))

(defmacro with-toolkit ((designator) &body body)
  "Draw BODY with the named collection; nested bindings restore on exit."
  `(let* ((*collection* ,designator)
          (*definition* (collection *collection*)))
     ,@body))

(defmacro opt (&rest forms &key width height padding gap align cross-align
               id direction clip-p scroll-p scrollbar-p scrollbar-width
               floating-p offset-x offset-y
               interactive-p keyboard-focus-p pointer-focus-p
               foreground background radius frost minimum maximum step
               font-size font-family font-weight opacity accent disabled-p
               painter web-style terminal-label selected-p text)
  "Build widget options, preserving order, explicit NIL, and omitted keys."
  (declare (ignore width height padding gap align cross-align id direction
                   clip-p scroll-p scrollbar-p scrollbar-width
                   floating-p offset-x offset-y interactive-p
                   keyboard-focus-p pointer-focus-p foreground background
                   radius frost minimum maximum step font-size font-family
                   font-weight opacity accent disabled-p painter web-style
                   terminal-label
                   selected-p text))
  `(list ,@forms))

(defmacro panel (options &body body)
  "Draw a styled container and attach widgets declared in BODY as children."
  `(let ((lui.frame:*parent*
           (lui.widgets:declare-panel
            *collection* (append ,options (toolkit-defaults)))))
     ,@body))

(defmacro define-control (name args doc &body body)
  (let ((kind (intern (symbol-name name) :keyword)))
    `(defun ,name (,@args &optional options)
       ,doc
       (let* ((entry (or *definition* (collection *collection*)))
              (custom (override ,kind entry)))
         (if custom (funcall custom ,@args options)
             (let ((style *collection*) (defaults (defaults-of entry)))
               ,@body))))))

(define-control label (text)
  "Display selectable text. Width determines wrapping; no ID is needed."
  (apply #'declare-widget :label style nil text (append options defaults)))

(define-control button (id text)
  "Return true in the frame where the control with this ID activates."
  (apply #'declare-widget :button style id text (append options defaults)))

(defun without-option (key options)
  (let ((result nil))
    (do ((tail options (cddr tail))) ((null tail) (nreverse result))
      (unless (eq (car tail) key)
        (push (car tail) result)
        (push (cadr tail) result)))))

(defun selectable (kind style id text options defaults)
  (apply #'declare-widget kind style id text :value (getf options :selected-p)
         (append (without-option :selected-p options) defaults)))

(define-control tab (id text)
  "Declare a tab. Supply :selected-p in OPT and update the page on activation."
  (selectable :tab style id text options defaults))

(define-control list-item (id text)
  "Declare a selectable row and return activation. The caller owns selection."
  (selectable :list-item style id text options defaults))

(define-control cell (id text)
  "Display a compact grid cell. Use :selected-p to mark the active cell."
  (selectable :cell style id text options
              (list* :background "#ffffff" :foreground "#202430" defaults)))

(define-control checkbox (id value text)
  "Return the new boolean and a second value indicating a change."
  (value-widget :checkbox style id value text (append options defaults)))

(define-control slider (id value)
  "Return the new number and a change flag. OPT accepts :minimum, :maximum and :step."
  (value-widget :slider style id value (getf options :text "")
                (append (without-option :text options) defaults)))

(define-control text-field (id value)
  "Return the edited string and a change flag. Keep the returned string in your model."
  (value-widget :text-field style id value "" (append options defaults)))

(define-control gauge (id fraction)
  "Display a read-only progress fraction, clamped to the range zero to one."
  (apply #'declare-widget :gauge style id "" :value (max 0 (min 1 fraction))
         (append options defaults)))

(define-control canvas (id commands)
  "Display circle commands (kind x y radius stroke fill) in local coordinates."
  (apply #'declare-widget :canvas style id "" :value commands
         (append options defaults)))

(defmacro define-collection (name defaults panel-name &rest names)
  "Retain collection-qualified entry points for existing callers."
  (let ((functions '(label button tab checkbox slider text-field cell
                     list-item gauge canvas))
        (args '((text) (id text) (id text) (id value text) (id value)
                (id value) (id text) (id text) (id fraction) (id commands))))
    `(progn
       (register-toolkit ,name :surface ,name :defaults (lambda () ,defaults))
       ,@(loop :for local :in names :for fn :in functions :for a :in args
               :collect
               `(defun ,local (,@a &optional options &rest legacy)
                  (with-toolkit (,name)
                    (,fn ,@a (if legacy (cons options legacy) options)))))
       (defmacro ,panel-name (options &body body)
         (let ((form (if (and (consp options) (keywordp (car options)))
                         (cons 'opt options) options)))
           (list 'with-toolkit (list ,name) (list* 'panel form body)))))))
