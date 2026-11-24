(defpackage #:lui.retained
  (:use #:cl #:%lui.fn)
  (:export
   #:draw #:node #:node-p #:+unspecified+ #:node-id #:node-width
   #:node-height #:node-padding #:node-position #:node-offset-x
   #:node-offset-y #:label #:make-label #:label-p #:label-id #:label-width
   #:label-height #:label-padding #:label-position #:label-offset-x
   #:label-offset-y #:label-foreground #:label-background #:label-palette
   #:label-radius #:label-frost #:label-font-size #:label-font-family
   #:label-font-weight #:label-opacity #:label-accent #:label-painter
   #:label-terminal-label #:label-terminal-border #:label-accessible-name
   #:label-text #:label-disabled-p #:button #:make-button #:button-p
   #:button-id #:button-width #:button-height #:button-padding
   #:button-position #:button-offset-x #:button-offset-y #:button-foreground
   #:button-background #:button-palette #:button-radius #:button-frost
   #:button-font-size #:button-font-family #:button-font-weight
   #:button-opacity #:button-accent #:button-painter #:button-terminal-label
   #:button-terminal-border #:button-accessible-name #:button-text
   #:button-on-activate #:button-disabled-p #:checkbox #:make-checkbox
   #:checkbox-p #:checkbox-id #:checkbox-width #:checkbox-height
   #:checkbox-padding #:checkbox-position #:checkbox-offset-x
   #:checkbox-offset-y #:checkbox-foreground #:checkbox-background
   #:checkbox-palette #:checkbox-radius #:checkbox-frost #:checkbox-font-size
   #:checkbox-font-family #:checkbox-font-weight #:checkbox-opacity
   #:checkbox-accent #:checkbox-painter #:checkbox-terminal-label
   #:checkbox-terminal-border #:checkbox-accessible-name #:checkbox-text
   #:checkbox-on-change #:checkbox-value #:checkbox-default-value
   #:checkbox-disabled-p #:radio #:make-radio #:radio-p #:radio-id
   #:radio-width #:radio-height #:radio-padding #:radio-position
   #:radio-offset-x #:radio-offset-y #:radio-foreground #:radio-background
   #:radio-palette #:radio-radius #:radio-frost #:radio-font-size
   #:radio-font-family #:radio-font-weight #:radio-opacity #:radio-accent
   #:radio-painter #:radio-terminal-label #:radio-terminal-border
   #:radio-accessible-name #:radio-choice #:radio-text #:radio-on-change
   #:radio-value #:radio-default-value #:radio-disabled-p #:slider
   #:make-slider #:slider-p #:slider-id #:slider-width #:slider-height
   #:slider-padding #:slider-position #:slider-offset-x #:slider-offset-y
   #:slider-foreground #:slider-background #:slider-palette #:slider-radius
   #:slider-frost #:slider-font-size #:slider-font-family
   #:slider-font-weight #:slider-opacity #:slider-accent #:slider-painter
   #:slider-terminal-label #:slider-terminal-border #:slider-accessible-name
   #:slider-on-change #:slider-value #:slider-default-value
   #:slider-disabled-p #:slider-minimum #:slider-maximum #:slider-step
   #:slider-text #:text-field #:make-text-field #:text-field-p
   #:text-field-id #:text-field-width #:text-field-height
   #:text-field-padding #:text-field-position #:text-field-offset-x
   #:text-field-offset-y #:text-field-foreground #:text-field-background
   #:text-field-palette #:text-field-radius #:text-field-frost
   #:text-field-font-size #:text-field-font-family #:text-field-font-weight
   #:text-field-opacity #:text-field-accent #:text-field-painter
   #:text-field-terminal-label #:text-field-terminal-border
   #:text-field-accessible-name #:text-field-on-change #:text-field-value
   #:text-field-default-value #:text-field-disabled-p
   #:text-field-placeholder #:text-field-password-p #:date-picker
   #:make-date-picker #:date-picker-p #:date-picker-id #:date-picker-width
   #:date-picker-height #:date-picker-padding #:date-picker-position
   #:date-picker-offset-x #:date-picker-offset-y #:date-picker-foreground
   #:date-picker-background #:date-picker-palette #:date-picker-radius
   #:date-picker-frost #:date-picker-font-size #:date-picker-font-family
   #:date-picker-font-weight #:date-picker-opacity #:date-picker-accent
   #:date-picker-painter #:date-picker-terminal-label
   #:date-picker-terminal-border #:date-picker-accessible-name
   #:date-picker-on-change #:date-picker-value #:date-picker-default-value
   #:searchable-combobox #:make-searchable-combobox #:searchable-combobox-p
   #:searchable-combobox-id #:searchable-combobox-width
   #:searchable-combobox-height #:searchable-combobox-padding
   #:searchable-combobox-position #:searchable-combobox-offset-x
   #:searchable-combobox-offset-y #:searchable-combobox-foreground
   #:searchable-combobox-background #:searchable-combobox-palette
   #:searchable-combobox-radius #:searchable-combobox-frost
   #:searchable-combobox-font-size #:searchable-combobox-font-family
   #:searchable-combobox-font-weight #:searchable-combobox-opacity
   #:searchable-combobox-accent #:searchable-combobox-painter
   #:searchable-combobox-terminal-label #:searchable-combobox-terminal-border
   #:searchable-combobox-accessible-name #:searchable-combobox-choices
   #:searchable-combobox-on-change #:searchable-combobox-value
   #:searchable-combobox-default-value #:searchable-combobox-disabled-p
   #:searchable-combobox-placeholder #:searchable-combobox-max-results
   #:searchable-combobox-password-p #:gauge #:make-gauge #:gauge-p #:gauge-id
   #:gauge-width #:gauge-height #:gauge-padding #:gauge-position
   #:gauge-offset-x #:gauge-offset-y #:gauge-foreground #:gauge-background
   #:gauge-palette #:gauge-radius #:gauge-frost #:gauge-font-size
   #:gauge-font-family #:gauge-font-weight #:gauge-opacity #:gauge-accent
   #:gauge-painter #:gauge-terminal-label #:gauge-terminal-border
   #:gauge-accessible-name #:gauge-fraction #:gauge-disabled-p #:spinner
   #:make-spinner #:spinner-p #:spinner-id #:spinner-width #:spinner-height
   #:spinner-padding #:spinner-position #:spinner-offset-x #:spinner-offset-y
   #:spinner-foreground #:spinner-background #:spinner-palette
   #:spinner-radius #:spinner-frost #:spinner-font-size #:spinner-font-family
   #:spinner-font-weight #:spinner-opacity #:spinner-accent #:spinner-painter
   #:spinner-terminal-label #:spinner-terminal-border
   #:spinner-accessible-name #:spinner-disabled-p #:spacer #:make-spacer
   #:spacer-p #:spacer-id #:spacer-width #:spacer-height #:spacer-padding
   #:spacer-position #:spacer-offset-x #:spacer-offset-y #:hr #:make-hr
   #:hr-p #:hr-id #:hr-width #:hr-height #:hr-padding #:hr-position
   #:hr-offset-x #:hr-offset-y #:hr-foreground #:hr-background #:hr-palette
   #:hr-radius #:hr-frost #:hr-font-size #:hr-font-family #:hr-font-weight
   #:hr-opacity #:hr-accent #:hr-painter #:hr-terminal-label
   #:hr-terminal-border #:hr-accessible-name #:hr-disabled-p #:vr #:make-vr
   #:vr-p #:vr-id #:vr-width #:vr-height #:vr-padding #:vr-position
   #:vr-offset-x #:vr-offset-y #:vr-foreground #:vr-background #:vr-palette
   #:vr-radius #:vr-frost #:vr-font-size #:vr-font-family #:vr-font-weight
   #:vr-opacity #:vr-accent #:vr-painter #:vr-terminal-label
   #:vr-terminal-border #:vr-accessible-name #:vr-disabled-p #:cell
   #:make-cell #:cell-p #:cell-id #:cell-width #:cell-height #:cell-padding
   #:cell-position #:cell-offset-x #:cell-offset-y #:cell-foreground
   #:cell-background #:cell-palette #:cell-radius #:cell-frost
   #:cell-font-size #:cell-font-family #:cell-font-weight #:cell-opacity
   #:cell-accent #:cell-painter #:cell-terminal-label #:cell-terminal-border
   #:cell-accessible-name #:cell-text #:cell-on-activate #:cell-disabled-p
   #:cell-selected-p #:list-item #:make-list-item #:list-item-p
   #:list-item-id #:list-item-width #:list-item-height #:list-item-padding
   #:list-item-position #:list-item-offset-x #:list-item-offset-y
   #:list-item-foreground #:list-item-background #:list-item-palette
   #:list-item-radius #:list-item-frost #:list-item-font-size
   #:list-item-font-family #:list-item-font-weight #:list-item-opacity
   #:list-item-accent #:list-item-painter #:list-item-terminal-label
   #:list-item-terminal-border #:list-item-accessible-name #:list-item-text
   #:list-item-on-activate #:list-item-disabled-p #:list-item-selected-p
   #:tab #:make-tab #:tab-p #:tab-id #:tab-width #:tab-height #:tab-padding
   #:tab-position #:tab-offset-x #:tab-offset-y #:tab-foreground
   #:tab-background #:tab-palette #:tab-radius #:tab-frost #:tab-font-size
   #:tab-font-family #:tab-font-weight #:tab-opacity #:tab-accent
   #:tab-painter #:tab-terminal-label #:tab-terminal-border
   #:tab-accessible-name #:tab-text #:tab-on-activate #:tab-disabled-p
   #:tab-selected-p #:canvas #:make-canvas #:canvas-p #:canvas-id
   #:canvas-width #:canvas-height #:canvas-padding #:canvas-position
   #:canvas-offset-x #:canvas-offset-y #:canvas-foreground
   #:canvas-background #:canvas-palette #:canvas-radius #:canvas-frost
   #:canvas-font-size #:canvas-font-family #:canvas-font-weight
   #:canvas-opacity #:canvas-accent #:canvas-painter #:canvas-terminal-label
   #:canvas-terminal-border #:canvas-accessible-name #:canvas-commands
   #:canvas-disabled-p #:row #:make-row #:row-p #:row-id #:row-width
   #:row-height #:row-padding #:row-position #:row-offset-x #:row-offset-y
   #:row-align #:row-cross-align #:row-clip-p #:row-scroll-p
   #:row-scrollbar-p #:row-scrollbar-width #:row-interactive-p
   #:row-keyboard-focus-p #:row-pointer-focus-p #:row-children #:row-gap
   #:column #:make-column #:column-p #:column-id #:column-width
   #:column-height #:column-padding #:column-position #:column-offset-x
   #:column-offset-y #:column-align #:column-cross-align #:column-clip-p
   #:column-scroll-p #:column-scrollbar-p #:column-scrollbar-width
   #:column-interactive-p #:column-keyboard-focus-p #:column-pointer-focus-p
   #:column-children #:column-gap #:panel #:make-panel #:panel-p #:panel-id
   #:panel-width #:panel-height #:panel-padding #:panel-position
   #:panel-offset-x #:panel-offset-y #:panel-align #:panel-cross-align
   #:panel-clip-p #:panel-scroll-p #:panel-scrollbar-p
   #:panel-scrollbar-width #:panel-interactive-p #:panel-keyboard-focus-p
   #:panel-pointer-focus-p #:panel-children #:panel-foreground
   #:panel-background #:panel-palette #:panel-radius #:panel-frost
   #:panel-font-size #:panel-font-family #:panel-font-weight #:panel-opacity
   #:panel-accent #:panel-painter #:panel-terminal-label
   #:panel-terminal-border #:panel-accessible-name #:panel-gap
   #:panel-direction #:table #:make-table #:table-p #:table-id #:table-width
   #:table-height #:table-padding #:table-position #:table-offset-x
   #:table-offset-y #:table-align #:table-cross-align #:table-clip-p
   #:table-scroll-p #:table-scrollbar-p #:table-scrollbar-width
   #:table-interactive-p #:table-keyboard-focus-p #:table-pointer-focus-p
   #:table-children #:table-gap #:table-column-gap #:table-row
   #:make-table-row #:table-row-p #:table-row-id #:table-row-width
   #:table-row-height #:table-row-padding #:table-row-position
   #:table-row-offset-x #:table-row-offset-y #:table-row-align
   #:table-row-cross-align #:table-row-clip-p #:table-row-scroll-p
   #:table-row-scrollbar-p #:table-row-scrollbar-width
   #:table-row-interactive-p #:table-row-keyboard-focus-p
   #:table-row-pointer-focus-p #:table-row-children #:table-cell
   #:make-table-cell #:table-cell-p #:table-cell-id #:table-cell-width
   #:table-cell-height #:table-cell-padding #:table-cell-position
   #:table-cell-offset-x #:table-cell-offset-y #:table-cell-align
   #:table-cell-cross-align #:table-cell-clip-p #:table-cell-scroll-p
   #:table-cell-scrollbar-p #:table-cell-scrollbar-width
   #:table-cell-interactive-p #:table-cell-keyboard-focus-p
   #:table-cell-pointer-focus-p #:table-cell-children #:table-cell-gap
   #:table-cell-column-span))
(in-package #:lui.retained)

(defstruct (unspecified (:constructor make-unspecified ()) (:copier nil))
  "Marker distinguishing an omitted option from an explicitly supplied NIL.")

(defvar +unspecified+ (make-unspecified)
  "Assign this marker to an option slot to restore toolkit/default behavior.
For a control's VALUE slot it restores LUI-owned state. Do not rebind it.")

(defstruct (node (:constructor nil)
             (:copier nil))
  "Shared identity and placement for retained widgets; no public constructor.
Use MAKE-LABEL, MAKE-BUTTON, MAKE-TEXT-FIELD or another widget constructor.
Stored objects keep identity across mutation and sibling reordering.
ID keys allow rebuilding."
  (id nil :type lui:object-id)
  (width +unspecified+ :type (or unspecified null lui:sizing))
  (height +unspecified+ :type (or unspecified null lui:sizing))
  (padding +unspecified+ :type (or unspecified null real list))
  (position +unspecified+ :type (or unspecified null keyword))
  (offset-x +unspecified+ :type (or unspecified null real list))
  (offset-y +unspecified+ :type (or unspecified null real list)))

(defstruct (styled-node (:include node) (:constructor nil)
             (:copier nil))
  "Shared appearance slots for painted retained widgets."
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
  (accessible-name +unspecified+ :type (or unspecified null string)))

(defstruct (container-node (:include node) (:constructor nil)
             (:copier nil))
  "Shared layout and child storage for retained containers."
  (align +unspecified+ :type (or unspecified null keyword))
  (cross-align +unspecified+ :type (or unspecified null keyword))
  (clip-p +unspecified+ :type (or unspecified boolean))
  (scroll-p +unspecified+ :type (or unspecified boolean))
  (scrollbar-p +unspecified+ :type (or unspecified boolean))
  (scrollbar-width +unspecified+ :type (or unspecified null real))
  (interactive-p +unspecified+ :type (or unspecified boolean))
  (keyboard-focus-p +unspecified+ :type (or unspecified boolean))
  (pointer-focus-p +unspecified+ :type (or unspecified boolean))
  (children (make-array 0 :element-type 'node) :type (vector node)))

(defstruct (label (:include styled-node) (:copier nil))
  "A retained label; see DRAW for mutation, identity and callback rules."
  (text +unspecified+ :type (or unspecified null string))
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (button (:include styled-node) (:copier nil))
  "A retained button; see DRAW for mutation, identity and callback rules."
  (text +unspecified+ :type (or unspecified null string))
  (on-activate nil :type (or function symbol))
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (checkbox (:include styled-node) (:copier nil))
  "A retained checkbox; see DRAW for mutation, identity and callback rules."
  (text +unspecified+ :type (or unspecified null string))
  (on-change nil :type (or function symbol))
  (value +unspecified+ :type t)
  (default-value +unspecified+ :type t)
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (radio (:include styled-node) (:copier nil))
  "A retained radio; see DRAW for mutation, identity and callback rules."
  (choice +unspecified+ :type t)
  (text +unspecified+ :type (or unspecified null string))
  (on-change nil :type (or function symbol))
  (value +unspecified+ :type t)
  (default-value +unspecified+ :type t)
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (slider (:include styled-node) (:copier nil))
  "A retained slider; see DRAW for mutation, identity and callback rules."
  (on-change nil :type (or function symbol))
  (value +unspecified+ :type t)
  (default-value +unspecified+ :type t)
  (disabled-p +unspecified+ :type (or unspecified boolean))
  (minimum +unspecified+ :type (or unspecified null real))
  (maximum +unspecified+ :type (or unspecified null real))
  (step +unspecified+ :type (or unspecified null real))
  (text +unspecified+ :type (or unspecified null string)))

(defstruct (text-field (:include styled-node) (:copier nil))
  "A retained text-field; see DRAW for mutation, identity and callback rules."
  (on-change nil :type (or function symbol))
  (value +unspecified+ :type t)
  (default-value +unspecified+ :type t)
  (disabled-p +unspecified+ :type (or unspecified boolean))
  (placeholder +unspecified+ :type (or unspecified null string))
  (password-p +unspecified+ :type (or unspecified boolean)))

(defstruct (date-picker (:include styled-node) (:copier nil))
  "A retained date-picker; see DRAW for mutation, identity and callback rules."
  (on-change nil :type (or function symbol))
  (value +unspecified+ :type t)
  (default-value +unspecified+ :type t))

(defstruct (searchable-combobox (:include styled-node) (:copier nil))
  "A retained searchable-combobox; see DRAW for mutation, identity and callback rules."
  (choices +unspecified+ :type (or unspecified null (vector string)))
  (on-change nil :type (or function symbol))
  (value +unspecified+ :type t)
  (default-value +unspecified+ :type t)
  (disabled-p +unspecified+ :type (or unspecified boolean))
  (placeholder +unspecified+ :type (or unspecified null string))
  (max-results +unspecified+ :type (or unspecified null integer))
  (password-p +unspecified+ :type (or unspecified boolean)))

(defstruct (gauge (:include styled-node) (:copier nil))
  "A retained gauge; see DRAW for mutation, identity and callback rules."
  (fraction +unspecified+ :type (or unspecified null real))
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (spinner (:include styled-node) (:copier nil))
  "A retained spinner; see DRAW for mutation, identity and callback rules."
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (spacer (:include node) (:copier nil))
  "A retained spacer; see DRAW for mutation, identity and callback rules.")

(defstruct (hr (:include styled-node) (:copier nil))
  "A retained hr; see DRAW for mutation, identity and callback rules."
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (vr (:include styled-node) (:copier nil))
  "A retained vr; see DRAW for mutation, identity and callback rules."
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (cell (:include styled-node) (:copier nil))
  "A retained cell; see DRAW for mutation, identity and callback rules."
  (text +unspecified+ :type (or unspecified null string))
  (on-activate nil :type (or function symbol))
  (disabled-p +unspecified+ :type (or unspecified boolean))
  (selected-p +unspecified+ :type (or unspecified boolean)))

(defstruct (list-item (:include styled-node) (:copier nil))
  "A retained list-item; see DRAW for mutation, identity and callback rules."
  (text +unspecified+ :type (or unspecified null string))
  (on-activate nil :type (or function symbol))
  (disabled-p +unspecified+ :type (or unspecified boolean))
  (selected-p +unspecified+ :type (or unspecified boolean)))

(defstruct (tab (:include styled-node) (:copier nil))
  "A retained tab; see DRAW for mutation, identity and callback rules."
  (text +unspecified+ :type (or unspecified null string))
  (on-activate nil :type (or function symbol))
  (disabled-p +unspecified+ :type (or unspecified boolean))
  (selected-p +unspecified+ :type (or unspecified boolean)))

(defstruct (canvas (:include styled-node) (:copier nil))
  "A retained canvas; see DRAW for mutation, identity and callback rules."
  (commands +unspecified+ :type (or unspecified list))
  (disabled-p +unspecified+ :type (or unspecified boolean)))

(defstruct (row (:include container-node) (:copier nil))
  "A retained row container with a CHILDREN vector made by CL:VECTOR.
Edit children with (SETF ROW-CHILDREN); see DRAW for identity rules."
  (gap +unspecified+ :type (or unspecified null real list)))

(defstruct (column (:include container-node) (:copier nil))
  "A retained column container with a CHILDREN vector made by CL:VECTOR.
Edit children with (SETF COLUMN-CHILDREN); see DRAW for identity rules."
  (gap +unspecified+ :type (or unspecified null real list)))

(defstruct (panel (:include container-node) (:copier nil))
  "A retained panel container with a CHILDREN vector made by CL:VECTOR.
Edit children with (SETF PANEL-CHILDREN); see DRAW for identity rules."
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
  (gap +unspecified+ :type (or unspecified null real list))
  (direction +unspecified+ :type (or unspecified null keyword)))

(defstruct (table (:include container-node) (:copier nil))
  "A retained table container with a CHILDREN vector made by CL:VECTOR.
Edit children with (SETF TABLE-CHILDREN); see DRAW for identity rules."
  (gap +unspecified+ :type (or unspecified null real list))
  (column-gap +unspecified+ :type (or unspecified null real list)))

(defstruct (table-row (:include container-node) (:copier nil))
  "A retained table-row container with a CHILDREN vector made by CL:VECTOR.
Edit children with (SETF TABLE-ROW-CHILDREN); see DRAW for identity rules.")

(defstruct (table-cell (:include container-node) (:copier nil))
  "A retained table-cell container with a CHILDREN vector made by CL:VECTOR.
Edit children with (SETF TABLE-CELL-CHILDREN); see DRAW for identity rules."
  (gap +unspecified+ :type (or unspecified null real list))
  (column-span +unspecified+ :type (or unspecified null integer)))

(defvar *renderers* (make-hash-table :test #'eq))
(defvar *ancestors* nil)
(defvar *callbacks* nil)

(defstruct sibling-scope
  (seen (make-hash-table :test #'equal) :type hash-table)
  (children nil :type (or null sibling-scope)))

(defvar *sibling-scope*)

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

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *option-groups*
    '((placement id width height padding position offset-x offset-y)
      (appearance foreground background palette radius frost font-size
                  font-family font-weight opacity accent painter terminal-label
                  terminal-border accessible-name)
      (container align cross-align clip-p scroll-p scrollbar-p scrollbar-width
                 interactive-p keyboard-focus-p pointer-focus-p)
      (value value default-value))
    "Shared slot sets used by retained renderer adapters."))

(defmacro collect-options (node prefix groups &rest names)
  "Read only this widget type's option slots, preserving explicit NIL."
  `(let ((options nil))
     ,@(loop :for name :in (append
                           (loop :for group :in groups
                                 :append (cdr (assoc group *option-groups*)))
                           names)
             :for reader := (intern (format nil "~A-~A" prefix name))
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

(defmacro define-leaf (name arguments event groups &rest options)
  "Register an adapter for a concrete leaf structure and its own slots."
  `(setf (gethash ',name *renderers*)
         (lambda (node)
           (declare (type ,name node))
           (multiple-value-bind (value changed)
               (,(intern (symbol-name name) :lui)
                ,@(mapcar (lambda (slot)
                            `(required-argument
                              (,(intern (format nil "~A-~A" name slot)) node)
                              node)) arguments)
                :options (collect-options node ,name ,groups ,@options))
             (declare (ignorable value changed))
             ,(when event
                `(let ((callback
                         (,(intern (format nil "~A-~A" name event)) node)))
                   (when (and callback ,(if (eq event 'on-change)
                                           'changed 'value))
                     (push (lambda ()
                             (invoke-callback
                              callback ,(when (eq event 'on-change)
                                          '(list value))))
                           *callbacks*))))))))

(defmacro define-container (name groups &rest options)
  "Register an adapter for a concrete container and its child vector."
  `(setf (gethash ',name *renderers*)
         (lambda (node)
           (declare (type ,name node))
           (,(intern (symbol-name name) :lui)
            (:options (collect-options node ,name ,groups ,@options))
            (draw-children
             (,(intern (format nil "~A-CHILDREN" name)) node))))))

(fn (draw-node (values)) ((node node))
  "Validate identity and ancestry, then declare one retained node."
  (let* ((seen (sibling-scope-seen *sibling-scope*))
         (renderer (gethash (type-of node) *renderers*))
         (key (or (node-id node) node))
         (namespace (if (node-id node) :explicit :object))
         (previous (gethash key seen)))
    (unless renderer (invalid-tree node "Unknown retained control kind."))
    (when (member node *ancestors* :test #'eq)
      (invalid-tree node "Container children must not contain an ancestor."))
    ;; An explicit key may itself be an unkeyed sibling's node object.
    ;; Track both namespaces without allocating a tagged key per declaration.
    (when (or (eq previous namespace) (eq previous :both))
      (invalid-tree node "Duplicate sibling identity."))
    (setf (gethash key seen) (if previous :both namespace))
    (let ((*ancestors* (cons node *ancestors*)))
      (if (node-id node)
          ;; Explicit IDs already inherit their parent's identity in core.
          (funcall renderer node)
          ;; else
          (lui:call-with-key node (lambda () (funcall renderer node))))))
  (values))

(fn (draw-children (values)) ((children (vector node)))
  "Reuse a sibling identity table at each depth within the current DRAW."
  (when (plusp (length children))
    (let ((*sibling-scope*
            (or (sibling-scope-children *sibling-scope*)
                (setf (sibling-scope-children *sibling-scope*)
                      (make-sibling-scope)))))
      (clrhash (sibling-scope-seen *sibling-scope*))
      (loop :for node :across children :do (draw-node node))))
  (values))

(define-leaf label (text) nil (placement appearance) disabled-p)
(define-leaf button (text) on-activate (placement appearance) disabled-p)
(define-leaf checkbox (text) on-change (placement appearance value)
  disabled-p)
(define-leaf radio (choice text) on-change (placement appearance value)
  disabled-p)
(define-leaf slider () on-change (placement appearance value)
  disabled-p minimum maximum step text)
(define-leaf text-field () on-change (placement appearance value)
  disabled-p placeholder password-p)
(define-leaf date-picker () on-change (placement appearance value))
(define-leaf searchable-combobox (choices) on-change (placement appearance value)
  disabled-p placeholder max-results password-p)
(define-leaf gauge (fraction) nil (placement appearance) disabled-p)
(define-leaf spinner () nil (placement appearance) disabled-p)
(define-leaf spacer () nil (placement))
(define-leaf hr () nil (placement appearance) disabled-p)
(define-leaf vr () nil (placement appearance) disabled-p)
(define-leaf cell (text) on-activate (placement appearance)
  disabled-p selected-p)
(define-leaf list-item (text) on-activate (placement appearance)
  disabled-p selected-p)
(define-leaf tab (text) on-activate (placement appearance)
  disabled-p selected-p)
(define-leaf canvas (commands) nil (placement appearance) disabled-p)
(define-container row (placement container) gap)
(define-container column (placement container) gap)
(define-container panel (placement container appearance) gap direction)
(define-container table (placement container) gap column-gap)
(define-container table-row (placement container))
(define-container table-cell (placement container) gap column-span)

(fn (draw (values))
    ((tree (or node (vector node))) &key ((id lui:object-id) :retained))
  "Declare a retained node or typed node vector inside the current LUI frame.
Create data with MAKE-LABEL, MAKE-BUTTON, MAKE-COLUMN and other constructors.
Use CL:VECTOR for child vectors and widget-specific SETF accessors for mutation.
The former list-node format is not supported. A stored node keeps its identity
when reordered within its parent. Supply :ID when reconstructing nodes; explicit
keys must be stable and unique among siblings. Reusing a node twice in one
parent is an error. Containers scope child identities; moving to another parent
starts new LUI state. Removed nodes lose owned state after a completed frame.
A control's VALUE slot defaults to +UNSPECIFIED+ (LUI-owned state). Any other
value, including NIL, makes it controlled; DEFAULT-VALUE initializes
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
  (let ((*callbacks* nil)
        (*sibling-scope* (make-sibling-scope)))
    (lui:call-with-key
     id (lambda ()
          (if (node-p tree)
              (draw-node tree)
              ;; else
              (loop :for node :across tree :do (draw-node node)))))
    (when *callbacks*
      (lui:request-frame)
      (dolist (callback (nreverse *callbacks*)) (funcall callback))))
  (values))
