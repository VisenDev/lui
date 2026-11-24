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
  (let* ((label (lui.retained:make-label :text "Before"))
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
           (lui.retained:make-label :text "Label")
           (lui.retained:make-button :text "Button")
           (lui.retained:make-checkbox :text "Check")
           (lui.retained:make-radio :choice :one :text "Radio")
           (lui.retained:make-radio :choice nil :text "No choice")
           (lui.retained:make-slider :minimum 0 :maximum 10 :step 1)
           (lui.retained:make-text-field :placeholder "Text")
           (lui.retained:make-date-picker)
           (lui.retained:make-searchable-combobox
            :choices (make-array 1 :element-type 'string
                                  :initial-element "Choice"))
           (lui.retained:make-gauge :fraction 0.5)
           (lui.retained:make-spinner)
           (lui.retained:make-spacer)
           (lui.retained:make-hr)
           (lui.retained:make-vr)
           (lui.retained:make-cell :text "Cell")
           (lui.retained:make-list-item :text "Item")
           (lui.retained:make-tab :text "Tab")
           (lui.retained:make-canvas :commands nil)
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
  ;; Unrelated options are rejected by the constructors themselves.
  (dolist (case '((lui.retained:make-button :children #())
                  (lui.retained:make-label :minimum 0)
                  (lui.retained:make-slider :password-p t)
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
         (other (lui.retained:make-label :text "other"))
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
         (check (lui.retained:make-checkbox :id :check :text "Check"
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

(defun test-styling-and-units ()
  (let ((label (lui.retained:make-label :text "Styled" :padding '(:units 2)
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
    (assert (equal '(:units 2) (lui.retained:node-padding label)))))

(defun invalid-p (tree)
  (handler-case
      (progn (frame (%lui.tests.support:make-test-context) tree) nil)
    (lui:configuration-error () t)))

(defun test-invalid-trees ()
  (let ((child (lui.retained:make-label :text "same"))
        (parent (lui.retained:make-column)))
    (frame (%lui.tests.support:make-test-context)
           (cl:vector child
                               #-jscl (copy-structure child)
                               #+jscl (lui.retained:make-label :text "same")))
    (assert (invalid-p (cl:vector child child)))
    (assert (invalid-p (cl:vector
                        (lui.retained:make-button :text "A" :id :same)
                        (lui.retained:make-label :text "B" :id :same))))
    (setf (lui.retained:column-children parent) (cl:vector parent))
    (assert (invalid-p parent)))
  (assert (invalid-p (lui.retained:make-button)))
  (assert (invalid-p (lui.retained:make-label :text "Bad" :padding '(:units "x"))))
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
         (first (lui.retained:make-button :text "First" :id :first
                                  :on-activate
                                  (lambda ()
                                    (push :first order)
                                    (setf (lui.retained:column-children parent)
                                          (cl:vector)))))
         (second (lui.retained:make-button :text "Second" :id :second
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
                (lui.retained:make-button :text "Redefine" :id :first
                 :on-activate (lambda ()
                                (setf (symbol-function callback)
                                      (lambda () (push :new result)))))
                (lui.retained:make-button :text "Call" :id :second
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
         (button (lui.retained:make-button :text "Go" :id :go
                                   :on-activate (lambda () (incf calls))))
         (tree (cl:vector button)))
    (frame context tree)
    (let ((event (activate context :go)))
      (setf tree (cl:vector button (lui.retained:make-button)))
      (assert (handler-case (progn (frame context tree (list event)) nil)
                (lui:configuration-error () t))))
    (assert (zerop calls))
    (frame context button)
    (assert (zerop calls))))

(defun run-tests ()
  (test-node-slots)
  (test-widget-constructors)
  (test-object-identity)
  (test-explicit-identity)
  (test-keyed-parent-scopes)
  (test-key-namespaces)
  (test-shared-subtree-scopes)
  (test-value-ownership)
  (test-styling-and-units)
  (test-invalid-trees)
  (test-deferred-callbacks)
  (test-symbol-callbacks)
  (test-discarded-callbacks)
  (format t "Retained structs, mutation, identity, callbacks and styling passed.~%"))
