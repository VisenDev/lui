(defpackage #:lui.retained
  (:use #:cl #:%lui.fn)
  (:export
   #:draw #:node #:node-p
   #:nodes #:+unspecified+ #:node-kind
   #:node-id #:node-children #:node-on-activate
   #:node-on-change #:node-text #:node-choice
   #:node-choices #:node-fraction #:node-commands
   #:node-width #:node-height #:node-padding
   #:node-position #:node-offset-x #:node-offset-y
   #:node-flow #:node-align #:node-cross-align
   #:node-clip-p #:node-scroll-p #:node-scrollbar-p
   #:node-scrollbar-width #:node-interactive-p #:node-keyboard-focus-p
   #:node-pointer-focus-p #:node-foreground #:node-background
   #:node-palette #:node-radius #:node-frost
   #:node-font-size #:node-font-family #:node-font-weight
   #:node-opacity #:node-accent #:node-painter
   #:node-terminal-label #:node-terminal-border #:node-accessible-name
   #:node-value #:node-default-value #:node-disabled-p
   #:node-selected-p #:node-gap #:node-direction
   #:node-column-gap #:node-column-span #:node-minimum
   #:node-maximum #:node-step #:node-placeholder
   #:node-password-p #:node-max-results))
(in-package #:lui.retained)

(defstruct (unspecified (:constructor make-unspecified ()) (:copier nil))
  "Marker distinguishing an omitted option from an explicitly supplied NIL.")

(defvar +unspecified+ (make-unspecified)
  "Assign this marker to an option slot to restore toolkit/default behavior.
For NODE-VALUE it restores LUI-owned state. Do not rebind this variable.")

(defstruct (node
             (:constructor node
                 (kind &key (id nil)
                  (children (make-array 0 :element-type 'node))
                  (on-activate nil) (on-change nil)
                  (text +unspecified+)
                  (choice +unspecified+)
                  (choices +unspecified+)
                  (fraction +unspecified+)
                  (commands +unspecified+)
                  (width +unspecified+)
                  (height +unspecified+)
                  (padding +unspecified+)
                  (position +unspecified+)
                  (offset-x +unspecified+)
                  (offset-y +unspecified+)
                  (flow +unspecified+)
                  (align +unspecified+)
                  (cross-align +unspecified+)
                  (clip-p +unspecified+)
                  (scroll-p +unspecified+)
                  (scrollbar-p +unspecified+)
                  (scrollbar-width +unspecified+)
                  (interactive-p +unspecified+)
                  (keyboard-focus-p +unspecified+)
                  (pointer-focus-p +unspecified+)
                  (foreground +unspecified+)
                  (background +unspecified+)
                  (palette +unspecified+)
                  (radius +unspecified+)
                  (frost +unspecified+)
                  (font-size +unspecified+)
                  (font-family +unspecified+)
                  (font-weight +unspecified+)
                  (opacity +unspecified+)
                  (accent +unspecified+)
                  (painter +unspecified+)
                  (terminal-label +unspecified+)
                  (terminal-border +unspecified+)
                  (accessible-name +unspecified+)
                  (value +unspecified+)
                  (default-value +unspecified+)
                  (disabled-p +unspecified+)
                  (selected-p +unspecified+)
                  (gap +unspecified+)
                  (direction +unspecified+)
                  (column-gap +unspecified+)
                  (column-span +unspecified+)
                  (minimum +unspecified+)
                  (maximum +unspecified+)
                  (step +unspecified+)
                  (placeholder +unspecified+)
                  (password-p +unspecified+)
                  (max-results +unspecified+)))
             (:copier nil))
  "A mutable retained UI declaration, separate from frame-local layout.
Construct with (node :button :text \"Hello\" :on-activate 'hello).
Slots expose the control, layout and styling options for editor completion.
Mutate text with (setf (node-text label) \"Updated\") and editor values with
NODE-VALUE. +UNSPECIFIED+ means omitted; NIL is an explicit value.
KIND is fixed at construction. Unkeyed nodes use stable object identity; ID
allows separately constructed nodes to share identity in the same parent.
CHILDREN is a typed vector made by NODES. Nodes must not form cycles."
  (kind :label :type keyword :read-only t)
  (id nil :type lui:object-id)
  (children (make-array 0 :element-type 'node) :type (vector node))
  (on-activate nil :type (or function symbol))
  (on-change nil :type (or function symbol))
  (text +unspecified+ :type (or unspecified null string))
  (choice +unspecified+ :type t)
  (choices +unspecified+ :type (or unspecified null (vector string)))
  (fraction +unspecified+ :type (or unspecified null real))
  (commands +unspecified+ :type (or unspecified list))
  (width +unspecified+ :type (or unspecified null lui:sizing))
  (height +unspecified+ :type (or unspecified null lui:sizing))
  (padding +unspecified+ :type (or unspecified null real list))
  (position +unspecified+ :type (or unspecified null keyword))
  (offset-x +unspecified+ :type (or unspecified null real list))
  (offset-y +unspecified+ :type (or unspecified null real list))
  (flow +unspecified+ :type (or unspecified null keyword))
  (align +unspecified+ :type (or unspecified null keyword))
  (cross-align +unspecified+ :type (or unspecified null keyword))
  (clip-p +unspecified+ :type (or unspecified boolean))
  (scroll-p +unspecified+ :type (or unspecified boolean))
  (scrollbar-p +unspecified+ :type (or unspecified boolean))
  (scrollbar-width +unspecified+ :type (or unspecified null real))
  (interactive-p +unspecified+ :type (or unspecified boolean))
  (keyboard-focus-p +unspecified+ :type (or unspecified boolean))
  (pointer-focus-p +unspecified+ :type (or unspecified boolean))
  (foreground +unspecified+ :type (or unspecified null string))
  (background +unspecified+ :type (or unspecified null string))
  (palette +unspecified+ :type (or unspecified null lui:palette list symbol))
  (radius +unspecified+ :type (or unspecified null real list))
  (frost +unspecified+ :type (or unspecified null real))
  (font-size +unspecified+ :type (or unspecified null real list))
  (font-family +unspecified+ :type (or unspecified null keyword))
  (font-weight +unspecified+ :type (or unspecified null keyword))
  (opacity +unspecified+ :type (or unspecified null real))
  (accent +unspecified+ :type (or unspecified null string))
  (painter +unspecified+ :type (or unspecified null function))
  (terminal-label +unspecified+ :type (or unspecified null function))
  (terminal-border +unspecified+ :type (or unspecified null string))
  (accessible-name +unspecified+ :type (or unspecified null string))
  (value +unspecified+ :type t)
  (default-value +unspecified+ :type t)
  (disabled-p +unspecified+ :type (or unspecified boolean))
  (selected-p +unspecified+ :type (or unspecified boolean))
  (gap +unspecified+ :type (or unspecified null real list))
  (direction +unspecified+ :type (or unspecified null keyword))
  (column-gap +unspecified+ :type (or unspecified null real list))
  (column-span +unspecified+ :type (or unspecified null integer))
  (minimum +unspecified+ :type (or unspecified null real))
  (maximum +unspecified+ :type (or unspecified null real))
  (step +unspecified+ :type (or unspecified null real))
  (placeholder +unspecified+ :type (or unspecified null string))
  (password-p +unspecified+ :type (or unspecified boolean))
  (max-results +unspecified+ :type (or unspecified null integer)))

(fn (nodes (vector node)) (&rest (items list))
  "Make a typed node vector for DRAW or a container's CHILDREN slot."
  (make-array (length items) :element-type 'node :initial-contents items))

(defstruct renderer
  (container-p nil :type boolean)
  (function #'identity :type function))

(defvar *renderers* (make-hash-table :test #'eq))
(defvar *ancestors* nil)
(defvar *callbacks* nil)

(fn (invalid-tree (values)) ((value t) (message string))
  "Signal a configuration error for an invalid retained declaration."
  (error 'lui:configuration-error :operation :retained-draw
         :setting :tree :value value :format-control "~A"
         :format-arguments (list message)))

(fn (option-value t) ((value t))
  "Resolve a spacing descriptor without evaluating Lisp forms."
  (cond
    ((and (consp value) (eq (first value) :units))
     (unless (and (consp (cdr value)) (null (cddr value))
                  (realp (second value)))
       (invalid-tree value "Expected (:units NUMBER)."))
     (lui:units (second value)))

    (t value)))

(defmacro collect-options (node &rest names)
  "Read typed option slots directly and omit only the unspecified marker."
  `(let ((options nil))
     ,@(loop :for name :in names
             :for reader := (intern (format nil "NODE-~A" name))
             :for key := (intern (symbol-name name) :keyword)
             :collect
             `(let ((value (,reader ,node)))
                (unless (eq value +unspecified+)
                  (setf options
                        (list* ,key
                               ,(if (member name '(padding gap column-gap
                                                  offset-x offset-y radius
                                                  font-size))
                                    '(option-value value) 'value)
                               options)))))
     options))

(fn (control-options list) ((node node))
  "Build the immediate control's options from slots, preserving explicit NIL."
  (let ((options
          (collect-options node
            width height padding position offset-x offset-y
            flow align cross-align clip-p scroll-p scrollbar-p
            scrollbar-width interactive-p keyboard-focus-p pointer-focus-p
            foreground background
            palette radius frost font-size font-family font-weight
            opacity accent painter terminal-label terminal-border
            accessible-name
            value default-value disabled-p selected-p gap direction
            column-gap column-span minimum maximum step placeholder
            password-p max-results)))
    (when (node-id node)
      (setf options (list* :id (node-id node) options)))
    (when (and (eq (node-kind node) :slider)
               (not (eq (node-text node) +unspecified+)))
      (setf options (list* :text (node-text node) options)))
    options))

(fn (required-argument t) ((value t) (node node))
  "Reject omitted positional control data before calling the immediate API."
  (when (eq value +unspecified+)
    (invalid-tree node "Missing required control data slot."))
  value)

(fn (invoke-callback (values))
    ((callback (or function symbol)) (arguments list))
  "Resolve a symbol at dispatch time so redefinitions affect existing nodes."
  (apply (if (symbolp callback) (symbol-function callback) callback)
         arguments)
  (values))

(defmacro define-leaf (kind control arguments event)
  "Register a compiled adapter that reads its positional data directly."
  `(setf (gethash ,kind *renderers*)
         (make-renderer
          :function
          (lambda (node)
            (multiple-value-bind (value changed)
                (,control
                 ,@(mapcar (lambda (name)
                             `(required-argument
                               (,(intern (format nil "NODE-~A" name)) node)
                               node))
                           arguments)
                 :options (control-options node))
              (declare (ignorable value changed))
              ,(when event
                 `(let ((callback
                          (,(if (eq event :on-change)
                                'node-on-change 'node-on-activate) node)))
                    (when (and callback ,(if (eq event :on-change)
                                            'changed 'value))
                      (push (lambda ()
                              (invoke-callback
                               callback ,(when (eq event :on-change)
                                           '(list value))))
                            *callbacks*)))))))))

(defmacro define-container (kind control)
  "Register a container adapter over the node's typed child vector."
  `(setf (gethash ,kind *renderers*)
         (make-renderer
          :container-p t
          :function (lambda (node)
                      (,control (:options (control-options node))
                        (draw-children (node-children node)))))))

(fn (draw-node (values)) ((node node) (seen hash-table))
  "Validate identity and ancestry, then declare one retained node."
  (let ((renderer (gethash (node-kind node) *renderers*))
        (key (if (node-id node)
                 (list :key (node-id node))
                 node)))
    (unless renderer (invalid-tree node "Unknown retained control kind."))
    (when (member node *ancestors* :test #'eq)
      (invalid-tree node "Container children must not contain an ancestor."))
    (when (and (not (renderer-container-p renderer))
               (plusp (length (node-children node))))
      (invalid-tree node "Only containers accept children."))
    (when (gethash key seen)
      (invalid-tree node "Duplicate sibling identity."))
    (setf (gethash key seen) t)
    (lui:call-with-key
     key (lambda ()
           (let ((*ancestors* (cons node *ancestors*)))
             (funcall (renderer-function renderer) node)))))
  (values))

(fn (draw-children (values)) ((children (vector node)))
  "Traverse typed child references without decoding list nodes."
  (let ((seen (make-hash-table :test #'equal)))
    (loop :for node :across children :do (draw-node node seen)))
  (values))

(define-leaf :label lui:label (text) nil)
(define-leaf :button lui:button (text) :on-activate)
(define-leaf :checkbox lui:checkbox (text) :on-change)
(define-leaf :radio lui:radio (choice text) :on-change)
(define-leaf :slider lui:slider () :on-change)
(define-leaf :text-field lui:text-field () :on-change)
(define-leaf :date-picker lui:date-picker () :on-change)
(define-leaf :searchable-combobox lui:searchable-combobox
  (choices) :on-change)
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

(fn (draw (values))
    ((tree (or node (vector node))) &key ((id lui:object-id) :retained))
  "Declare a retained node or typed node vector inside the current LUI frame.
Create data with NODE and NODES; edit it through standard SETF slot accessors.
The former list-node format is not supported. A stored node keeps its identity
when reordered within its parent. Supply :ID when reconstructing nodes; explicit
keys must be stable and unique among siblings. Reusing a node twice in one
parent is an error. Containers scope child identities; moving to another parent
starts new LUI state. Removed nodes lose owned state after a completed frame.
NODE-VALUE defaults to +UNSPECIFIED+ (LUI-owned state). Assigning any other
value, including NIL, makes it controlled; NODE-DEFAULT-VALUE initializes
owned state. Set an option slot back to +UNSPECIFIED+ to restore its default.
Spacing slots accept (:units NUMBER), resolved for the active backend.
Callbacks may be functions or symbols, resolved with SYMBOL-FUNCTION when
invoked. On-activate receives no arguments; on-change receives the new value.
Callbacks run in traversal order after successful declaration, before DRAW
returns, and DRAW requests another frame. They may mutate slots or replace
child vectors; changes appear next frame. Traversal failures discard callbacks.
Callback errors stop dispatch without rolling back earlier edits. Use distinct
DRAW :ID values for multiple roots in the same parent scope. DRAW still solves
layout each frame; it does not cache layouts or automatically bind model data."
  (let ((*callbacks* nil))
    (lui:call-with-key
     id (lambda ()
          (if (node-p tree)
              (draw-node tree (make-hash-table :test #'equal))
              ;; else
              (draw-children tree))))
    (when *callbacks*
      (lui:request-frame)
      (dolist (callback (nreverse *callbacks*)) (funcall callback))))
  (values))
