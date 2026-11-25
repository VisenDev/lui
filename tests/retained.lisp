(defpackage #:%lui.tests.retained
  (:use #:cl)
  (:export #:run-tests))
(in-package #:%lui.tests.retained)

(defun frame (context tree &optional events)
  (lui:with-frame (context 100 60 :events events)
    (lui.retained:draw tree)))

(defun element-with-value (context value)
  (let ((found nil))
    (%lui.layout:walk-elements
     (%lui.frame:context-root context)
     (lambda (element)
       (let ((widget (%lui.layout:element-content element)))
         (when (and (%lui.widgets:widget-p widget)
                    (or (equal value (%lui.widgets:widget-value widget))
                        (equal value (%lui.widgets:widget-text widget))))
           (setf found element)))))
    (assert found)
    found))

(defun retained-id (key context)
  (lui:with-key :retained
    (lui:widget-id key context)))

(defun activate (context key)
  (%lui.frame:make-event :kind :activate :id (retained-id key context)))

(defun test-node-slots ()
  (let* ((label (lui.retained:make-label "Before"))
         (children (cl:vector label))
         (panel (lui.retained:make-panel :children children))
         (context (%lui.tests.support:make-test-context)))
    (assert (lui.retained:node-p label))
    (assert (lui.retained:label-p label))
    (assert (not (lui.retained:button-p label)))
    (assert (typep children '(vector lui.retained:node)))
    (assert (eq label (aref (lui.retained:panel-children panel) 0)))
    (frame context panel)
    (let ((id (%lui.layout:element-id (element-with-value context "Before"))))
      (setf (lui.retained:label-text label) "After")
      (frame context panel)
      (assert (equal id (%lui.layout:element-id
                        (element-with-value context "After")))))
    (assert (eq label (aref children 0)))
    (assert (null (lui.retained:label-background label)))
    (setf (lui.retained:label-background label) "#fedcba")
    (frame context panel)
    (let ((widget (%lui.layout:element-content
                   (element-with-value context "After"))))
      (assert (equal "#fedcba"
                     (%lui.widgets:widget-color widget :background))))
    (setf (lui.retained:label-background label) nil)
    (frame context panel)
    (let ((widget (%lui.layout:element-content
                   (element-with-value context "After"))))
      (assert (not (equal "#fedcba"
                          (%lui.widgets:widget-color widget :background)))))))

(defun test-widget-constructors ()
  ;; Every concrete type uses its standard DEFSTRUCT constructor and adapter.
  (let ((widgets
          (cl:vector
           (lui.retained:make-label "Label")
           (lui.retained:make-button "Button")
           (lui.retained:make-checkbox "Check")
           (lui.retained:make-radio :one "Radio")
           (lui.retained:make-radio nil "No choice")
           (lui.retained:make-slider :minimum 0 :maximum 10 :step 1)
           (lui.retained:make-text-field :placeholder "Text")
           (lui.retained:make-date-picker)
           (lui.retained:make-searchable-combobox
            (make-array 1 :element-type 'string :initial-element "Choice"))
           (lui.retained:make-gauge 0.5)
           (lui.retained:make-spinner)
           (lui.retained:make-spacer)
           (lui.retained:make-hr)
           (lui.retained:make-vr)
           (lui.retained:make-cell "Cell")
           (lui.retained:make-list-item "Item")
           (lui.retained:make-tab "Tab")
           (lui.retained:make-canvas nil)
           (lui.retained:make-row)
           (lui.retained:make-column)
           (lui.retained:make-panel)
           (lui.retained:make-table
            :children (cl:vector
                       (lui.retained:make-table-row
                        :children (cl:vector
                                   (lui.retained:make-table-cell))))))))
    (loop :for widget :across widgets
          :do (frame (%lui.tests.support:make-test-context) widget)))
  ;; Missing required arguments and unrelated keywords fail at construction.
  (dolist (case '((lui.retained:make-label)
                  (lui.retained:make-button)
                  (lui.retained:make-checkbox)
                  (lui.retained:make-radio :one)
                  (lui.retained:make-searchable-combobox)
                  (lui.retained:make-gauge)
                  (lui.retained:make-cell)
                  (lui.retained:make-list-item)
                  (lui.retained:make-tab)
                  (lui.retained:make-canvas)
                  (lui.retained:make-label :text "Old keyword form")
                  (lui.retained:make-button "Button" :children #())
                  (lui.retained:make-label "Label" :minimum 0)
                  (lui.retained:make-slider :password-p t)
                  (luir:make-text-field :observed-value "private")
                  (luir:make-slider :controlled-p t)
                  (lui.retained:make-text-field :on-activate identity)
                  (lui.retained:make-column :text "Invalid")))
    (assert (handler-case
                (progn (apply (symbol-function (first case)) (rest case)) nil)
              (error () t))))
  (assert (not (fboundp 'lui.retained:node)))
  (assert (not (fboundp 'lui.retained:button))))

(defun test-object-identity ()
  (let* ((context (%lui.tests.support:make-test-context))
         (changes nil)
         (field (lui.retained:make-text-field :default-value "start"
                 :on-change (lambda (value) (push value changes))))
         (other (lui.retained:make-label "other"))
         (tree (cl:vector field other)))
    (frame context tree)
    (let ((id (%lui.layout:element-id (element-with-value context "start"))))
      (frame context tree
             (list (%lui.frame:make-event :kind :text :id id :value "!")))
      (assert (equal changes '("start!")))
      (setf (%lui.frame:context-focus context) id
            tree (reverse tree))
      (frame context tree)
      (assert (equal id (%lui.frame:context-focus context)))
      (assert (equal id (%lui.layout:element-id
                        (element-with-value context "start!")))))
    ;; A new unkeyed object is a new widget, even in the same position.
    (setf tree (cl:vector
                other (lui.retained:make-text-field :default-value "fresh")))
    (frame context tree)
    (assert (%lui.tests.support:has-text-p context "fresh"))
    (assert (not (%lui.tests.support:has-text-p context "start!")))
    (frame context (cl:vector))
    (frame context field)
    (assert (%lui.tests.support:has-text-p context "start"))
    (assert (not (%lui.tests.support:has-text-p context "start!")))))

(defun test-single-children ()
  (assert (eq (find-package :luir) (find-package :lui.retained)))
  (dolist (key '(nil :same))
    (let* ((context (%lui.tests.support:make-test-context))
           (field (luir:make-text-field :id key :default-value "single"))
           (inner (luir:make-row :id :same :children field))
           (root (luir:make-column :children inner)))
      (frame context root)
      (let ((id (%lui.layout:element-id
                 (element-with-value context "single"))))
        (frame context root
               (list (%lui.frame:make-event :kind :text :id id :value "!")))
        ;; Changing collection shape preserves identity, focus, and owned text.
        (setf (%lui.frame:context-focus context) id)
        (dolist (children (list (cl:vector field) field))
          (setf (luir:row-children inner) children)
          (frame context root)
          (assert (equal id (%lui.frame:context-focus context)))
          (assert (equal id (%lui.layout:element-id
                            (element-with-value context "single!"))))))
      ;; Empty vectors still remove children and release their owned state.
      (setf (luir:row-children inner) (cl:vector))
      (frame context root)
      (setf (luir:row-children inner) field)
      (frame context root)
      (assert (%lui.tests.support:has-text-p context "single")))))

(defun test-explicit-identity ()
  (let* ((context (%lui.tests.support:make-test-context))
         (field (lui.retained:make-text-field :id 0 :default-value "keyed")))
    (frame context field)
    (let ((id (retained-id 0 context)))
      (frame context field
             (list (%lui.frame:make-event :kind :text :id id :value "!")))
      (setf field (lui.retained:make-text-field :id 0 :default-value "new"))
      (frame context field)
      (assert (equal id (retained-id 0 context)))
      (assert (%lui.tests.support:has-text-p context "keyed!")))))

(defun keyed-columns (left right)
  "Rebuild equal compound parent keys around independently keyed fields."
  (lui.retained:make-row
   :id :root
   :children
   (cl:vector
    (lui.retained:make-column :id (list :column (copy-seq "left"))
                             :children (cl:vector left))
    (lui.retained:make-column :id (list :column (copy-seq "right"))
                             :children (cl:vector right))
    (lui.retained:make-column :id :spare))))

(defun value-id (context value)
  "Return a field's resolved ID without depending on its internal shape."
  (%lui.layout:element-id (element-with-value context value)))

(defun test-keyed-parent-scopes ()
  (let* ((context (%lui.tests.support:make-test-context))
         (left (lui.retained:make-text-field
                :id (list :edit 0) :default-value "Left"))
         (right (lui.retained:make-text-field
                 :id (list :edit 0) :default-value "Right"))
         (tree (keyed-columns left right)))
    (frame context tree)
    (let ((left-id (value-id context "Left"))
          (right-id (value-id context "Right")))
      (assert (not (equal left-id right-id)))
      (setf (%lui.frame:context-focus context) left-id)
      (frame context tree
             (list (%lui.frame:make-event :kind :text :id left-id :value "!")
                   (%lui.frame:make-event :kind :text :id right-id :value "!")))
      ;; New nodes and new EQUAL keys must preserve each parent's state.
      (setf left (lui.retained:make-text-field
                  :id (list :edit 0) :default-value "Reset left")
            right (lui.retained:make-text-field
                   :id (list :edit 0) :default-value "Reset right")
            tree (keyed-columns left right))
      (frame context tree)
      (assert (equal left-id (value-id context "Left!")))
      (assert (equal right-id (value-id context "Right!")))
      (assert (equal left-id (%lui.frame:context-focus context)))
      (let* ((children (lui.retained:row-children tree))
             (left-parent (aref children 0))
             (spare-parent (aref children 2)))
        (setf (lui.retained:row-children tree) (reverse children))
        (frame context tree)
        (assert (equal left-id (value-id context "Left!")))
        (assert (equal right-id (value-id context "Right!")))
        ;; Moving the field to a different parent starts new owned state.
        (setf (lui.retained:column-children left-parent) (cl:vector)
              (lui.retained:column-children spare-parent)
              (cl:vector left))
        (frame context tree)
        (assert (not (equal left-id (value-id context "Reset left"))))
        (assert (null (%lui.frame:context-focus context)))
        (assert (equal right-id (value-id context "Right!")))))))

(defun test-key-namespaces ()
  (let* ((context (%lui.tests.support:make-test-context))
         (object (lui.retained:make-text-field :default-value "Object"))
         (keyed (lui.retained:make-text-field
                 :id object :default-value "Keyed"))
         (tree (cl:vector object keyed)))
    (frame context tree)
    (let ((object-id (value-id context "Object"))
          (keyed-id (value-id context "Keyed")))
      (assert (not (equal object-id keyed-id)))
      (frame context tree
             (list (%lui.frame:make-event :kind :text :id object-id :value "!")
                   (%lui.frame:make-event :kind :text :id keyed-id :value "!")))
      (frame context (reverse tree))
      (assert (equal object-id (value-id context "Object!")))
      (assert (equal keyed-id (value-id context "Keyed!"))))
    ;; Both orders exercise a shared hash key in the two identity namespaces.
    (assert (invalid-p (cl:vector object keyed object)))
    (assert (invalid-p (cl:vector keyed object keyed)))
    (setf (lui.retained:node-id keyed) (list :changed 0))
    (frame context tree)
    (assert (%lui.tests.support:has-text-p context "Object!"))
    (assert (%lui.tests.support:has-text-p context "Keyed"))))

(defun test-shared-subtree-scopes ()
  (let* ((context (%lui.tests.support:make-test-context))
         (shared (lui.retained:make-column
                  :id :branch
                  :children (cl:vector
                             (lui.retained:make-text-field
                              :id :edit :default-value "Shared"))))
         (first (lui.retained:make-panel
                 :id :first :children (cl:vector shared)))
         (second (lui.retained:make-panel
                  :id :second :children (cl:vector shared)))
         (tree (cl:vector first second))
         (ids nil))
    (frame context tree)
    (%lui.layout:walk-elements
     (%lui.frame:context-root context)
     (lambda (element)
       (let ((widget (%lui.layout:element-content element)))
         (when (and (%lui.widgets:widget-p widget)
                    (eq :text-field (%lui.widgets:widget-kind widget)))
           (push (%lui.layout:element-id element) ids)))))
    (assert (= 2 (length ids)))
    (assert (not (equal (first ids) (second ids))))
    (frame context tree
           (list (%lui.frame:make-event
                  :kind :text :id (first ids) :value "!")))
    (frame context (reverse tree))
    (assert (equal (first ids) (value-id context "Shared!")))
    (assert (equal (second ids) (value-id context "Shared")))
    ;; Traversing children must not clear the enclosing siblings' table.
    (assert (invalid-p (cl:vector first second first)))))

(defun test-value-ownership ()
  (let* ((context (%lui.tests.support:make-test-context))
         (field (lui.retained:make-text-field :id :edit :default-value "owned"))
         (check (lui.retained:make-checkbox "Check" :id :check
                                  :default-value t :value nil))
         (tree (cl:vector field check)))
    (frame context tree)
    (let ((widget (%lui.layout:element-content (element-with-value context "Check"))))
      ;; NIL VALUE is omitted, so DEFAULT-VALUE initializes owned state.
      (assert (%lui.widgets:widget-value widget)))
    (setf (lui.retained:text-field-value field) "controlled")
    (frame context tree)
    (assert (%lui.tests.support:has-text-p context "controlled"))
    (setf (lui.retained:text-field-value field) nil)
    (frame context tree
           (list (%lui.frame:make-event :kind :key :key lui.key:end
                                       :id (retained-id :edit context))
                 (%lui.frame:make-event :kind :text
                                       :id (retained-id :edit context) :value "!")))
    (frame context tree)
    (assert (%lui.tests.support:has-text-p context "controlled!"))))

(defun test-value-write-back ()
  "Publish all six control values, with or without ON-CHANGE callbacks."
  (dolist (controlled '(nil t))
    (dolist (callback-p '(nil t))
      (dolist (spec
               '((luir:make-checkbox luir:checkbox-value
                  ("Check" :default-value t) t :activate nil nil)
                 (luir:make-radio luir:radio-value
                  (:second "Radio" :default-value :first)
                  :first :activate nil :second)
                 (luir:make-radio luir:radio-value
                  (nil "None" :default-value :first)
                  :first :activate nil nil)
                 (luir:make-slider luir:slider-value
                  (:default-value 2 :minimum 0 :maximum 10 :step 1)
                  2 :change 7 7)
                 (luir:make-text-field luir:text-field-value
                  (:default-value "") "" :text "edited" "edited")
                 (luir:make-searchable-combobox luir:searchable-combobox-value
                  (#("choice") :default-value "") "" :text "edited" "edited")
                 (luir:make-date-picker luir:date-picker-value
                  () nil :change "11/25/2026" "2026-11-25")))
        (destructuring-bind (constructor reader args initial kind input expected)
            spec
          (let* ((context (%lui.tests.support:make-test-context))
                 (node nil)
                 (calls 0))
            (setf node
                  (apply constructor
                         (append args
                                 (list :id :value
                                       :value (when controlled initial)
                                       :on-change
                                       (when callback-p
                                         (lambda (value)
                                           (incf calls)
                                           (assert (equal value
                                                          (funcall reader
                                                                   node)))))))))
            (frame context node)
            (let ((id (if (eq constructor 'luir:make-date-picker)
                          (%lui.layout:element-id
                           (element-with-value context ""))
                          (retained-id :value context))))
              (frame context node
                     (list (%lui.frame:make-event
                            :kind kind :id id :value input))))
            (assert (equal expected (funcall reader node)))
            (assert (= calls (if callback-p 1 0)))
            ;; In particular, an unchecked checkbox must remain NIL.
            (frame context node)
            (assert (equal expected (funcall reader node)))
            (assert (= calls (if callback-p 1 0)))))))))

(defun test-cleared-date-value ()
  "Clearing an explicitly valued date picker must publish and retain NIL."
  (let* ((context (%lui.tests.support:make-test-context))
         (node (luir:make-date-picker :value "2026-11-24")))
    (frame context node)
    (let ((id (%lui.layout:element-id
               (element-with-value context "11/24/2026"))))
      (frame context node
             (list (%lui.frame:make-event :kind :change :id id :value ""))))
    (assert (null (luir:date-picker-value node)))
    (frame context node)
    (assert (null (luir:date-picker-value node)))))

(defun test-login-values ()
  "Button callbacks read current strings even when declared before the fields."
  (let* ((context (%lui.tests.support:make-test-context))
         (username (luir:make-text-field :id :username))
         (password (luir:make-text-field :id :password :password-p t))
         (submitted nil)
         (submit (luir:make-button
                  "Login" :id :submit
                  :on-activate
                  (lambda ()
                    (setf submitted (list (luir:text-field-value username)
                                          (luir:text-field-value password))))))
         (tree (cl:vector submit username password)))
    (assert (equal "" (luir:text-field-value username)))
    (assert (equal "" (luir:text-field-value password)))
    (frame context tree)
    (frame context tree (list (activate context :submit)))
    (assert (equal '("" "") submitted))
    (frame context tree
           (list (activate context :submit)
                 (%lui.frame:make-event :kind :text
                  :id (retained-id :username context) :value "alice")
                 (%lui.frame:make-event :kind :text
                  :id (retained-id :password context) :value "secret")))
    (assert (equal '("alice" "secret") submitted))
    (setf (luir:text-field-value username) "replacement")
    (frame context tree)
    (assert (%lui.tests.support:has-text-p context "replacement"))))

(defun test-styling-and-units ()
  (let ((label (lui.retained:make-label "Styled" :padding (lui:units 2)
                                 :font-size 18 :font-weight :bold
                                 :foreground "#123456" :background "#fedcba"
                                 :radius 4)))
    (dolist (unit '(1 12))
      (let ((context (%lui.tests.support:make-test-context))
            (lui:*unit* unit))
        (frame context label)
        (let* ((element (element-with-value context "Styled"))
               (widget (%lui.layout:element-content element)))
          (assert (= (* 2 unit) (%lui.layout:element-padding element)))
          (assert (= 18 (%lui.widgets:widget-font-size widget)))
          (assert (eq :bold (%lui.widgets:widget-font-weight widget)))
          (assert (= 4 (%lui.widgets:widget-radius widget)))
          (assert (equal "#123456" (%lui.widgets:widget-color widget :foreground)))
          (assert (equal "#fedcba" (%lui.widgets:widget-color widget :background))))))
    (assert (= 2 (lui:units-count (lui.retained:node-padding label))))))

(defun check-deferred-dimensions (context scale)
  "Check resolved dimensions in either immediate or retained declarations."
  (let* ((element (element-with-value context "Deferred"))
         (widget (%lui.layout:element-content element))
         (box (%lui.layout:element-box element)))
    (assert (= (* 12 scale) (%lui.layout:box-width box)))
    (assert (= (* 5 scale) (%lui.layout:box-height box)))
    (assert (= scale (%lui.layout:element-padding element)))
    (assert (= (* 0.5 scale) (%lui.layout:element-offset-x element)))
    (assert (= (* 2 scale) (%lui.widgets:widget-font-size widget)))
    (assert (= scale (%lui.widgets:widget-radius widget)))
    (assert (= (* 3 scale) (%lui.widgets:widget-frost widget)))))

(defun test-deferred-dimensions ()
  "Reuse values created outside a frame across backend scales and API layers."
  (let* ((lui:*unit* 99)
         (width (lui:units 12))
         (height (lui:fixed (lui:units 5)))
         (padding (lui:units 1))
         (options (list :width width :height height :padding padding
                        :offset-x (lui:units 0.5) :font-size (lui:units 2)
                        :radius padding :frost (lui:units 3)))
         (label (apply #'luir:make-label "Deferred" options))
         (root (luir:make-panel :width 200 :height 180 :gap padding
                               :padding padding :children label)))
    (dolist (scale '(1 8 1))
      (let ((lui:*unit* scale)
            (context (%lui.tests.support:make-test-context)))
        (frame context root)
        (check-deferred-dimensions context scale)
        (lui:with-frame (context 300 200)
          (lui:panel (:width 200 :height 180 :gap padding :padding padding)
            (lui:label "Deferred" :options options)))
        (check-deferred-dimensions context scale)
        (assert (= (* 12 scale) (lui:resolve-units width)))
        (assert (= 7 (lui:resolve-units 7)))))
    (assert (eq width (luir:label-width label)))
    (assert (eq height (luir:label-height label)))
    (assert (= 5 (lui:units-count (%lui.layout:sizing-value height))))
    (assert (= 12 (lui:units-count width)))))

(defun test-unit-sizing-bounds ()
  "Resolve stored FIT/GROW bounds and reject contradictory mixed-scale bounds."
  (let ((fit (lui:fit (lui:units 3) 40))
        (grow (lui:grow (lui:units 2) (lui:units 5)))
        (mixed (lui:fit (lui:units 3) 20)))
    (dolist (scale '(1 8))
      (let ((lui:*unit* scale)
            (context (%lui.tests.support:make-test-context)))
        (lui:with-frame (context 300 200)
          (lui:column (:width 100)
            (lui:label "X" :width fit)
            (lui:label "Y" :width grow)))
        (assert (= (* 3 scale)
                   (%lui.layout:box-width
                    (%lui.layout:element-box
                     (element-with-value context "X")))))
        (assert (= (* 5 scale)
                   (%lui.layout:box-width
                    (%lui.layout:element-box
                     (element-with-value context "Y")))))))
    (assert (lui:units-p (%lui.layout:sizing-minimum fit)))
    (let ((lui:*unit* 8))
      (assert (handler-case
                  (progn (%lui.layout:resolve-sizing mixed) nil)
                (error () t))))))

(defun invalid-p (tree)
  (handler-case
      (progn (frame (%lui.tests.support:make-test-context) tree) nil)
    (lui:configuration-error () t)))

(defun test-invalid-trees ()
  (let ((child (lui.retained:make-label "same"))
        (parent (lui.retained:make-column)))
    (frame (%lui.tests.support:make-test-context)
           (cl:vector child
                               #-jscl (copy-structure child)
                               #+jscl (lui.retained:make-label "same")))
    (assert (invalid-p (cl:vector child child)))
    (assert (invalid-p (cl:vector
                        (lui.retained:make-button "A" :id :same)
                        (lui.retained:make-label "B" :id :same))))
    (setf (lui.retained:column-children parent) (cl:vector parent))
    (assert (invalid-p parent))
    (setf (luir:column-children parent) parent)
    (assert (invalid-p parent)))
  (assert (invalid-p (lui.retained:make-button nil)))
  ;; JSCL deliberately omits generated DEFSTRUCT constructor slot checks.
  #-jscl
  (assert (handler-case
              (progn (funcall (symbol-function 'lui:units) "bad") nil)
            (type-error () t)))
  ;; The obsolete list representation is rejected, not silently converted.
  (assert (handler-case
              (progn (funcall (symbol-function 'frame)
                             (%lui.tests.support:make-test-context)
                             '((:label "old"))) nil)
            (type-error () t))))

(defun test-deferred-callbacks ()
  (let* ((context (%lui.tests.support:make-test-context))
         (order nil)
         (parent (lui.retained:make-column :id :parent))
         (first (lui.retained:make-button "First" :id :first
                                  :on-activate
                                  (lambda ()
                                    (push :first order)
                                    (setf (lui.retained:column-children parent)
                                          (cl:vector)))))
         (second (lui.retained:make-button "Second" :id :second
                                   :on-activate (lambda () (push :second order)))))
    (setf (lui.retained:column-children parent)
          (cl:vector first second))
    (frame context parent)
    (frame context parent
           (loop :for text :in '("First" "Second")
                 :collect (%lui.frame:make-event
                           :kind :activate :id
                           (%lui.layout:element-id
                            (element-with-value context text)))))
    (assert (equal (reverse order) '(:first :second)))
    (assert (%lui.tests.support:has-text-p context "Second"))
    (assert (%lui.frame:context-next-frame context))
    (frame context parent)
    (assert (not (%lui.tests.support:has-text-p context "Second")))))

(defun test-symbol-callbacks ()
  (let* ((context (%lui.tests.support:make-test-context))
         (callback (gensym "CALLBACK"))
         (change (gensym "CHANGE"))
         (result nil)
         (tree (cl:vector
                (lui.retained:make-button "Redefine" :id :first
                 :on-activate (lambda ()
                                (setf (symbol-function callback)
                                      (lambda () (push :new result)))))
                (lui.retained:make-button "Call" :id :second
                                  :on-activate callback)
                (lui.retained:make-text-field :id :edit :on-change change))))
    (unwind-protect
         (progn
           (setf (symbol-function callback) (lambda () (push :old result))
                 (symbol-function change) (lambda (text) (push text result)))
           (frame context tree)
           (frame context tree
                  (list (activate context :first) (activate context :second)
                        (%lui.frame:make-event :kind :text
                                              :id (retained-id :edit context)
                                              :value "changed")))
           (assert (equal (reverse result) '(:new "changed"))))
      #-jscl (fmakunbound callback)
      #-jscl (fmakunbound change)
      #+jscl (setf (symbol-function callback) #'identity
                   (symbol-function change) #'identity))))

(defun test-discarded-callbacks ()
  (let* ((context (%lui.tests.support:make-test-context))
         (calls 0)
         (button (lui.retained:make-button "Go" :id :go
                                   :on-activate (lambda () (incf calls))))
         (tree (cl:vector button)))
    (frame context tree)
    (let ((event (activate context :go)))
      (setf tree (cl:vector button (lui.retained:make-button nil)))
      (assert (handler-case (progn (frame context tree (list event)) nil)
                (lui:configuration-error () t))))
    (assert (zerop calls))
    (frame context button)
    (assert (zerop calls))))

(defun run-tests ()
  (test-node-slots)
  (test-widget-constructors)
  (test-object-identity)
  (test-single-children)
  (test-explicit-identity)
  (test-keyed-parent-scopes)
  (test-key-namespaces)
  (test-shared-subtree-scopes)
  (test-value-ownership)
  (test-value-write-back)
  (test-cleared-date-value)
  (test-login-values)
  (test-styling-and-units)
  (test-deferred-dimensions)
  (test-unit-sizing-bounds)
  (test-invalid-trees)
  (test-deferred-callbacks)
  (test-symbol-callbacks)
  (test-discarded-callbacks)
  (format t "Retained structs, mutation, identity, callbacks and styling passed.~%"))
