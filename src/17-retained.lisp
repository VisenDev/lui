(defpackage #:lui.retained
  (:use #:cl #:%lui.fn)
  (:export #:draw #:node))
(in-package #:lui.retained)

(defstruct renderer
  (arity 0 :type (integer 0 *))
  (arguments nil :type list)
  (container-p nil :type boolean)
  (function #'identity :type function))

(defvar *renderers* (make-hash-table :test #'eq))
(defvar *ancestors* nil)
(defvar *callbacks* nil)

(fn (invalid-tree (values)) ((value t) (message string))
  "Signal a configuration error for an invalid retained description."
  (error 'lui:configuration-error :operation :retained-draw
         :setting :tree :value value :format-control "~A"
         :format-arguments (list message)))

(fn (proper-list-p boolean) ((value t))
  "Recognize finite proper lists without hanging on circular descriptions."
  (and (listp value)
       (handler-case (not (null (list-length value)))
         (type-error () nil))))

(fn (check-options (values)) ((options t))
  "Require a proper keyword plist and callable event handlers."
  (unless (and (proper-list-p options) (evenp (length options)))
    (invalid-tree options "Expected an even keyword property list."))
  (loop :for (key value) :on options :by #'cddr
        :do (unless (keywordp key)
              (invalid-tree options "Option names must be keywords."))
            (when (and (member key '(:on-change :on-activate))
                       value (not (or (functionp value) (symbolp value))))
              (invalid-tree value "Event handlers must be functions, symbols or NIL.")))
  (values))

(fn (option-value t) ((value t))
  "Resolve an explicit spacing descriptor without evaluating Lisp forms."
  (cond
    ((and (consp value) (eq (first value) :units))
     (unless (and (proper-list-p value) (= (length value) 2)
                  (realp (second value)))
       (invalid-tree value "Expected (:units NUMBER)."))
     (lui:units (second value)))

    (t value)))

(fn (control-options list) ((options list))
  "Strip retained event handlers before passing options to LUI."
  (loop :for (key value) :on options :by #'cddr
        :unless (member key '(:on-change :on-activate))
          :append (list key (if (member key '(:padding :gap
                                           :offset-x :offset-y :radius
                                           :font-size :column-gap))
                                 (option-value value) value))))

(fn (invoke-callback (values))
    ((callback (or function symbol)) (arguments list))
  "Resolve a symbol at dispatch time so redefinitions affect existing trees."
  (apply (if (symbolp callback) (symbol-function callback) callback) arguments)
  (values))

(defmacro define-leaf (kind control arguments event)
  "Register a compiled adapter to a public LUI control macro."
  `(setf (gethash ,kind *renderers*)
         (make-renderer
          :arity ,(length arguments)
          :arguments ',(mapcar (lambda (name)
                                 (intern (symbol-name name) :keyword))
                               arguments)
          :function
          (lambda (arguments options children)
            (declare (ignore children))
            (destructuring-bind ,arguments arguments
              (multiple-value-bind (value changed)
                  (,control ,@arguments :options (control-options options))
                (declare (ignorable changed))
                (let ((callback (getf options ,event)))
                  (when (and callback ,(if (eq event :on-change)
                                          'changed 'value))
                    ,(if (eq event :on-change)
                         '(push (lambda () (invoke-callback callback (list value)))
                                *callbacks*)
                         '(push (lambda () (invoke-callback callback nil))
                                *callbacks*))))))))))

(defmacro define-container (kind control)
  "Register a container adapter that draws its child descriptions."
  `(setf (gethash ,kind *renderers*)
         (make-renderer
          :container-p t
          :function (lambda (arguments options children)
                      (declare (ignore arguments))
                      (,control (:options (control-options options))
                        (draw-children children))))))

(fn (node-parts (values renderer list list list)) ((node t))
  "Parse a node into its adapter, positional arguments, options and children."
  (unless (and (consp node) (proper-list-p node))
    (invalid-tree node "Expected a nonempty proper node list."))
  (when (member node *ancestors* :test #'eq)
    (invalid-tree node "Container children must not contain an ancestor."))
  (let ((renderer (gethash (first node) *renderers*))
         (tail (rest node)))
    (unless renderer
      (invalid-tree node "Unknown retained control kind."))
    (when (< (length tail) (renderer-arity renderer))
      (invalid-tree node "Missing positional control arguments."))
    (let* ((count (renderer-arity renderer))
           (arguments (subseq tail 0 count))
           (remaining (nthcdr count tail))
           (options (if (renderer-container-p renderer)
                        (first remaining) remaining))
           (children (when (renderer-container-p renderer)
                       (rest remaining))))
      (check-options options)
      (values renderer arguments options children))))

(fn (draw-children (values)) ((nodes list))
  "Draw siblings with stable explicit keys or positional fallback identities."
  (unless (proper-list-p nodes)
    (invalid-tree nodes "Expected a finite proper list of nodes."))
  (let ((seen (make-hash-table :test #'equal)))
    (loop :for node :in nodes
          :for index :from 0
          :do (multiple-value-bind (renderer arguments options children)
                  (node-parts node)
                (let ((key (if (getf options :id)
                               (list :key (getf options :id))
                               (list :position index))))
                  (when (gethash key seen)
                    (invalid-tree node "Duplicate sibling identity."))
                  (setf (gethash key seen) t)
                  (lui:call-with-key
                   key (lambda ()
                         (let ((*ancestors* (cons node *ancestors*)))
                           (funcall (renderer-function renderer)
                                    arguments options children))))))))
  (values))

(define-leaf :label lui:label (text) nil)
(define-leaf :button lui:button (text) :on-activate)
(define-leaf :checkbox lui:checkbox (text) :on-change)
(define-leaf :radio lui:radio (choice text) :on-change)
(define-leaf :slider lui:slider () :on-change)
(define-leaf :text-field lui:text-field () :on-change)
(define-leaf :date-picker lui:date-picker () :on-change)
(define-leaf :searchable-combobox lui:searchable-combobox (choices) :on-change)
(define-leaf :gauge lui:gauge (fraction) nil)
(define-leaf :spinner lui:spinner () nil)
(define-leaf :spacer lui:spacer () nil)
(define-leaf :hr lui:hr () nil)
(define-leaf :vr lui:vr () nil)
(define-leaf :cell lui:cell (text) :on-activate)
(define-leaf :list-item lui:list-item (text) :on-activate)
(define-leaf :tab lui:tab (text) :on-activate)
(define-leaf :canvas lui:canvas (commands) nil)
(define-container :row lui:row)
(define-container :column lui:column)
(define-container :panel lui:panel)
(define-container :table lui:table)
(define-container :table-row lui:table-row)
(define-container :table-cell lui:table-cell)

(fn (draw (values)) ((tree list) &key ((id lui:object-id) :retained))
  "Draw a retained description inside the current LUI frame.
Load the optional lui/retained system. NODE constructs nodes with keyword
arguments for editor completion. TREE is a list of nodes, for example
((:button \"hello\") (:label \"hi\")). Leaves contain a kind, the ordinary LUI
positional arguments, then keyword options. Styling options pass through to LUI:
(:text-field :padding 4 :font-size 16 :foreground \"#202430\" :width (lui:grow))
uses the same styling and sizing rules as the immediate control. Numeric
padding, gap, column-gap, offset-x/y, radius and font-size options accept
(:units NUMBER), resolved against LUI:*UNIT* each frame. This lets trees be defined at load time for any backend. Supply actual
sizing objects in constructed data, not unevaluated (lui:grow) forms.
Containers contain a kind, an
options plist, and child nodes: (:column (:gap 1) (:label \"Hello\")).
Store and edit TREE between frames, or reconstruct it each time. No forms are
evaluated and TREE is never modified by DRAW. LUI retains control values and
focus. Use :ID on moving siblings; unkeyed nodes have positional identity.
Changing a node kind resets its control identity. Use distinct DRAW :ID values
for multiple trees in one parent scope. Removed controls lose LUI owned state.
:ON-ACTIVATE takes a zero-argument function; :ON-CHANGE takes a function of the
new value. Either callback can also be a symbol; its SYMBOL-FUNCTION is
looked up when the callback runs. NIL disables the callback. DRAW queues callbacks while declaring widgets, then runs them in
encounter order after successful traversal, before returning. Callbacks may edit
the tree directly; their edits appear next frame. DRAW requests that frame
when callbacks are queued. Traversal errors discard queued callbacks; callback
errors propagate and stop dispatch without rolling back earlier edits.
:VALUE and :DEFAULT-VALUE follow LUI semantics.
This layer replays declarations every frame; it does not cache solved layout."
  (let ((*callbacks* nil))
    (lui:call-with-key id (lambda () (draw-children tree)))
    (when *callbacks*
      (lui:request-frame)
      (dolist (callback (nreverse *callbacks*))
        (funcall callback))))
  (values))

(fn (node-arguments list) ((renderer renderer) (options list))
  "Extract required positional fields from constructor keywords."
  (loop :for key :in (renderer-arguments renderer)
        :collect (if (loop :for option :in options :by #'cddr
                           :thereis (eq key option))
                     (getf options key)
                     ;; else
                     (invalid-tree options
                                   "Missing required node argument."))))

(fn (construct-node list) ((kind keyword) (options list))
  "Build the ordinary list representation without injecting omitted defaults."
  (let ((renderer (gethash kind *renderers*)))
    (unless renderer (invalid-tree kind "Unknown retained control kind."))
    (check-options options)
    (let* ((arguments (node-arguments renderer options))
           (children (getf options :children))
           (appearance
             (loop :for (key value) :on options :by #'cddr
                   :unless (or (eq key :children)
                               (member key (renderer-arguments renderer)))
                     :append (list key value))))
      (unless (proper-list-p children)
        (invalid-tree children "Children must be a finite proper list."))
      (when (and children (not (renderer-container-p renderer)))
        (invalid-tree children "Only containers accept children."))
      (if (renderer-container-p renderer)
          (list* kind appearance (copy-list children))
          ;; else
          (cons kind (append arguments appearance))))))

(fn (node list)
    ((kind keyword) &rest (fields list) &key
     ((text (or null string)) nil)
     ((choice t) nil)
     ((choices (or null vector)) nil)
     ((fraction (or null real)) nil)
     ((commands list) nil)
     ((children list) nil)
     ((id lui:object-id) nil)
     ((width (or null lui:sizing)) nil)
     ((height (or null lui:sizing)) nil)
     ((padding (or null real list)) nil)
     ((position (or null keyword)) nil)
     ((offset-x (or null real list)) nil)
     ((offset-y (or null real list)) nil)
     ((flow (or null keyword)) nil)
     ((align (or null keyword)) nil)
     ((cross-align (or null keyword)) nil)
     ((clip-p boolean) nil)
     ((scroll-p boolean) nil)
     ((scrollbar-p boolean) nil)
     ((scrollbar-width (or null real)) nil)
     ((interactive-p boolean) nil)
     ((keyboard-focus-p boolean) nil)
     ((pointer-focus-p boolean) nil)
     ((foreground (or null string)) nil)
     ((background (or null string)) nil)
     ((palette (or null lui:palette list symbol)) nil)
     ((radius (or null real list)) nil)
     ((frost (or null real)) nil)
     ((font-size (or null real list)) nil)
     ((font-family (or null keyword)) nil)
     ((font-weight (or null keyword)) nil)
     ((opacity (or null real)) nil)
     ((accent (or null string)) nil)
     ((painter (or null function)) nil)
     ((terminal-label (or null function)) nil)
     ((terminal-border (or null string)) nil)
     ((accessible-name (or null string)) nil)
     ((value t) nil)
     ((default-value t) nil)
     ((disabled-p boolean) nil)
     ((selected-p boolean) nil)
     ((gap (or null real list)) nil)
     ((direction (or null keyword)) nil)
     ((column-gap (or null real list)) nil)
     ((column-span (or null integer)) nil)
     ((minimum (or null real)) nil)
     ((maximum (or null real)) nil)
     ((step (or null real)) nil)
     ((placeholder (or null string)) nil)
     ((password-p boolean) nil)
     ((max-results (or null integer)) nil)
     ((on-activate (or function symbol)) nil)
     ((on-change (or function symbol)) nil)
     ((options list) nil))
  "Construct one retained node using explicit keywords for editor completion.
For example (node :button :text \"Hello\" :on-activate 'hello), or
(node :column :gap '(:units 1) :children (list button label)).
Returns the same ordinary list accepted by DRAW; use CL:LIST for a forest.
Required fields follow the kind: :TEXT for labels/buttons/checkboxes/tabs/cells/
list-items, :CHOICE and :TEXT for radio, :CHOICES for searchable-combobox,
:FRACTION for gauge, and :COMMANDS for canvas. Other leaves take no positional
fields. Containers accept :CHILDREN. Remaining keywords are the union of LUI
control options; use those applicable to the chosen kind. Only supplied options
are included, preserving defaults and explicit NIL. Callback symbols are
resolved via SYMBOL-FUNCTION at dispatch time, so redefinition takes effect."
  (declare (ignore text choice choices fraction commands children id width
                   height padding position offset-x offset-y flow align
                   cross-align clip-p scroll-p scrollbar-p scrollbar-width
                   interactive-p keyboard-focus-p pointer-focus-p foreground
                   background palette radius frost font-size font-family
                   font-weight opacity accent painter terminal-label
                   terminal-border accessible-name value default-value
                   disabled-p selected-p gap direction column-gap column-span
                   minimum maximum step placeholder password-p max-results
                   on-activate on-change))
  (check-options options)
  (construct-node
   kind (append (loop :for (key value) :on fields :by #'cddr
                      :unless (eq key :options) :append (list key value))
                options)))
