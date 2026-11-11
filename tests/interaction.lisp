(defpackage #:lui.tests.interaction
  (:use #:cl #:lui.layout #:lui.frame #:lui.tests.support)
  (:export #:run-tests))
(in-package #:lui.tests.interaction)

(defun test-shared-helpers ()
  (assert (= 1 (lui.interaction:list-index :down 0 3)))
  (assert (= 2 (lui.interaction:list-index :down 2 3)))
  (assert (= 0 (lui.interaction:list-index :home 2 3)))
  (assert (null (lui.interaction:list-index :down 0 0)))
  (let* ((control (make-event :kind :text :value (string (code-char 1))))
         (normalized (lui.interaction:text-input-event control t)))
    (assert (eq :key (event-kind normalized)))
    (assert (eq :home (event-key normalized)))
    (assert (null (lui.interaction:text-input-event control nil))))
  (multiple-value-bind (first end)
      (lui.interaction:visible-span 999 20 10 4 26)
    (assert (<= 0 first end 26)))
  (let ((context (make-test-context)))
    (with-frame (context 20 5 :events
                         (vector (make-event :kind :text :id :editor
                                             :value "!")))
      (assert (typep (lui.interaction:event-targets) '(vector t)))
      (assert (find :editor (lui.interaction:event-targets)))
      (let ((events (events-for :editor)))
        (assert (typep events '(vector event)))
        (assert (equal "!" (event-value (aref events 0)))))
      (lui.interaction:reset-editor :editor "abc")
      (let ((text (lui.interaction:edit-value :editor "abc")))
        (assert (equal "abc!" text))
        (let ((events (lui.interaction:take-events :editor)))
          (assert (typep events '(vector event)))
          (assert (zerop (length events))))
        (lui.tests.support::draw-text-field (lui:opt :id :editor :value
                                              text))))
    (let ((widget (element-content
                    (gethash (lui:widget-id :editor context)
                      (lui.frame::context-ids context)))))
      (assert (equal "abc!" (lui.widgets:widget-value widget)))))
  (let ((context (make-test-context)))
    (flet ((draw ()
             (column (:id :view :width (fixed 10) :height (fixed 8)
                      :scroll-p t)
               (emit (make-element :width (fixed 100) :height (fixed 100))))))
      (with-frame (context 20 20) (draw))
      (with-frame (context 20 20 :events
                           (list (make-event :kind :key :key :escape
                                             :id :key)))
        (assert (lui.interaction:key-pressed-p :escape))
        (assert (lui.interaction:reveal-rect :view 30 40 4 4
                                            :leading-x 2 :leading-y 1))
        (draw))
      (let ((*context* context))
        (multiple-value-bind (x y) (scroll-position :view)
          (assert (= x 24)) (assert (= y 36))))
      (with-frame (context 20 20)
        (assert (not (lui.interaction:reveal-rect :view 30 40 4 4
                                                :leading-x 2 :leading-y 1)))
        (draw))
      (assert (null (context-next-frame context))))))

(defun scroll-frame (context &rest events)
  (with-frame (context 100 100 :events events)
    (column (:id :view :width (fixed 20) :height (fixed 20) :scroll-p t)
      (emit (make-element :width (fixed 20) :height (fixed 5000))))))

(defun scroll-offset (context &optional (id :view))
  (element-scroll-y (gethash (lui:widget-id id context)
                      (lui.frame::context-ids context))))

(defun wheel (amount &optional (mode :auto))
  (make-event :kind :scroll :x 1 :y 1 :value amount :scroll-mode mode))

(defun test-wheel-momentum ()
  (let ((one (make-context)) (many (make-context)))
    (dolist (context (list one many))
      (scroll-frame context)
      (scroll-frame context (wheel 32))
      (assert (< 0 (scroll-offset context) 32))
      (assert (> (context-next-frame context)
                 (lui.frame::context-time context))))
    ;; Different redraw rates cover the same distance at the same elapsed time.
    (lui.frame::advance-scroll
     one (+ (lui.frame::context-time one) 0.05d0))
    (dotimes (step 5)
      (lui.frame::advance-scroll
       many (+ (lui.frame::context-time many) (* (1+ step) 0.01d0))))
    (assert (< (abs (- (scroll-offset one) (scroll-offset many))) 1d-7))
    (lui.frame::advance-scroll one (+ (lui.frame::context-time one) 1))
    (assert (< (abs (- (scroll-offset one) 32)) 1d-7))
    (assert (null (lui.frame::context-scroll-motion one))))
  (let ((burst (make-context)) (isolated (make-context)))
    (dolist (context (list burst isolated)) (scroll-frame context))
    (dotimes (tick 5)
      (setf (lui.frame::context-time burst) (* tick 0.02d0)
            (lui.frame::context-time isolated) tick)
      (lui.frame::wheel-scroll burst (wheel 32))
      (lui.frame::wheel-scroll isolated (wheel 32))
      (lui.frame::advance-scroll isolated (+ tick 1)))
    (lui.frame::advance-scroll burst 1)
    ;; A quick wheel burst travels faster, but its gain remains bounded.
    (assert (= (scroll-offset isolated) 160d0))
    (assert (< 160 (scroll-offset burst) (* 160 2.05d0)))
    (assert (null (lui.frame::context-scroll-motion burst))))
  (let ((context (make-context)))
    (scroll-frame context)
    (scroll-frame context (wheel 32 :immediate))
    (assert (= 32 (scroll-offset context)))
    (assert (null (context-next-frame context)))
    ;; OS-provided inertia neither gains distance nor starts a second tail.
    (scroll-frame context (wheel 32 :immediate) (wheel 16 :immediate))
    (assert (= 80 (scroll-offset context)))
    (assert (null (lui.frame::context-scroll-motion context)))
    (scroll-frame context (wheel 32))
    (let ((position (scroll-offset context)))
      (scroll-frame context (make-event :kind :key :key :down))
      (assert (= position (scroll-offset context)))
      (assert (null (context-next-frame context))))
    (scroll-frame context (wheel 32))
    (with-frame (context 100 100)
      (scroll-to :view 0 10)
      (column (:id :view :width (fixed 20) :height (fixed 20) :scroll-p t)
        (emit (make-element :height (fixed 5000)))))
    (assert (= 10 (scroll-offset context)))
    (assert (null (context-next-frame context)))
    (scroll-frame context (wheel 32))
    (scroll-frame context (wheel -32))
    (lui.frame::advance-scroll context
                              (+ (lui.frame::context-time context) 1))
    (assert (= 0 (scroll-offset context)))
    (assert (null (lui.frame::context-scroll-motion context)))
    (scroll-frame context (wheel 32))
    (with-frame (context 101 100)
      (column (:id :view :height (fixed 20) :scroll-p t)
        (emit (make-element :height (fixed 5000)))))
    (assert (null (context-next-frame context)))
    (assert (null (lui.frame::context-scroll-motion context))))
  ;; Case-distinct string IDs must start separate momentum tails.
  (let ((context (make-context)))
    (with-frame (context 100 100)
      (row ()
        (dolist (id '("A" "a"))
          (column (:id id :width (fixed 20) :height (fixed 20) :scroll-p t)
            (emit (make-element :height (fixed 5000)))))))
    (setf (lui.frame::context-time context) 0)
    (lui.frame::wheel-scroll context (wheel 32))
    (setf (lui.frame::context-time context) 0.02d0)
    (let ((event (wheel 32)))
      (setf (event-x event) 21)
      (lui.frame::wheel-scroll context event))
    (lui.frame::advance-scroll context 1)
    (assert (= 0 (scroll-offset context "A")))
    (assert (= 32 (scroll-offset context "a"))))
  (let ((context (make-test-context)))
    (scroll-frame context)
    (scroll-frame context (wheel 3))
    (assert (= 3 (scroll-offset context)))
    ;; The real terminal adapter can explicitly opt its wheel into physics.
    (scroll-frame context (wheel 3 :smooth))
    (assert (< 3 (scroll-offset context) 6))
    (assert (context-next-frame context)))
  (let ((context (make-context)))
    (flet ((draw ()
             (column (:id :outer :width (fixed 20) :height (fixed 20)
                      :scroll-p t)
               (column (:id :inner :width (grow) :height (fixed 10)
                        :scroll-p t)
                 (emit (make-element :height (fixed 100))))
               (emit (make-element :height (fixed 100))))))
      (with-frame (context 100 100) (draw))
      (with-frame (context 100 100 :events (list (wheel 120))) (draw))
      (lui.frame::advance-scroll context
                                (+ (lui.frame::context-time context) 1))
      (assert (= 90 (scroll-offset context :inner)))
      (assert (= 30 (scroll-offset context :outer)))
      ;; Exhausting both scroll ranges stops, rather than requesting idle frames.
      (with-frame (context 100 100 :events (list (wheel 1000))) (draw))
      (lui.frame::advance-scroll context
                                (+ (lui.frame::context-time context) 1))
      (assert (= 90 (scroll-offset context :outer)))
      (assert (null (lui.frame::context-scroll-motion context)))
      (with-frame (context 100 100 :events (list (wheel -32))) (draw))
      (with-frame (context 100 100) nil)
      (assert (null (lui.frame::context-scroll-motion context)))
      (assert (null (context-next-frame context))))))

(defparameter *macro-defaults*
  '(:background "#123456" :foreground "#ffffff"))

(lui:define-toolkit :test-modern *macro-defaults* modern-panel
  modern-label modern-button)

(defun test-toolkit-definitions ()
  (let ((context (make-test-context))
        (*macro-defaults* '(:background "#abcdef" :foreground "#010203")))
    (with-frame (context 40 20)
      (modern-panel (lui:opt :id :modern-panel :padding 1)
        (modern-label "Modern")
        (modern-button "Action" (lui:opt :id :modern :width
                                  (fixed 11)))))
    (let* ((node (gethash (lui:widget-id :modern context)
                   (lui.frame::context-ids context)))
           (widget (element-content node)))
      (assert (eq :test-modern (lui.widgets:widget-style widget)))
      (assert (string= "#abcdef" (lui.widgets:widget-background widget)))
      (assert (= 11 (box-width (element-box node)))))
    (loop for (key value) on *macro-defaults* by #'cddr
          do (assert (equal value (getf (lui:toolkit-defaults :test-modern)
              key))))))

(defun test-palettes ()
  (assert (equalp (lui:available-palettes) #(:default :light :dark :ocean
          :forest)))
  (assert (lui:palette-p lui:+palette-default+))
  (assert (equal (lui:palette-foreground lui:+palette-dark+) "#eeeeee"))
  (assert (handler-case (funcall (symbol-function 'lui::call-with-palette)
                     (list :accent "#123456") (constantly nil))
            (error () t)))
  ;; Resolve a provider once per control, while observing changes within a frame.
  (let ((reads 0) (color "#112233") (context (make-test-context)))
    (lui:register-toolkit :palette-provider :parent :glass
      :defaults (lambda () (incf reads) (list :palette (list :cell-background
              color))))
    (with-frame (context 80 30)
      (lui:with-toolkit (:palette-provider)
        (lui.tests.support::draw-cell "First" (lui:opt :id :first))
        (setf color "#445566")
        (lui.tests.support::draw-cell "Second" (lui:opt :id :second))))
    (assert (= reads 2))
    (dolist (entry '((:first . "#112233") (:second . "#445566")))
      (assert (equal (cdr entry)
                     (lui:widget-color
                  (element-content (gethash (lui:widget-id (car entry)
                  context) (lui.frame::context-ids context)))
                      :background)))))
  (lui:register-toolkit :palette-parent :parent :glass
                       :defaults '(:palette (:accent "#123456" :outline "#654321")))
  (lui:register-toolkit :palette-child :parent :palette-parent
                       :defaults '(:palette (:background "#abcdef")))
  (assert (equal "#123456" (getf (lui:toolkit-palette :palette-child)
          :accent)))
  (assert (equal "#abcdef" (getf (lui:toolkit-palette :palette-child)
          :background)))
  (let ((context (make-test-context)))
    (with-frame (context 80 30)
      (lui:with-palette ((lui:make-palette :accent "#112233" :outline "#445566"))
        (lui:with-toolkit (:glass) (lui.tests.support::draw-button "Glass"
                                     (lui:opt :id :glass)))
        (lui:with-toolkit (:motif)
          (lui:with-palette ((lui:make-palette :background "#778899"))
            (lui.tests.support::draw-button "Motif" (lui:opt :id :motif
                                                      :accent "#aabbcc"))
            (lui:panel (lui:opt :id :palette-panel) (lui:label "Panel"))))
        (lui:with-toolkit (:garnet) (lui.tests.support::draw-button "Garnet"
                                      (lui:opt :id :garnet))))
      (lui:with-toolkit (:glass) (lui.tests.support::draw-button "Default"
                                   (lui:opt :id :unscoped))))
    ;; Check after the scopes have unwound: widgets retain resolved colors.
    (flet ((color (id role)
             (lui:widget-color (element-content (gethash (lui:widget-id id
                  context) (lui.frame::context-ids context))) role)))
      (assert (equal "#112233" (color :glass :accent)))
      (assert (equal "#445566" (color :garnet :outline)))
      (assert (equal "#aabbcc" (color :motif :accent)))
      (assert (equal "#778899" (color :motif :background)))
      (assert (equal "#778899" (color :palette-panel :background)))
      (assert (equal "#303040" (color :glass :background)))
      (assert (equal "#ffffff" (color :garnet :background)))
      (assert (equal "#258bff" (color :unscoped :accent))))))

(defun test-named-palette-scope ()
  (let ((before (lui:toolkit-palette)))
    (loop :for name :across (lui:available-palettes)
          :for palette :in (list lui:+palette-default+ lui:+palette-light+
                                 lui:+palette-dark+ lui:+palette-ocean+
                                 lui:+palette-forest+)
          :do (assert
               (equal (lui:with-palette (name) (lui:toolkit-palette))
                      (lui:with-palette (palette) (lui:toolkit-palette)))))
    (lui:with-palette (:dark)
      (lui:with-palette ((lui:make-palette :accent "#123456"))
        (assert (equal "#123456" (getf (lui:toolkit-palette) :accent)))
        (assert (equal "#eeeeee" (getf (lui:toolkit-palette) :foreground)))))
    (assert (equal before (lui:toolkit-palette)))))

(defun test-date-picker ()
  (assert (equalp #(2024 2 29) (lui::parse-picker-date "02/29/2024")))
  (assert (equalp #(2024 2 29) (lui::parse-picker-date "2024-02-29")))
  (dolist (text '("02/29/2023" "04/31/2024" "00/01/2024" "01/01/0000"
                  "2024-02-29T12:00" "12:00" "02/29/2024 12:00"))
    (assert (null (lui::parse-picker-date text))))
  (let ((context (lui.tests.support:make-test-context)))
    (with-frame (context 56 22)
      (lui.tests.support::draw-date-picker (lui:opt :id :appointment :value "2026-11-06")))
    (assert (equal '(:appointment :input) (lui:widget-key (lui.frame::hit
              context 1 1))))
    (dolist (text '("11/06/2026" "▦"))
      (assert (has-text-p context text))))
  (let ((context (make-test-context)))
    (dolist (style '(:glass :motif :garnet))
      (lui:with-toolkit (style)
        (with-frame (context 80 40)
          (lui.tests.support::draw-date-picker
            (lui:opt :id style :value "2026-11-06")))
        (with-frame (context 80 40)
          (record-activation context
            (lui:widget-id (list style :calendar) context))
          (lui.tests.support::draw-date-picker (lui:opt :id style :value "2026-11-06")))
        (let* ((palette (lui:toolkit-defaults))
               (day (element-content
                      (gethash (lui:widget-id (list style :day 6) context)
                        (lui.frame::context-ids context)))))
          (assert (lui.widgets:widget-value day))
          (assert (equal (lui.widgets:widget-foreground day) (getf palette
                  :foreground)))
          (assert (equal (lui.widgets:widget-background day) (getf palette
                  :background)))
          (assert (equal (lui.widgets:widget-accent day) (getf palette
                  :accent)))))))
  (let ((context (make-test-context)) (value "2026-11-06"))
    (flet ((frame (&rest events)
             (with-frame (context 60 32 :events events)
               (setf value (lui.tests.support::draw-date-picker (lui:opt :id
                  :date :value value))))))
      (dolist (xy '((3 1) (0 0)))
        (frame)
        (destructuring-bind (x y) xy
          (frame (make-event :kind :press :x x :y y))
          (frame (make-event :kind :release :x x :y y)))
        (assert (equal (lui:widget-key (context-focus context)) '(:date
                :input)))
        (assert (gethash (lui:widget-id '(:date :popup) context)
                  (lui.frame::context-ids context)))
        (frame (make-event :kind :key :key :escape))
        (assert (null (gethash (lui:widget-id '(:date :popup) context)
                        (lui.frame::context-ids context)))))
      (frame (make-event :kind :change :id '(:date :input) :value
            "11/07/2026"))
      (assert (equal value "2026-11-07"))))
  (assert (= 4 (lui::calendar-start 2026 1)))
  ;; Adjacent days at the lower bound use year zero before being disabled.
  (assert (equal '(0 12) (multiple-value-list (lui::shift-month 1 1 -1))))
  (assert (= 31 (lui::month-days 0 12)))
  (let ((context (lui.tests.support:make-test-context))
        (value "2024-02-28"))
    (flet ((draw ()
             (column (:gap 1)
               (setf value (lui.tests.support::draw-date-picker (lui:opt :id
                  :date :value value)))
               (lui.tests.support::draw-button "Following control" (lui:opt
                :id :following)))))
      (with-frame (context 80 40) (draw))
      (let* ((picker (gethash (lui:widget-id :date context)
                       (lui.frame::context-ids context)))
             (following (gethash (lui:widget-id :following context)
                          (lui.frame::context-ids context)))
             (following-y (lui.layout:box-y (lui.layout:element-box
                  following))))
        ;; Opening the calendar paints over the space below the field; layout
        ;; keeps the following control at its original position.
        (with-frame (context 80 40 :events
                     (list (make-event :kind :activate :id '(:date
                    :calendar))))
          (draw))
        (assert (= following-y
                   (lui.layout:box-y
                    (lui.layout:element-box
                      (gethash (lui:widget-id :following context)
                        (lui.frame::context-ids context))))))
        (assert picker)
        (assert (visible-text-p context "February 2024"))
        (let ((days 0))
          (walk-elements (context-root context)
            (lambda (node)
              (let ((id (lui:widget-key (element-id node))))
                (when (and (consp id) (member (second id) '(:day :adjacent)))
                  (incf days)))))
          (assert (= days 42))))
      (with-frame (context 80 40
                   :events (list (make-event :kind :activate
                                             :id '(:date :day 29))))
        (draw))
      (assert (equal value "2024-02-29"))
      ;; Editable drafts update the model only when the full date is valid.
      (with-frame (context 80 40
                   :events (list (make-event :kind :change
                                             :id '(:date :input)
                                             :value "03/01/2024")))
        (draw))
      (assert (equal value "2024-03-01"))
      (with-frame (context 80 40
                   :events (list (make-event :kind :change
                                             :id '(:date :input)
                                             :value "02/30/2024")))
        (draw))
      (assert (equal value "2024-03-01"))
      (with-frame (context 80 40 :events
                   (list (make-event :kind :activate :id '(:date :calendar))))
        (draw))
      (with-frame (context 80 40
                   :events (list (make-event :kind :activate
                                             :id '(:date :clear))))
        (draw))
      (assert (null value))
      (with-frame (context 80 40 :events
                   (list (make-event :kind :activate :id '(:date :calendar))))
        (draw))
      (with-frame (context 80 40
                   :events (list (make-event :kind :activate
                                             :id '(:date :today))))
        (draw))
      (assert (equalp (lui::parse-picker-date value)
                     (lui::local-today)))
      (setf value "2024-12-31")
      (with-frame (context 80 40) (draw))
      (with-frame (context 80 40 :events
                   (list (make-event :kind :activate :id '(:date :calendar))))
        (draw))
      (with-frame (context 80 40 :events (list (make-event :kind :key :key
                :right)))
        (draw))
      (assert (equal (lui:widget-key (context-focus context)) '(:date :day
              1)))
      (with-frame (context 80 40 :events (list (make-event :kind :activate)))
        (draw))
      (assert (equal value "2025-01-01")))))

(defun test-frame-limits ()
  (let ((context (make-context :min-fps 1 :max-fps 8)))
    (setf (lui.frame::context-time context) 10)
    (assert (= 1 (lui.frame::frame-wait context nil 10)))
    (assert (= 0.125 (lui.frame::frame-wait context t 10)))
    (setf (context-next-frame context) 10.5)
    (assert (= 0.5 (lui.frame::frame-wait context nil 10)))
    (setf (context-next-frame context) 10)
    (assert (= 0.125 (lui.frame::frame-wait context nil 10)))
    (assert (zerop (lui.frame::frame-wait context nil 11)))))

(defun test-owned-widget-state ()
  (let ((context (make-test-context)) (other (make-test-context))
        (default "first") (visible t) value changed id)
    (flet ((draw (context &optional events)
             (with-frame (context 80 20 :events events)
               (when visible
                 (multiple-value-setq (value changed id)
                   (lui:text-field (lui:opt :default-value default)))))))
      (draw context)
      (assert (equal value "first"))
      (assert (not changed))
      (let ((first-id id))
        (setf default "ignored")
        (draw context (vector (make-event :kind :change :id id :value
                                "saved")))
        (assert (equal value "saved"))
        (assert changed)
        (assert (equal first-id id))
        (draw context)
        (assert (equal value "saved"))
        (assert (not changed))
        (draw other)
        (assert (equal value "ignored"))
        (draw context)
        (assert (equal value "saved")))
      (let ((*context* context)) (lui:reset-editor id "reset"))
      (draw context)
      (assert (equal value "reset"))
      (setf visible nil)
      (draw context)
      (assert (zerop (hash-table-count (context-values context))))
      (setf visible t)
      (draw context)
      (assert (equal value "ignored")))))

(defun test-keyed-widget-state ()
  (let ((context (make-test-context)) (order '(0 1)) ids values)
    (flet ((draw (&optional events)
             (setf ids nil values nil)
             (with-frame (context 80 20 :events events)
               (dolist (key order)
                 (lui:with-key key
                   (multiple-value-bind (value changed id)
                     (lui:text-field (lui:opt :id 0 :default-value ""))
                     (declare (ignore changed))
                     (push (cons key value) values)
                     (push (cons key id) ids))
                   (multiple-value-bind (checked changed id)
                     (lui:checkbox "Enabled" (lui:opt :id 0))
                     (declare (ignore checked changed))
                     (assert (not (equal id (cdar ids))))))))))
      (draw)
      (let ((first-id (cdr (assoc 0 ids))))
        (setf order '(1 0))
        (draw (vector (make-event :kind :change :id first-id :value "zero")))
        (assert (equal "zero" (cdr (assoc 0 values))))
        (assert (equal "" (cdr (assoc 1 values))))
        (assert (equal first-id (cdr (assoc 0 ids))))
        (let ((*context* context))
          (assert (handler-case (progn (lui:with-key 0 (lui:widget-id 0)) nil)
                    (lui:configuration-error () t))))))))

(defun test-controlled-widget-state ()
  (let ((context (make-test-context)) (model "model") value id)
    (flet ((draw (&optional events)
             (with-frame (context 80 20 :events events)
               (multiple-value-bind (text changed identity)
                 (lui:text-field (lui:opt :value model :default-value
                    "unused"))
                 (declare (ignore changed))
                 (setf value text id identity)))))
      (draw)
      (assert (equal "model" value))
      (draw (vector (make-event :kind :change :id id :value "edit")))
      (assert (equal "edit" value))
      (draw)
      (assert (equal "model" value))
      (with-frame (context 80 20)
        (assert (null (lui:checkbox "False"
                        (lui:opt :value nil :default-value
                          t))))))))

(defun test-automatic-widget-identity ()
  (let ((context (make-test-context)) ids (evaluations 0))
    (flet ((draw ()
             (with-frame (context 80 20)
               (setf ids
                 (list (nth-value 2 (lui:text-field))
                   (nth-value 2 (lui:text-field))))
            (lui:button
              (progn (incf evaluations) "Once")
              (progn (incf evaluations) (lui:opt :id 0))))))
      (draw)
      (assert (= evaluations 2))
      (assert (not (equal (first ids) (second ids))))
      (let ((previous ids))
        (draw)
        (assert (equal previous ids)))
      (assert
        (handler-case
          (progn
            (with-frame (context 80 20)
              (dotimes (i 2)
                (declare (ignorable i))
                (lui:text-field (lui:opt :id 0))))
            nil)
          (error () t))))))

(defun test-missing-widget-keys ()
  (let ((context (make-test-context)))
    (dolist (options (list nil (lui:opt :id 0) (lui:opt :id nil)))
      (let ((failure
              (handler-case
                  (with-frame (context 80 20)
                    (dotimes (i 2)
                      (lui:text-field options)))
                (lui:configuration-error (condition) condition))))
        (assert (typep failure 'lui:configuration-error))
        (assert (eq :declare-widget (lui:error-operation failure)))
        (assert (eq :id (lui:error-setting failure)))
        (assert (search (if options "Repeated control key" "call site")
                        (princ-to-string failure)))))))

(defun run-tests ()
  (test-missing-widget-keys)
  (test-owned-widget-state)
  (test-keyed-widget-state)
  (test-controlled-widget-state)
  (test-automatic-widget-identity)
  (test-named-palette-scope)
  (test-palettes)
  (test-frame-limits)
  (test-date-picker)
  (test-toolkit-definitions)
  (test-shared-helpers)
  (test-wheel-momentum)
  (let ((outer (lui:current-toolkit)))
    (dolist (style '(:glass :motif :garnet))
      (let ((context (make-test-context)) (evaluations 0)
            (checked nil) (number 3) (text "raw"))
        (labels ((node (id)
                   (gethash (lui:widget-id id context)
                     (lui.frame::context-ids context)))
                 (appearance (id) (element-content (node id)))
                 (draw ()
                   (lui:with-toolkit ((progn (incf evaluations) style))
                     (assert (eq style (lui:current-toolkit)))
                     (lui:label "Plain label")
                     (lui.tests.support::draw-button "Plain button" (lui:opt
                    :id :plain))
                     (lui.tests.support::draw-button "Sized" (lui:opt :id
                    :sized :width (progn (incf evaluations)
                                                       (fixed 9))
                                                               :height
                                                               (fixed 2)))
                     (lui.tests.support::draw-tab "Tab" (lui:opt :id :tab
                                                          :selected-p t))
                     (setf checked (lui.tests.support::draw-checkbox "Check"
                                     (lui:opt :id :check :value checked))
                       number (lui.tests.support::draw-slider (lui:opt
                      :id :slider :value number :minimum 0 :maximum 10
                                                       :step 1))
                       text (lui.tests.support::draw-text-field (lui:opt
                      :id :field :value text)))
                     (lui.tests.support::draw-cell "Cell" (lui:opt :id :cell
                                                            :selected-p t))
                     (lui.tests.support::draw-list-item "Item" (lui:opt :id
                    :item :selected-p t))
                     (lui.tests.support::draw-gauge 0.5 (lui:opt :id :gauge))
                     (lui.tests.support::draw-canvas nil (lui:opt :id
                                                           :canvas))
                     (lui:panel (lui:opt :id :panel :width (fixed 15)
                                          :padding 1)
                       (lui.tests.support::draw-button "Inside"
                         (lui:opt :id :inside))
                       (lui:with-toolkit (:garnet)
                         (lui.tests.support::draw-button "Nested"
                           (lui:opt :id :nested))))
                     (lui.tests.support::draw-button "After" (lui:opt :id
                                                               :after))))
                 (frame (&rest events)
                   (with-frame (context 50 50 :events events) (draw))))
          (frame)
          (assert (= 2 evaluations))
          (assert (eq outer (lui:current-toolkit)))
          (dolist (id '(:plain :sized :tab :check :slider :field :cell :item
                        :gauge :canvas :panel :inside :after))
            (assert (eq style (lui.widgets:widget-style (appearance id)))))
          (assert (eq :garnet
                      (lui.widgets:widget-style (appearance :nested))))
          (assert (equal (getf (lui:toolkit-defaults style) :background)
                         (lui.widgets:widget-background (appearance :plain))))
          (assert (= 9 (box-width (element-box (node :sized)))))
          (assert (= 2 (box-height (element-box (node :sized)))))
          (assert (= 15 (box-width (element-box (node :panel)))))
          (assert (= 1 (element-padding (node :panel))))
          (assert (not (element-interactive-p (node :gauge))))
          (dolist (id '(:tab :cell :item))
            (assert (lui.widgets:widget-value (appearance id))))
          (frame (make-event :kind :activate :id :check)
                 (make-event :kind :change :id :slider :value 7)
                 (make-event :kind :change :id :field :value "edited"))
          (assert checked)
          (assert (= 7 number))
          (assert (equal "edited" text)))))
    ;; An explicit NIL option overrides a true toolkit default.
    (let ((lui:*glass-defaults*
            (append '(:disabled-p t) lui:*glass-defaults*))
          (context (make-test-context)))
      (with-frame (context 20 5)
        (lui:with-toolkit (:glass)
          (lui.tests.support::draw-button "Inherited" (lui:opt :id
                                                        :inherited))
          (lui.tests.support::draw-button "Enabled" (lui:opt :id :enabled
                                                      :disabled-p nil))))
      (assert (not (element-interactive-p
                     (gethash (lui:widget-id :inherited context)
                       (lui.frame::context-ids context)))))
      (assert (element-interactive-p
                (gethash (lui:widget-id :enabled context)
                  (lui.frame::context-ids context)))))
    (assert (handler-case (progn (lui:with-toolkit (:unknown) t) nil)
              (error () t)))
    (assert (eq outer (lui:current-toolkit))))
  (let ((received nil)
        (options (lui:opt :width (fixed 12)))
        (context (make-test-context)))
    (lui:register-toolkit
     :test :parent :motif :defaults '(:accent "#123456")
     :controls
     (list (cons :button
                 (lambda (id text opts)
                   (setf received (list id text opts))
                   (apply #'lui.widgets:declare-widget :button
                          (lui:current-toolkit) id text
                          (append opts (lui:toolkit-defaults)))))))
    (lui:register-toolkit :test-child :parent :test)
    (with-frame (context 30 10)
      (lui:with-toolkit (:test)
        (assert (eq :test (lui:current-toolkit)))
        (lui.tests.support::draw-button "Custom" (list* :id :custom options))
        (lui:label "Inherited")
        (lui:panel (lui:opt :id :custom-panel)
          (lui:label "Child"))))
    (assert (equal (list (lui:widget-key (first received)) (second received))
              '(:custom "Custom")))
    (assert (equal (third received) options))
    (assert (equal "#123456" (getf (lui:toolkit-defaults :test) :accent)))
    (assert (equal "#b8b8b8"
                   (getf (lui:toolkit-defaults :test-child) :background)))
    (let ((widget (element-content
                    (gethash (lui:widget-id :custom context)
                      (lui.frame::context-ids context)))))
      (assert (eq :test (lui.widgets:widget-style widget)))
      (assert (equal "#123456" (lui.widgets:widget-accent widget)))))
  (format t "Public toolkit scopes, controls, options and panels passed.~%")
  t)
