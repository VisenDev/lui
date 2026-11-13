(defpackage #:%lui.tests.core
  (:use #:cl #:%lui.fn #:%lui.layout #:%lui.frame #:%lui.tests.support)
  (:export #:run-tests))

(in-package #:%lui.tests.core)

(fn (typed-example integer) ((value integer))
  "Exercise docstrings and caller declarations."
  (declare (ignorable value))
  (1+ value))

(fn (supplied-option list) (&optional (value nil value-p))
  (list value value-p))

(fn (supplied-key list) (&key ((paint (or null function)) nil paint-p))
  (list paint paint-p))

(fn (typed-bindings list) ((value integer)
                          &optional ((increment integer) 2 supplied-p)
                          &rest (extra list))
  (list (+ value increment) supplied-p extra))

#-jscl
(fn (typed-aux integer) ((value integer) &aux ((total integer) (1+ value)))
  total)

(fn test-frame-memo ()
  (let ((context (make-test-context)) (other (make-test-context))
        (calls 0) (text (copy-seq "one")))
    (labels ((value (key)
               (%lui.frame::memoized key (lambda () (incf calls))))
             (frame (target &rest keys)
               (with-frame (target 80 36)
                 (dolist (key keys) (value key)))))
      (frame context (list text) '(2))
      (assert (= calls 2))
      (frame context (list text) '(2))
      (assert (= calls 2))
      ;; Mutable text is snapshotted rather than retained as a live key.
      (setf (char text 0) #\O)
      (frame context (list text) '(2))
      (assert (= calls 3))
      (frame other (list text))
      (assert (= calls 4))
      ;; Removed entries cannot survive a frame in which they were not used.
      (frame context (list text))
      (assert (= calls 4))
      (frame context (list text) '(2))
      (assert (= calls 5))
      ;; Aborted declarations must not become a source of reusable results.
      (catch 'abort
        (with-frame (context 80 36)
          (value '(3))
          (throw 'abort nil)))
      (frame context '(3))
      (assert (= calls 7))
      (frame context '(3))
      (assert (= calls 7))
      (frame context)
      (assert (zerop (length (%lui.frame::context-memo context))))
      ;; There is no indefinitely retained cache outside a building frame.
      (value '(3)) (value '(3))
      (assert (= calls 9)))))

(fn (test-side-effect-values (values)) ()
  (let ((context (make-test-context)) (root (make-element)) (visits 0))
    (append-child root (make-element))
    (assert (null (multiple-value-list
                   (walk-elements root (lambda (node)
                                         (declare (ignore node))
                                         (incf visits))))))
    (assert (= visits 2))
    (assert (null (multiple-value-list
                   (%lui.frame::advance-scroll context 0))))
    (let ((stats (%lui.frame::context-statistics context)))
      (assert (null (multiple-value-list
                     (%lui.frame::record-frame-statistics stats 2 0))))
      (assert (= 1 (%lui.frame::frame-statistics-count stats)))))
  (values))

(fn (test-conditions (values)) ()
  (let ((failure
          (handler-case
              (lui:run (lambda () (values)) :backend :missing-test-backend)
            (lui:configuration-error (condition) condition))))
    (assert (typep failure 'lui:lui-error))
    (assert (eq :backend (lui:error-setting failure)))
    (assert (eq :missing-test-backend (lui:error-value failure)))
    (assert (eq :run (lui:error-operation failure)))
    (assert (search "not loaded" (princ-to-string failure))))
  (let ((failure
          (make-condition 'lui:backend-error :backend :x11
                          :operation :open-window
                          :format-control "Cannot open display ~A."
                          :format-arguments '("test"))))
    (assert (eq :x11 (lui:error-backend failure)))
    (assert (string= "Cannot open display test." (princ-to-string failure))))
  (values))

(defun test-call-with-scopes ()
  (let ((toolkit (lui:current-toolkit))
        (palette (lui.toolkit:toolkit-palette))
        (scope %lui.frame::*key-scope*))
    (assert
     (equal '(1 2)
            (multiple-value-list
             (lui:call-with-toolkit :motif
               (lambda ()
                 (assert (eq :motif (lui:current-toolkit)))
                 (lui:call-with-palette :dark
                   (lambda ()
                     (lui:call-with-key 42
                       (lambda ()
                         (assert (= 42 (first %lui.frame::*key-scope*)))
                         (values 1 2))))))))))
    (assert
     (eq :escaped
         (catch 'scope-exit
           (lui:with-toolkit (:qt)
             (lui:with-palette (:light)
               (lui:with-key :nested (throw 'scope-exit :escaped)))))))
    (assert (eq toolkit (lui:current-toolkit)))
    (assert (equal palette (lui.toolkit:toolkit-palette)))
    (assert (eq scope %lui.frame::*key-scope*)))
  (let ((context (make-test-context)) (calls 0))
    (assert (eq (lui:call-with-frame context 20 10
                  (lambda () (incf calls)))
                (context-root context)))
    (assert (= calls 1))
    (assert (eq :escaped
                (catch 'frame-exit
                  (lui:call-with-frame context 20 10
                    (lambda () (throw 'frame-exit :escaped))))))
    (assert (null (context-root context)))
    (assert (not (%lui.frame::context-building-p context)))
    (assert (typep (with-frame (context 20 10)
                     (let ((ignored 1))
                       (declare (ignore ignored))
                       (incf calls)))
                   'element))
    (assert (= calls 2))))

(defun test-absolute-placement ()
  (dolist (direction '(:row :column))
    (dolist (manual-first '(nil t))
      (let* ((root (make-element :direction direction :gap 5 :padding 2))
             (manual (make-element :position :fixed :offset-x 17
                                   :offset-y 17
                                   :width (fixed 20) :height (fixed 20)))
             (a (make-element :width (fixed 20) :height (fixed 20)))
             (b (make-element :width (fixed 20) :height (fixed 20))))
        (when manual-first (append-child root manual))
        (append-child root a)
        (append-child root b)
        (unless manual-first (append-child root manual))
        (dolist (placement '((:fixed 17) (:fixed 100) (:absolute 17)))
          (setf (element-position manual) (first placement)
                (element-offset-x manual) (second placement)
                (element-offset-y manual) (second placement))
          (solve root 200 200)
          (let ((axis (if (eq direction :row) #'box-x #'box-y)))
            (assert (= 2 (funcall axis (element-box a))))
            (assert (= 27 (funcall axis (element-box b))))))))))

(defun test-positioned-fit-container ()
  (let* ((root (make-element))
         (parent (append-child root (make-element :padding 2)))
         (flow (append-child parent
                 (make-element :width (fixed 20) :height (fixed 10)))))
    (append-child parent
      (make-element :position :fixed :offset-x 200
                    :offset-y 200
                    :width (fixed 20) :height (fixed 20)))
    (let ((following (append-child root (make-element :height (fixed 10)))))
      (solve root 300 300)
      (assert (= 2 (box-y (element-box flow))))
      (assert (= 14 (box-height (element-box parent))))
      (assert (= 14 (box-y (element-box following))))
      ;; An explicit automatic container reserves space for manual contents.
      (setf (element-height parent) (fixed 50))
      (solve root 300 300)
      (assert (= 50 (box-y (element-box following)))))))

(defun test-absolute-scroll-and-parent ()
  (let* ((root (make-element :padding 10))
         (parent (append-child root
                   (make-element :width (fixed 80) :height (fixed 60)
                                 :scroll-p t :scroll-y 20)))
         (flow (append-child parent (make-element :width (fixed 30)
                                                  :height (fixed 200))))
         (relative (append-child parent
                     (make-element :position :absolute :offset-y 30
                                   :width (fixed 20) :height (fixed 20))))
         (manual (append-child parent
                   (make-element :position :fixed :offset-x 30
                                 :offset-y 35
                                 :width (fixed 20)
                                 :height (fixed 20)))))
    (solve root 200 200)
    (assert (= -10 (box-y (element-box flow))))
    (assert (= 20 (box-y (element-box relative))))
    (assert (= 30 (box-x (element-box manual))))
    (assert (= 35 (box-y (element-box manual))))
    (setf (element-scroll-y parent) 999)
    (solve root 200 200)
    (assert (= 140 (element-scroll-y parent)))
    (assert (= -100 (box-y (element-box relative))))
    (assert (= 35 (box-y (element-box manual))))))

(defun test-positioned-widget-events ()
  (let ((context (make-test-context)) (x 20) (activated nil))
    (flet ((draw ()
             (setf activated
                   (lui:button "Manual"
                     (lui:opt :id :manual :position :fixed :offset-x x
                              :offset-y 10
                              :width (fixed 20) :height (fixed 5))))))
      (with-frame (context 100 60) (draw))
      (with-frame (context 100 60
                   :events (list (make-event :kind :press :button :primary
                                             :x 22 :y 12))) (draw))
      (assert (not activated))
      (with-frame (context 100 60
                   :events (list (make-event :kind :release :button :primary
                                             :x 22 :y 12))) (draw))
      (assert activated)
      (setf x 60)
      (with-frame (context 100 60) (draw))
      (let ((*context* context))
        (assert (= 60 (box-x
                        (element-box (gethash (lui:widget-id :manual)
                                              (context-ids context)))))))
      (with-frame (context 100 60)
        (column (lui:opt :id :scroll :scroll-p t :height (fixed 10))
          (assert (equal '(0 0)
                         (multiple-value-list (lui:parent-scroll-position))))
          (lui:label "Tall" (lui:opt :height (fixed 40)))))
      (let ((*context* context)) (scroll-to :scroll 0 5))
      (with-frame (context 100 60)
        (column (lui:opt :id :scroll :scroll-p t :height (fixed 10))
          (assert (equal '(0 5)
                         (multiple-value-list (lui:parent-scroll-position))))
          (lui:label "Tall" (lui:opt :height (fixed 40))))))))

(defun run-tests ()
  (test-conditions)
  (test-side-effect-values)
  (test-absolute-placement)
  (test-positioned-fit-container)
  (test-absolute-scroll-and-parent)
  (test-positioned-widget-events)
  (test-call-with-scopes)
  (test-frame-memo)
  (let ((checks 0))
    (flet ((check (value)
             (incf checks)
             (assert value () "Check ~D failed." checks)))
      (check (typep (make-hash-table) 'lui:object-id))
      (check (typep (make-element) 'lui:object-id))
      (check (equal '(7 t (1 "two" :three))
                    (typed-bindings 3 4 1 "two" :three)))
      (check (= (typed-example 2) 3))
      #-jscl (check (= (typed-aux 2) 3))
      (check (equal '(5 nil nil) (typed-bindings 3)))
      (check (equal '(7 t (a b)) (typed-bindings 3 4 'a 'b)))
      (check (equal '(nil nil) (supplied-option)))
      (check (equal '(nil t) (supplied-option nil)))
      (check (equal '(nil nil) (supplied-key)))
      (check (equal '(nil t) (supplied-key :paint nil)))
      (check (stringp (documentation 'typed-example 'function)))
      (let ((lui::*backends* (make-hash-table :test 'eq))
            (lui::%*default-backend-function* (constantly :terminal))
            (lui:*backend* nil))
        (lui:register-backend :terminal (constantly :terminal))
        (lui:register-backend :x11 (constantly :x11))
        (check (eq :terminal (lui:run #'identity)))
        (let ((lui:*backend* :x11))
          (check (eq :x11 (lui:run #'identity)))
          (check (eq :terminal (lui:run #'identity :backend :terminal)))))
      (let ((context (make-test-context))
            (options (lui:opt :width (grow) :column-gap 1))
            (calls 0))
        (flet ((draw ()
                 (lui:table (progn (incf calls) options)
                   (lui:table-row (lui:opt :id :header)
                     (lui:table-cell (lui:opt :column-span 2)
                       (lui:label "Header")))
                   (lui:table-row ()
                     (lui:label "A")
                     (lui:table-cell ()
                       (%lui.tests.support::draw-button "Edit" (lui:opt :id
                                                                :edit))))
                   (lui:table-row () (lui:label "First") (lui:label "B"))
                   (lui:table-row () (lui:label "C")))))
          (dolist (width '(32 12))
            (setf calls 0)
            (with-frame (context width 12) (draw))
            (check (= calls 1))
            (check (equal (cdr options)
                          (list (getf options :width) :column-gap 1)))
            (let* ((table (aref (element-children (context-root context)) 0))
                   (rows (element-children table)))
              (check (eq :header (lui:widget-key (element-id (aref rows 0)))))
              (flet ((cell-box (row col)
                       (element-box (aref (element-children (aref rows row))
                          col))))
                (check (= width (box-width (cell-box 0 0))))
                (check (= (box-x (cell-box 1 1)) (box-x (cell-box 2 1))))
                (check (= (box-width (cell-box 1 0)) (box-width (cell-box 3
                          0))))
                (check (= width (+ (box-x (cell-box 1 1))
                                   (box-width (cell-box 1 1))))))
              (check (visible-text-p context "Header"))))))
      ;; Growth redistributes space after a maximum is reached.
      (let* ((root (make-element :direction :row :padding 2 :gap 2))
             (a (append-child root (make-element :width (fixed 10))))
             (b (append-child root (make-element :width (grow 0 20))))
             (c (append-child root (make-element :width (grow)))))
        (solve root 100 20)
        (check (= (box-width (element-box a)) 10))
        (check (= (box-width (element-box b)) 20))
        (check (= (box-width (element-box c)) 62))
        (check (= (box-x (element-box c)) 36)))
      ;; Percentage basis excludes padding and inter-child gaps.
      (let* ((root (make-element :direction :row :padding 5 :gap 10))
             (a (append-child root (make-element :width (percent 0.5))))
             (b (append-child root (make-element :width (grow)))))
        (solve root 100 20)
        (check (= (box-width (element-box a)) 40))
        (check (= (box-width (element-box b)) 40)))
      ;; Shrink largest first, but never shrink fixed sizes or violate minima.
      (let* ((root (make-element :direction :row))
             (a (append-child
                 root
                 (make-element :width (fit 8)
                               :measure (lambda (width)
                                          (declare (ignore width))
                                          (values 30 1)))))
             (b (append-child root (make-element :width (fixed 10)))))
        (solve root 20 10)
        (check (= (box-width (element-box a)) 10))
        (solve root 12 10)
        (check (= (box-width (element-box a)) 8))
        (check (= (box-width (element-box b)) 10)))
      (let* ((root (make-element :direction :row :align :end
                                 :cross-align :center))
             (a (append-child root
                              (make-element :width (fixed 10)
                                            :height (fixed 4)))))
        (solve root 40 20)
        (check (= (box-x (element-box a)) 30))
        (check (= (box-y (element-box a)) 8)))
      ;; Clipping reserves fractional padding without clipping the container.
      (let* ((root (make-element :padding 1.5 :clip-p t))
             (child (append-child
                     root (make-element :width (fixed 20) :height (fixed 12)
                                        :position :absolute :offset-x -1
                                        :offset-y -1))))
        (solve root 10 8)
        (check (= (box-width (element-clip root)) 10))
        (check (= (box-x (element-clip child)) 1.5))
        (check (= (box-y (element-clip child)) 1.5))
        (check (= (box-width (element-clip child)) 7))
        (check (= (box-height (element-clip child)) 5)))
      ;; Fractional row heights can sum to slightly more than the viewport.
      (let ((root (make-element :scroll-p t)))
        (dotimes (i 3)
          (append-child root (make-element :height (fixed 0.1d0))))
        (solve root 1 0.3d0)
        (check (zerop (element-scroll-limit-y root)))
        (solve root 1 0.25d0)
        (check (> (element-scroll-limit-y root) 0.049d0)))
      ;; Scrolled children stay inside padding; the last row can reach its end.
      (let* ((root (make-element :padding 2 :scroll-p t :scroll-y 1.5))
             (first (append-child
                     root (make-element :width (fixed 20)
                                        :height (fixed 8)))))
        (append-child root (make-element :height (fixed 8)))
        (solve root 20 10)
        (check (= (box-y (element-box first)) 0.5))
        (check (= (box-y (element-clip first)) 2))
        (check (= (box-height (element-clip first)) 6))
        (check (= (element-scroll-limit-y root) 10))
        (setf (element-scroll-y root) 100
              (element-scroll-x root) 100)
        (solve root 20 10)
        (check (= (element-scroll-y root) 10))
        (check (= (element-scroll-x root) 4))
        (let ((last (aref (element-children root) 1)))
          (check (= (box-y (element-clip last)) 2))
          (check (= (box-height (element-clip last)) 6))))
      ;; Padding has no child hit/cursor region, even behind a scrolled row.
      (let ((context (make-test-context))
            (clicked nil))
        (labels ((draw ()
                   (column (lui:opt :id :scroll :width (fixed 20) :height
                     (fixed 10)
                            :padding 2 :scroll-p t)
                     (setf clicked
                       (lui:with-toolkit (:motif)
                         (%lui.tests.support::draw-button "Row" (lui:opt
                        :id :row :height (fixed 16))))))))
          (with-frame (context 20 10) (draw))
          (check (eq :default (%lui.widgets:cursor-at context 3 1)))
          (check (eq :pointer (%lui.widgets:cursor-at context 3 2)))
          (with-frame
              (context 20 10 :events
                       (list (make-event :kind :scroll :x 3 :y 3 :value 1.5)
                             (make-event :kind :press :x 3 :y 1)
                             (make-event :kind :release :x 3 :y 1)))
            (draw))
          (check (not clicked))
          (check (eq :default (%lui.widgets:cursor-at context 3 1)))
          (check (eq :default (%lui.widgets:cursor-at context 3 8)))
          (check (eq :pointer (%lui.widgets:cursor-at context 3 3)))))
      ;; Wrapped height reaches the parent before vertical positioning.
      (let ((context (make-test-context)))
        (with-frame (context 5 10)
          (column (lui:opt :width (grow))
            (lui.glass:label "ab cd ef")
            (lui.glass:label "next")))
        (let* ((column (aref (element-children (context-root context)) 0))
               (second (aref (element-children column) 1)))
          (check (= (box-height (element-box column)) 3))
          (check (= (box-y (element-box second)) 2)))
        (check (has-text-p context "ab cd ef")))
      (check (equalp (test-lines (format nil "a~%~%b~%") 3)
                    #("a" "" "b" "")))
      (check (equalp (test-lines "longword ok" 3) #("longword" "ok")))
      ;; Previous-frame hit testing; release requires capture of the same ID.
      (let ((context (make-test-context))
            (clicked nil))
        (with-frame (context 20 5) (lui:with-toolkit (:glass)
                                     (%lui.tests.support::draw-button "OK"
                                       (lui:opt :id :button))))
        (with-frame
            (context 20 5 :events
                     (list (make-event :kind :press :x 1 :y 0)
                           (make-event :kind :release :x 1 :y 0)))
          (setf clicked (lui:with-toolkit (:glass)
                          (%lui.tests.support::draw-button "OK" (lui:opt :id
                                                                 :button)))))
        (check clicked)
        (with-frame (context 20 5)
          (setf clicked (lui:with-toolkit (:glass)
                          (%lui.tests.support::draw-button "OK" (lui:opt :id
                                                                 :button)))))
        (check (not clicked))
        (with-frame
            (context 20 5 :events
                     (list (make-event :kind :press :x 1 :y 0)
                           (make-event :kind :release :x 19 :y 4)))
          (setf clicked (lui:with-toolkit (:glass)
                          (%lui.tests.support::draw-button "OK" (lui:opt :id
                                                                 :button)))))
        (check (not clicked))
        (with-frame
            (context 21 5 :events
                     (list (make-event :kind :press :x 1 :y 0)
                           (make-event :kind :release :x 1 :y 0)))
          (setf clicked (lui:with-toolkit (:glass)
                          (%lui.tests.support::draw-button "OK" (lui:opt :id
                                                                 :button)))))
        (check (not clicked))
        (with-frame
            (context 21 5 :events
                     (list (make-event :kind :tab)
                           (make-event :kind :activate)))
          (setf clicked (lui:with-toolkit (:glass)
                          (%lui.tests.support::draw-button "OK" (lui:opt :id
                                                                 :button)))))
        (check clicked)
        (with-frame (context 21 5))
        (check (null (lui:widget-key (context-focus context))))
        (check (null (lui:widget-key (context-active context))))
        (check (handler-case
                   (progn
                     (with-frame (context 20 5)
                     (lui:with-toolkit (:glass)
                       (%lui.tests.support::draw-button "A" (lui:opt :id
                                                             :same)))
                     (lui:with-toolkit (:motif)
                       (%lui.tests.support::draw-button "B" (lui:opt :id
                                                             :same))))
                     nil)
                 (error () t)))
        ;; Aborted frame must not leave stale geometry or prevent the next frame.
        (check (null (context-root context)))
        (with-frame (context 20 5) (lui:with-toolkit (:motif)
                                     (%lui.tests.support::draw-button "New"
                                       (lui:opt :id :new))))
        (check (visible-text-p context "[ New ]")))

      (check (handler-case (progn (percent 2) nil) (error () t)))
      (check (handler-case (progn (fixed -1) nil) (error () t)))
      (check (handler-case (progn (fit 10 5) nil) (error () t))))
    (format t "~&~D LUI checks passed.~%" checks)
    t))
