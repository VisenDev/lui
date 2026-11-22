(defpackage #:lui.retained
  (:use #:cl #:%lui.fn)
  (:export #:draw))
(in-package #:lui.retained)

(defstruct renderer
  (arity 0 :type (integer 0 *))
  (container-p nil :type boolean)
  (function #'identity :type function))

(defvar *renderers* (make-hash-table :test #'eq))
(defvar *ancestors* nil)

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
                       value (not (functionp value)))
              (invalid-tree value "Event handlers must be functions or NIL.")))
  (values))

(fn (control-options list) ((options list))
  "Strip retained event handlers before passing options to LUI."
  (loop :for (key value) :on options :by #'cddr
        :unless (member key '(:on-change :on-activate))
          :append (list key value)))

(defmacro define-leaf (kind control arguments event)
  "Register a compiled adapter to a public LUI control macro."
  `(setf (gethash ,kind *renderers*)
         (make-renderer
          :arity ,(length arguments)
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
                         '(funcall callback value)
                         '(funcall callback))))))))))

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
Load the optional lui/retained system. TREE is a list of nodes, for example
((:button \"hello\") (:label \"hi\")). Leaves contain a kind, the ordinary LUI
positional arguments, then keyword options. Containers contain a kind, an
options plist, and child nodes: (:column (:gap 1) (:label \"Hello\")).
Store and edit TREE between frames, or reconstruct it each time. No forms are
evaluated and TREE is never modified by DRAW. LUI retains control values and
focus. Use :ID on moving siblings; unkeyed nodes have positional identity.
Changing a node kind resets its control identity. Use distinct DRAW :ID values
for multiple trees in one parent scope. Removed controls lose LUI owned state.
:ON-ACTIVATE takes a zero-argument function; :ON-CHANGE takes a function of the
new value. Callbacks run synchronously during drawing; edit the tree between
frames, not during traversal. :VALUE and :DEFAULT-VALUE follow LUI semantics.
This layer replays declarations every frame; it does not cache solved layout."
  (lui:call-with-key id (lambda () (draw-children tree)))
  (values))
