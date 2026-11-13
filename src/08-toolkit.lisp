(defpackage #:lui.toolkit
  (:use #:cl #:%lui.fn)
  (:import-from #:lui.palette #:%resolve-palette)
  (:export
           #:register-toolkit #:register-toolkit-rendering #:toolkit-paint
           #:toolkit-geometry #:toolkit-native-labels-p #:toolkit-palette
           #:toolkit-defaults #:define-toolkit #:%*toolkit-revision*
           #:current-toolkit #:call-with-toolkit #:with-toolkit #:control
           #:%*toolkit* #:%*toolkit-definition* #:%find-toolkit #:%override
           #:%without-option))
(in-package #:lui.toolkit)

(fn (%without-option list) ((key symbol) (options list))
  "Return an option plist without KEY and its associated value."
  (let ((result nil))
    (do ((tail options (cddr tail))) ((null tail) (nreverse result))
      (unless (eq (car tail) key)
        (push (car tail) result)
        (push (cadr tail) result)))))

(defvar %*toolkit* :qt)
(defvar %*toolkit-definition* nil)

(defstruct (toolkit (:conc-name %toolkit-))
  (parent nil :type symbol)
  (defaults nil :type (or list function))
  (controls nil :type list)
  (paint :inherit :type (or function (member nil :inherit)))
  (geometry :inherit :type (or function (member nil :inherit)))
  (native-labels :inherit :type (member nil t :inherit)))
(defvar *toolkits* (make-hash-table :test 'eq))

(defvar %*toolkit-revision* 0)

(fn (%find-toolkit toolkit) ((name symbol))
  "Resolve a toolkit name or signal a CONFIGURATION-ERROR for an unknown name."
  (or (gethash name *toolkits*) (error '%lui.conditions:configuration-error
                                       :setting :toolkit :value name
                                       :operation :find-toolkit
                                       :format-control "Unknown toolkit ~S."
                                       :format-arguments (list name))))

(fn (rendering-option t) ((name symbol) (key symbol))
  "Resolve an inherited toolkit rendering policy through its parent chain."
  (let* ((entry (%find-toolkit name))
         (value (ecase key (:paint (%toolkit-paint entry))
                       (:geometry (%toolkit-geometry entry))
                       (:native-labels (%toolkit-native-labels entry)))))
    (if (not (eq value :inherit)) value
        ;; else
        (when (and (%toolkit-parent entry)
                   (or (not (eq key :native-labels))
                       (and (eq (%toolkit-paint entry) :inherit)
                            (eq (%toolkit-geometry entry) :inherit))))
          (rendering-option (%toolkit-parent entry) key)))))

(fn (toolkit-paint (or null function)) ((name symbol))
  "Return NAME's graphical painter, inherited through its parent, or NIL."
  (rendering-option name :paint))

(fn (toolkit-geometry (or null function)) ((name symbol))
  "Return NAME's graphical geometry callback (widget -> geometry), inherited from its parent."
  (rendering-option name :geometry))

(fn (toolkit-native-labels-p boolean) ((name symbol))
  "Return whether NAME delegates graphical labels to native text rendering."
  (not (null (rendering-option name :native-labels))))

(fn (register-toolkit-rendering symbol)
    ((name symbol) &key ((paint (or null function)) nil
                               paint-p)
                     ((geometry (or null function)) nil
                               geometry-p)
                     ((native-labels boolean) nil
                                    labels-p))
  "Set graphical callbacks for registered NAME. Omitted keys retain their
settings or inherit from :PARENT; explicit NIL disables the inherited setting."
  (let ((entry (%find-toolkit name)))
    (when paint-p (check-type paint (or null function)))
    (when geometry-p (check-type geometry (or null function)))
    (when paint-p (setf (%toolkit-paint entry) paint))
    (when geometry-p (setf (%toolkit-geometry entry) geometry))
    (when labels-p (setf (%toolkit-native-labels entry)
                     (not
                       (null
                         native-labels))))
    (incf %*toolkit-revision*))
  name)

(fn (register-toolkit symbol)
    ((name symbol) &key ((parent symbol) nil)
     ((defaults (or list function)) nil) ((controls list) nil)
     ((paint (or null function)) nil paint-p)
     ((geometry (or null function)) nil geometry-p)
     ((native-labels boolean) nil labels-p))
  "Register a toolkit. DEFAULTS is a plist or a zero-argument function.
CONTROLS maps control names to functions taking the public arguments and options.
PAINT, GEOMETRY and NATIVE-LABELS configure graphical rendering; omitted values
inherit only from an explicit PARENT."
  (loop :for ancestor := parent
        :then (%toolkit-parent (%find-toolkit ancestor))
        :while ancestor :when (eq ancestor name)
        :do (error '%lui.conditions:configuration-error
                   :setting :toolkit :value name
                   :operation :register-toolkit
                   :format-control "Circular toolkit inheritance at ~S."
                   :format-arguments (list name)))
  (when paint-p (check-type paint (or null function)))
  (when geometry-p (check-type geometry (or null function)))
  (incf %*toolkit-revision*)
  (setf (gethash name *toolkits*)
        (make-toolkit :parent parent :defaults defaults :controls controls
                      :paint (if paint-p paint :inherit)
                      :geometry (if geometry-p geometry :inherit)
                      :native-labels (if labels-p (not (null native-labels))
                                         ;; else
                                         :inherit)))
  name)

(fn (current-toolkit symbol) ()
  "Return the toolkit name active in this drawing scope."
  %*toolkit*)

(fn (defaults-of list) ((entry toolkit))
  "Collect toolkit defaults, evaluating dynamic providers for this declaration."
  (let* ((parent (%toolkit-parent entry))
         (source (%toolkit-defaults entry))
         (defaults (if (functionp source) (funcall source) source)))
    (if parent (append defaults (defaults-of (%find-toolkit parent)))
        ;; else
        defaults)))

(fn (toolkit-palette list) (&optional ((name symbol) %*toolkit*))
  "Return scoped semantic colors followed by NAME's inherited palette."
  (%resolve-palette (defaults-of (%find-toolkit name))))

(fn (toolkit-defaults (values list list))
    (&optional ((name symbol) %*toolkit*) ((kind symbol) nil))
  "Return appearance defaults for KIND and the captured palette as a second value."
  (let* ((defaults (defaults-of (%find-toolkit name)))
         (palette (copy-list (%resolve-palette defaults))))
    (values (list* :palette palette
                   :foreground (%lui.widgets:palette-color palette
                                                           :foreground)
                   :background
                   (or
                    (when (member kind '(:button :tab
                                         :text-field))
                      (%lui.widgets:palette-color palette
                                                  :control-background))
                    (%lui.widgets:palette-color palette
                                                :background))
                   :accent (%lui.widgets:palette-color palette :accent)
                   (%without-option :palette defaults))
            palette)))

(fn (%override (or null function)) ((kind symbol) (entry toolkit))
  "Merge explicit widget options with defaults, preserving explicit NIL values."
  (or (cdr (assoc kind (%toolkit-controls entry)))
      (let ((parent (%toolkit-parent entry)))
        (when parent (%override kind (%find-toolkit parent))))))

(fn (control t) ((kind symbol) &rest (arguments list))
  "Invoke a user-defined control from the current toolkit or its ancestors."
  (apply (or (%override kind (or %*toolkit-definition*
                                (%find-toolkit %*toolkit*)))
             (error '%lui.conditions:configuration-error
                    :setting :control :value kind
                    :operation :control
                    :format-control "No ~S control in toolkit ~S."
                    :format-arguments (list kind %*toolkit*)))
         arguments))

(fn (call-with-toolkit (values &rest t))
    ((designator symbol) (draw function))
  "Call DRAW with the named toolkit; restore enclosing bindings on exit."
  (let* ((%*toolkit* designator)
         (%*toolkit-definition* (%find-toolkit %*toolkit*)))
    (declare (special %*toolkit* %*toolkit-definition*))
    (funcall draw)))

(defmacro with-toolkit ((designator) &body body)
  "Draw BODY with the named toolkit; nested bindings restore on exit."
  `(call-with-toolkit ,designator (lambda () ,@body)))
