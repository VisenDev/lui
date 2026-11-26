(defpackage #:%lui.tests.interaction
  (:use #:cl #:%lui.layout #:%lui.frame #:%lui.tests.support)
  (:export #:run-tests))
(in-package #:%lui.tests.interaction)

(defun test-shared-helpers ()
  ;; Key constants are package-owned symbols, including names shared with CL.
  (dolist (key (list lui.key:enter lui.key:equal lui.key:quote lui.key:t
                     lui.key:keypad-enter lui.key:shift-word-right))
    (assert (eq (symbol-package key) (find-package :lui.key)))
    (assert (eq key (symbol-value key)))
    (assert (typep key 'lui.key:key)))
  (assert (not (typep :enter 'lui.key:key)))
  (assert (char= #\a (lui.key:key->char lui.key:a)))
  (assert (null (lui.key:key->char lui.key:f1)))
  (assert (equal (list lui.key:a lui.key:left-shift)
                 (multiple-value-list (lui.key:char->key #\A))))
  (assert (eq lui.key:enter (lui.key:char->key #\Newline)))
  (assert (null (lui.key:char->key (code-char 955))))
  ;; Activation remains observable before and after a control consumes input.
  (let ((context (make-test-context)))
    (with-frame (context 20 5 :events
                         (vector (make-event :kind :activate :key
                                             lui.key:enter
                                             :id :editor)))
      (assert (lui:key-pressed-p lui.key:enter))
      (assert (lui:activated-p :editor))
      (lui:take-events :editor)
      (assert (lui:key-pressed-p lui.key:enter)))
    (with-frame (context 20 5 :events
                         (vector (make-event :kind :activate :key
                                             lui.key:enter)))
      (assert (lui:key-pressed-p lui.key:enter)))
    (with-frame (context 20 5)
      (assert (not (lui:key-pressed-p lui.key:enter)))))

  (assert (= 1 (%lui.interaction:list-index lui.key:down 0 3)))
  (assert (= 2 (%lui.interaction:list-index lui.key:down 2 3)))
  (assert (= 0 (%lui.interaction:list-index lui.key:home 2 3)))
  (assert (null (%lui.interaction:list-index lui.key:down 0 0)))
  (let* ((control (make-event :kind :text :value (string (code-char 1))))
         (normalized (%lui.interaction:text-input-event control t)))
    (assert (eq :key (event-kind normalized)))
    (assert (eq lui.key:home (event-key normalized)))
    (assert (null (%lui.interaction:text-input-event control nil))))
  (multiple-value-bind (first end)
      (%lui.interaction:visible-span 999 20 10 4 26)
    (assert (<= 0 first end 26)))
  (let ((context (make-test-context)))
    (with-frame (context 20 5 :events
                         (vector (make-event :kind :text :id :editor
                                             :value "!")))
      (assert (typep (%lui.interaction:event-targets) '(vector t)))
      (assert (find :editor (%lui.interaction:event-targets)))
      (let ((events (events-for :editor)))
        (assert (typep events '(vector event)))
        (assert (equal "!" (event-value (aref events 0)))))
      (%lui.interaction:reset-editor :editor "abc")
      (let ((text (%lui.interaction:edit-value :editor "abc")))
        (assert (equal "abc!" text))
        (let ((events (%lui.interaction:take-events :editor)))
          (assert (typep events '(vector event)))
          (assert (zerop (length events))))
        (%lui.tests.support::draw-text-field (list :id :editor :value
                                              text))))
    (let ((widget (element-content
                    (gethash (lui:widget-id :editor context)
                      (%lui.frame::context-ids context)))))
      (assert (equal "abc!" (%lui.widgets:widget-value widget)))))
  (let ((context (make-test-context)))
    (flet ((draw ()
             (lui:column (:id :view :width (fixed 10) :height (fixed 8)
                          :scroll-p t)
               (emit (make-element :width (fixed 100) :height (fixed 100))))))
      (with-frame (context 20 20) (draw))
      (with-frame (context 20 20 :events
                           (list (make-event :kind :key :key lui.key:escape
                                             :id :key)))
        (assert (%lui.interaction:key-pressed-p lui.key:escape))
        (assert (%lui.interaction:reveal-rect :view 30 40 4 4
                                            :leading-x 2 :leading-y 1))
        (draw))
      (let ((*context* context))
        (multiple-value-bind (x y) (scroll-position :view)
          (assert (= x 24)) (assert (= y 36))))
      (with-frame (context 20 20)
        (assert (not (%lui.interaction:reveal-rect :view 30 40 4 4
                                                :leading-x 2 :leading-y 1)))
        (draw))
      (assert (null (context-next-frame context))))))

(defun scroll-frame (context &rest events)
  (with-frame (context 100 100 :events events)
    (lui:column (:id :view :width (fixed 20) :height (fixed 20) :scroll-p
      t)
      (emit (make-element :width (fixed 20) :height (fixed 5000))))))

(defun scroll-offset (context &optional (id :view))
  (element-scroll-y (gethash (lui:widget-id id context)
                      (%lui.frame::context-ids context))))

(defun wheel (amount &optional (mode :auto))
  (make-event :kind :scroll :x 1 :y 1 :value amount :scroll-mode mode))

(defun test-wheel-momentum ()
  (let ((one (make-context)) (many (make-context)))
    (dolist (context (list one many))
      (scroll-frame context)
      (scroll-frame context (wheel 32))
      (assert (< 0 (scroll-offset context) 32))
      (assert (> (context-next-frame context)
                 (%lui.frame::context-time context))))
    ;; Different redraw rates cover the same distance at the same elapsed time.
    (%lui.frame::advance-scroll
     one (+ (%lui.frame::context-time one) 0.05d0))
    (dotimes (step 5)
      (%lui.frame::advance-scroll
       many (+ (%lui.frame::context-time many) (* (1+ step) 0.01d0))))
    (assert (< (abs (- (scroll-offset one) (scroll-offset many))) 1d-7))
    (%lui.frame::advance-scroll one (+ (%lui.frame::context-time one) 1))
    (assert (< (abs (- (scroll-offset one) 32)) 1d-7))
    (assert (null (%lui.frame::context-scroll-motion one))))
  (let ((burst (make-context)) (isolated (make-context)))
    (dolist (context (list burst isolated)) (scroll-frame context))
    (dotimes (tick 5)
      (setf (%lui.frame::context-time burst) (* tick 0.02d0)
            (%lui.frame::context-time isolated) tick)
      (%lui.frame::wheel-scroll burst (wheel 32))
      (%lui.frame::wheel-scroll isolated (wheel 32))
      (%lui.frame::advance-scroll isolated (+ tick 1)))
    (%lui.frame::advance-scroll burst 1)
    ;; A quick wheel burst travels faster, but its gain remains bounded.
    (assert (= (scroll-offset isolated) 160d0))
    (assert (< 160 (scroll-offset burst) (* 160 2.05d0)))
    (assert (null (%lui.frame::context-scroll-motion burst))))
  (let ((context (make-context)))
    (scroll-frame context)
    (scroll-frame context (wheel 32 :immediate))
    (assert (= 32 (scroll-offset context)))
    (assert (null (context-next-frame context)))
    ;; OS-provided inertia neither gains distance nor starts a second tail.
    (scroll-frame context (wheel 32 :immediate) (wheel 16 :immediate))
    (assert (= 80 (scroll-offset context)))
    (assert (null (%lui.frame::context-scroll-motion context)))
    (scroll-frame context (wheel 32))
    (let ((position (scroll-offset context)))
      (scroll-frame context (make-event :kind :key :key lui.key:down))
      (assert (= position (scroll-offset context)))
      (assert (null (context-next-frame context))))
    (scroll-frame context (wheel 32))
    (with-frame (context 100 100)
      (scroll-to :view 0 10)
      (lui:column (:id :view :width (fixed 20) :height (fixed 20)
                   :scroll-p t)
        (emit (make-element :height (fixed 5000)))))
    (assert (= 10 (scroll-offset context)))
    (assert (null (context-next-frame context)))
    (scroll-frame context (wheel 32))
    (scroll-frame context (wheel -32))
    (%lui.frame::advance-scroll context
                              (+ (%lui.frame::context-time context) 1))
    (assert (= 0 (scroll-offset context)))
    (assert (null (%lui.frame::context-scroll-motion context)))
    (scroll-frame context (wheel 32))
    (with-frame (context 101 100)
      (lui:column (:id :view :height (fixed 20) :scroll-p t)
        (emit (make-element :height (fixed 5000)))))
    (assert (null (context-next-frame context)))
    (assert (null (%lui.frame::context-scroll-motion context))))
  ;; Case-distinct string IDs must start separate momentum tails.
  (let ((context (make-context)))
    (with-frame (context 100 100)
      (lui:row ()
        (dolist (id '("A" "a"))
          (lui:column (:id id :width (fixed 20) :height (fixed 20)
                       :scroll-p t)
            (emit (make-element :height (fixed 5000)))))))
    (setf (%lui.frame::context-time context) 0)
    (%lui.frame::wheel-scroll context (wheel 32))
    (setf (%lui.frame::context-time context) 0.02d0)
    (let ((event (wheel 32)))
      (setf (event-x event) 21)
      (%lui.frame::wheel-scroll context event))
    (%lui.frame::advance-scroll context 1)
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
             (lui:column (:id :outer :width (fixed 20) :height (fixed 20)
                          :scroll-p t)
               (lui:column (:id :inner :width (grow) :height (fixed 10)
                            :scroll-p t)
                 (emit (make-element :height (fixed 100))))
               (emit (make-element :height (fixed 100))))))
      (with-frame (context 100 100) (draw))
      (with-frame (context 100 100 :events (list (wheel 120))) (draw))
      (%lui.frame::advance-scroll context
                                (+ (%lui.frame::context-time context) 1))
      (assert (= 90 (scroll-offset context :inner)))
      (assert (= 30 (scroll-offset context :outer)))
      ;; Exhausting both scroll ranges stops, rather than requesting idle frames.
      (with-frame (context 100 100 :events (list (wheel 1000))) (draw))
      (%lui.frame::advance-scroll context
                                (+ (%lui.frame::context-time context) 1))
      (assert (= 90 (scroll-offset context :outer)))
      (assert (null (%lui.frame::context-scroll-motion context)))
      (with-frame (context 100 100 :events (list (wheel -32))) (draw))
      (with-frame (context 100 100) nil)
      (assert (null (%lui.frame::context-scroll-motion context)))
      (assert (null (context-next-frame context))))))

(defparameter *macro-defaults*
  '(:background "#123456" :foreground "#ffffff"))

(lui.toolkit:define-toolkit :test-modern *macro-defaults* modern-panel
  modern-label modern-button)

(defun test-toolkit-definitions ()
  (let ((context (make-test-context))
        (*macro-defaults* '(:background "#abcdef" :foreground "#010203")))
    (with-frame (context 40 20)
      (modern-panel (:id :modern-panel :padding 1)
        (modern-label "Modern")
        (modern-button "Action" :id :modern :width (fixed 11))))
    (let* ((node (gethash (lui:widget-id :modern context)
                   (%lui.frame::context-ids context)))
           (widget (element-content node)))
      (assert (eq :test-modern (%lui.widgets:widget-style widget)))
      (assert (string= "#abcdef" (%lui.widgets:widget-background widget)))
      (assert (= 11 (box-width (element-box node)))))
    (loop :for (key value) :on *macro-defaults* :by #'cddr
          :do (assert (equal value
                             (getf (lui.toolkit:toolkit-defaults :test-modern)
                                   key))))))

(defun test-palettes ()
  (assert (equalp (lui:available-palettes) #(:default :light :dark :ocean
          :forest)))
  (assert (lui:palette-p lui:+palette-default+))
  (assert (equal (lui.palette:palette-foreground lui:+palette-dark+)
                 "#eeeeee"))
  (assert (handler-case (funcall (symbol-function 'lui::call-with-palette)
                     (list :accent "#123456") (constantly nil))
            (error () t)))
  ;; Resolve a provider once per control, while observing changes within a frame.
  (let ((reads 0) (color "#112233") (context (make-test-context)))
    (lui.toolkit:register-toolkit :palette-provider :parent :glass
      :defaults (lambda () (incf reads) (list :palette (list :cell-background
              color))))
    (with-frame (context 80 30)
      (lui:with-toolkit (:palette-provider)
        (%lui.tests.support::draw-cell "First" (list :id :first))
        (setf color "#445566")
        (%lui.tests.support::draw-cell "Second" (list :id :second))))
    (assert (= reads 2))
    (dolist (entry '((:first . "#112233") (:second . "#445566")))
      (assert (equal (cdr entry)
                     (lui:widget-color
                  (element-content (gethash (lui:widget-id (car entry)
                  context) (%lui.frame::context-ids context)))
                      :background)))))
  (lui.toolkit:register-toolkit :palette-parent :parent :glass
                       :defaults '(:palette (:accent "#123456" :outline "#654321")))
  (lui.toolkit:register-toolkit :palette-child :parent :palette-parent
                       :defaults '(:palette (:background "#abcdef")))
  (assert (equal "#123456" (getf (lui.toolkit:toolkit-palette :palette-child)
          :accent)))
  (assert (equal "#abcdef" (getf (lui.toolkit:toolkit-palette :palette-child)
          :background)))
  (let ((context (make-test-context)))
    (with-frame (context 80 30)
      (lui:with-palette ((lui:make-palette :accent "#112233" :outline "#445566"))
        (lui:with-toolkit (:glass) (%lui.tests.support::draw-button "Glass"
                                     (list :id :glass)))
        (lui:with-toolkit (:motif)
          (lui:with-palette ((lui:make-palette :background "#778899"))
            (%lui.tests.support::draw-button "Motif" (list :id :motif
                                                      :accent "#aabbcc"))
            (lui:panel (:id :palette-panel) (lui:label "Panel"))))
        (lui:with-toolkit (:garnet) (%lui.tests.support::draw-button "Garnet"
                                      (list :id :garnet))))
      (lui:with-toolkit (:glass) (%lui.tests.support::draw-button "Default"
                                   (list :id :unscoped))))
    ;; Check after the scopes have unwound: widgets retain resolved colors.
    (flet ((color (id role)
             (lui:widget-color (element-content (gethash (lui:widget-id id
                  context) (%lui.frame::context-ids context))) role)))
      (assert (equal "#112233" (color :glass :accent)))
      (assert (equal "#445566" (color :garnet :outline)))
      (assert (equal "#aabbcc" (color :motif :accent)))
      (assert (equal "#778899" (color :motif :background)))
      (assert (equal "#778899" (color :palette-panel :background)))
      (assert (equal "#303040" (color :glass :background)))
      (assert (equal "#ffffff" (color :garnet :background)))
      (assert (equal "#258bff" (color :unscoped :accent))))))

(defun test-named-palette-scope ()
  (let ((before (lui.toolkit:toolkit-palette)))
    (loop :for name :across (lui:available-palettes)
          :for palette :in (list lui:+palette-default+ lui:+palette-light+
                                 lui:+palette-dark+ lui:+palette-ocean+
                                 lui:+palette-forest+)
          :do (assert
               (equal (lui:with-palette (name) (lui.toolkit:toolkit-palette))
                      (lui:with-palette (palette)
                        (lui.toolkit:toolkit-palette)))))
    (lui:with-palette (:dark)
      (lui:with-palette ((lui:make-palette :accent "#123456"))
        (assert (equal "#123456"
                       (getf (lui.toolkit:toolkit-palette) :accent)))
        (assert (equal "#eeeeee"
                       (getf (lui.toolkit:toolkit-palette) :foreground)))))
    (assert (equal before (lui.toolkit:toolkit-palette)))))

(defun test-date-picker ()
  (assert (equalp #(2024 2 29) (lui::parse-picker-date "02/29/2024")))
  (assert (equalp #(2024 2 29) (lui::parse-picker-date "2024-02-29")))
  (dolist (text '("02/29/2023" "04/31/2024" "00/01/2024" "01/01/0000"
                  "2024-02-29T12:00" "12:00" "02/29/2024 12:00"))
    (assert (null (lui::parse-picker-date text))))
  (let ((context (%lui.tests.support:make-test-context)))
    (with-frame (context 56 22)
      (%lui.tests.support::draw-date-picker (list :id :appointment :value "2026-11-06")))
    (assert (equal '(:appointment :input) (lui:widget-key (%lui.frame::hit
              context 1 1))))
    (dolist (text '("11/06/2026" "▦"))
      (assert (has-text-p context text))))
  (let ((context (make-test-context)))
    (dolist (style '(:glass :motif :garnet))
      (lui:with-toolkit (style)
        (with-frame (context 80 40)
          (%lui.tests.support::draw-date-picker
            (list :id style :value "2026-11-06")))
        (with-frame (context 80 40)
          (record-activation context
            (lui:widget-id (list style :calendar) context))
          (%lui.tests.support::draw-date-picker (list :id style :value "2026-11-06")))
        (let* ((palette (lui.toolkit:toolkit-defaults))
               (day (element-content
                      (gethash (lui:widget-id (list style :day 6) context)
                        (%lui.frame::context-ids context)))))
          (assert (%lui.widgets:widget-value day))
          (assert (equal (%lui.widgets:widget-foreground day) (getf palette
                  :foreground)))
          (assert (equal (%lui.widgets:widget-background day) (getf palette
                  :background)))
          (assert (equal (%lui.widgets:widget-accent day) (getf palette
                  :accent)))))))
  (let ((context (make-test-context)) (value "2026-11-06"))
    (flet ((frame (&rest events)
             (with-frame (context 60 32 :events events)
               (setf value (%lui.tests.support::draw-date-picker (list :id
                  :date :value value))))))
      (dolist (xy '((3 1) (0 0)))
        (frame)
        (destructuring-bind (x y) xy
          (frame (make-event :kind :press :x x :y y))
          (frame (make-event :kind :release :x x :y y)))
        (assert (equal (lui:widget-key (context-focus context)) '(:date
                :input)))
        (assert (gethash (lui:widget-id '(:date :popup) context)
                  (%lui.frame::context-ids context)))
        (frame (make-event :kind :key :key lui.key:escape))
        (assert (null (gethash (lui:widget-id '(:date :popup) context)
                        (%lui.frame::context-ids context)))))
      (frame (make-event :kind :change :id '(:date :input) :value
            "11/07/2026"))
      (assert (equal value "2026-11-07"))))
  (assert (= 4 (lui::calendar-start 2026 1)))
  ;; Adjacent days at the lower bound use year zero before being disabled.
  (assert (equal '(0 12) (multiple-value-list (lui::shift-month 1 1 -1))))
  (assert (= 31 (lui::month-days 0 12)))
  (let ((context (%lui.tests.support:make-test-context))
        (value "2024-02-28"))
    (flet ((draw ()
             (lui:column (:gap 1)
               (setf value (%lui.tests.support::draw-date-picker (list :id
                  :date :value value)))
               (%lui.tests.support::draw-button "Following control" (list
                :id :following)))))
      (with-frame (context 80 40) (draw))
      (let* ((picker (gethash (lui:widget-id :date context)
                       (%lui.frame::context-ids context)))
             (following (gethash (lui:widget-id :following context)
                          (%lui.frame::context-ids context)))
             (following-y (%lui.layout:box-y (%lui.layout:element-box
                  following))))
        ;; Opening the calendar paints over the space below the field; layout
        ;; keeps the following control at its original position.
        (with-frame (context 80 40 :events
                     (list (make-event :kind :activate :id '(:date
                    :calendar))))
          (draw))
        (assert (= following-y
                   (%lui.layout:box-y
                    (%lui.layout:element-box
                      (gethash (lui:widget-id :following context)
                        (%lui.frame::context-ids context))))))
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
                                                           lui.key:right)))
        (draw))
      (assert (equal (lui:widget-key (context-focus context)) '(:date :day
              1)))
      (with-frame (context 80 40 :events (list (make-event :kind :activate)))
        (draw))
      (assert (equal value "2025-01-01")))))

(defun test-frame-limits ()
  (let ((context (make-context :min-fps 1 :max-fps 8)))
    (setf (%lui.frame::context-time context) 10)
    (assert (= 1 (%lui.frame::frame-wait context nil 10)))
    (assert (= 0.125 (%lui.frame::frame-wait context t 10)))
    (setf (context-next-frame context) 10.5)
    (assert (= 0.5 (%lui.frame::frame-wait context nil 10)))
    (setf (context-next-frame context) 10)
    (assert (= 0.125 (%lui.frame::frame-wait context nil 10)))
    (assert (zerop (%lui.frame::frame-wait context nil 11)))
    (let ((*context* context))
      (lui:set-frame-rate-limit nil)
      (assert (null (lui:frame-rate-limit)))
      (assert (zerop (%lui.frame:frame-wait context t 10)))
      (assert (zerop (%lui.frame:frame-wait context nil 10)))
      (setf (context-next-frame context) nil)
      (assert (= 1 (%lui.frame:frame-wait context nil 10)))
      (lui:set-frame-rate-limit 8)
      (assert (= 8 (lui:frame-rate-limit)))
      (assert (= 0.125 (%lui.frame:frame-wait context t 10)))
      (assert (handler-case (progn (lui:set-frame-rate-limit 0) nil)
                (lui:configuration-error () t))))))

(defun test-owned-widget-state ()
  (let ((context (make-test-context)) (other (make-test-context))
        (default "first") (visible t) value changed id)
    (flet ((draw (context &optional events)
             (with-frame (context 80 20 :events events)
               (when visible
                 (multiple-value-bind (new-value changed-p resolved-id)
                     (lui:text-field :default-value default)
                   (setf value new-value
                         changed changed-p
                         id resolved-id))))))
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
                     (lui:text-field :id 0 :default-value "")
                     (declare (ignore changed))
                     (push (cons key value) values)
                     (push (cons key id) ids))
                   (multiple-value-bind (checked changed id)
                     (lui:checkbox "Enabled" :id 0)
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
                 (lui:text-field :value model :default-value
                    "unused")
                 (declare (ignore changed))
                 (setf value text id identity)))))
      (draw)
      (assert (equal "model" value))
      (draw (vector (make-event :kind :change :id id :value "edit")))
      (assert (equal "edit" value))
      (draw)
      (assert (equal "model" value))
      (with-frame (context 80 20)
        (let ((order nil))
          (assert
           (null (lui:checkbox "False"
                   :value (progn (push :value order) nil)
                   :options (progn (push :options order) (list :value t))
                   :default-value (progn (push :default order) t))))
          (assert (equal order '(:default :options :value))))))))

(defun test-automatic-widget-identity ()
  (let ((context (make-test-context)) ids (evaluations 0))
    (flet ((draw ()
             (with-frame (context 80 20)
               (setf ids
                 (list (nth-value 2 (lui:text-field))
                   (nth-value 2 (lui:text-field))))
            (lui:button
              (progn (incf evaluations) "Once")
              :options (progn (incf evaluations) (list :id 0))))))
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
                (lui:text-field :id 0)))
            nil)
          (error () t))))))

(defun test-missing-widget-keys ()
  (let ((context (make-test-context)))
    (dolist (options (list nil (list :id 0) (list :id nil)))
      (let ((failure
              (handler-case
                  (with-frame (context 80 20)
                    (dotimes (i 2)
                      (lui:text-field :options options)))
                (lui:configuration-error (condition) condition))))
        (assert (typep failure 'lui:configuration-error))
        (assert (eq :declare-widget (lui:error-operation failure)))
        (assert (eq :id (lui:error-setting failure)))
        (assert (search (if options "Repeated control key" "call site")
                        (princ-to-string failure)))))))

(defun test-styling-package-boundaries ()
  (let ((readers 0))
    (do-external-symbols (symbol :lui.palette)
      (let ((name (symbol-name symbol)))
        (when (and (<= 8 (length name))
                   (string= "PALETTE-" (subseq name 0 8))
                   (not (string= name "PALETTE-P")))
          (incf readers)
          (assert (fboundp symbol))
          (assert (eq (symbol-package symbol) (find-package :lui.palette)))
          (assert (not (eq :external
                           (nth-value 1 (find-symbol name :lui))))))))
    (assert (= 22 readers)))
  (dolist (name '("REGISTER-TOOLKIT" "REGISTER-TOOLKIT-RENDERING"
                  "TOOLKIT-PAINT" "TOOLKIT-GEOMETRY"
                  "TOOLKIT-NATIVE-LABELS-P" "TOOLKIT-PALETTE"
                  "TOOLKIT-DEFAULTS" "DEFINE-TOOLKIT"
                  "%*TOOLKIT-REVISION*"))
    (multiple-value-bind (symbol status) (find-symbol name :lui.toolkit)
      (assert (eq status :external))
      (assert (eq (symbol-package symbol) (find-package :lui.toolkit)))
      (assert (not (eq :external (nth-value 1 (find-symbol name :lui)))))))
  (dolist (name '("WITH-PALETTE" "MAKE-PALETTE" "AVAILABLE-PALETTES"
                  "+PALETTE-DARK+" "WITH-TOOLKIT" "CURRENT-TOOLKIT"))
    (assert (eq :external (nth-value 1 (find-symbol name :lui)))))
  (dolist (pair '((:lui.glass "*GLASS-DEFAULTS*")
                  (:lui.motif "*MOTIF-DEFAULTS*")
                  (:lui.macos "*MACOS-DEFAULTS*")
                  (:lui.qt "*QT-DEFAULTS*")
                  (:lui.garnet "*GARNET-DEFAULTS*")))
    (let ((symbol (find-symbol (second pair) (first pair))))
      (assert (boundp symbol))
      (assert (eq (symbol-package symbol) (find-package (first pair))))
      (assert (null (find-symbol (second pair) :lui))))))

(defmacro container-drawers ()
  `(vector
    ,@(loop :for kind :in '(lui:row lui:column lui:panel lui:table
                            lui:table-row lui:table-cell)
            :collect
            `(lambda (clickable disabled)
               (,kind (:id :target :width 30 :height 8 :padding 1
                       :clickable-p clickable :disabled-p disabled)
                 (lui:table-row (:width 20 :height 5)
                   (lui:column ()
                     (lui:label "Nested label")
                     (lui:button "Edit" :id :child :width 10 :height 2)))
                 :ignored-body-value)))))

(defun test-clickable-containers ()
  (loop :for draw :across (container-drawers) :do
    (let ((context (make-test-context))
          (result nil)
          (outer nil)
          (clickable t)
          (disabled nil))
      (flet ((frame (&rest events)
               (with-frame (context 50 20 :events (coerce events 'vector))
                 (setf outer
                       (lui:panel (:id :outer :clickable-p t :padding 0
                                   :width 40 :height 12)
                         (setf result (multiple-value-list
                                       (funcall draw clickable disabled))))))))
        (frame)
        (assert (= 2 (length result)))
        (assert (not (first result)))
        (assert (equal (second result) (lui:widget-id :target context)))
        ;; Noninteractive descendants and padding resolve to the container.
        (dolist (point '((2 1) (0 0) (29 7)))
          (destructuring-bind (x y) point
            (frame (make-event :kind :press :x x :y y))
            (assert (not (first result)))
            (frame (make-event :kind :release :x x :y y))
            (assert (first result))
            (assert (not outer))))
        ;; A nested button owns its capture; neither ancestor activates.
        (frame (make-event :kind :press :x 2 :y 2)
               (make-event :kind :release :x 2 :y 2))
        (assert (gethash (lui:widget-id :child context)
                         (context-activated context)))
        (assert (not (first result)))
        (assert (not outer))
        ;; Outside release, secondary buttons and cancellation never activate.
        (dolist (end (list (make-event :kind :release :x 45 :y 15)
                          (make-event :kind :cancel)))
          (frame (make-event :kind :press :x 0 :y 0) end)
          (assert (not (first result))))
        (frame (make-event :kind :press :button :secondary :x 0 :y 0)
               (make-event :kind :release :button :secondary :x 0 :y 0))
        (assert (not (first result)))
        ;; Keyboard traversal reaches outer, target, then child.
        (frame (make-event :kind :tab) (make-event :kind :tab)
               (make-event :kind :activate :key lui.key:enter))
        (assert (first result))
        (frame (make-event :kind :activate :key lui.key:space))
        (assert (first result))
        ;; Disabling clears focus/capture and blocks the enclosing container.
        (frame (make-event :kind :press :x 0 :y 0))
        (setf disabled t)
        (frame)
        (assert (null (context-active context)))
        (assert (null (context-focus context)))
        (frame (make-event :kind :press :x 0 :y 0)
               (make-event :kind :release :x 0 :y 0))
        (assert (not (first result)))
        (assert (not outer))
        (frame (make-event :kind :press :x 2 :y 2)
               (make-event :kind :release :x 2 :y 2))
        (assert (gethash (lui:widget-id :child context)
                         (context-activated context)))
        ;; Disabled passive containers also block hits, without disabling children.
        (setf clickable nil)
        (frame)
        (frame (make-event :kind :press :x 0 :y 0)
               (make-event :kind :release :x 0 :y 0))
        (assert (not outer))
        (frame (make-event :kind :press :x 2 :y 2)
               (make-event :kind :release :x 2 :y 2))
        (assert (gethash (lui:widget-id :child context)
                         (context-activated context)))
        ;; An ordinary container returns NIL even when its body returns true.
        (setf clickable nil disabled nil)
        (frame)
        (assert (not (first result)))
        (frame (make-event :kind :press :x 0 :y 0)
               (make-event :kind :release :x 0 :y 0))
        (assert outer)
        (assert (not (first result)))))))

(defun test-disabled-child-hit-blocking ()
  (let ((context (make-test-context))
        (disabled t)
        (outer nil))
    (flet ((frame (&rest events)
             (with-frame (context 50 20 :events (coerce events 'vector))
               (setf outer
                     (lui:column (:clickable-p t :width 40 :height 10)
                       (lui:button "Child" :id :child :width 10 :height 2
                                   :disabled-p disabled))))))
      (frame)
      (frame (make-event :kind :press :x 1 :y 1)
             (make-event :kind :release :x 1 :y 1))
      (assert (not outer))
      (assert (null (context-active context)))
      ;; Space outside the disabled child still belongs to its parent.
      (frame (make-event :kind :press :x 20 :y 5)
             (make-event :kind :release :x 20 :y 5))
      (assert outer)
      (setf disabled nil)
      (frame)
      (frame (make-event :kind :press :x 1 :y 1)
             (make-event :kind :release :x 1 :y 1))
      (assert (not outer))
      (assert (gethash (lui:widget-id :child context)
                       (context-activated context))))))

(defun test-clickable-table-row ()
  (let ((context (make-test-context))
        (activated nil))
    (flet ((draw ()
             (lui:table (:width 40 :column-gap 4)
               (setf activated
                     (lui:table-row (:clickable-p t :height 5)
                       (lui:table-cell () (lui:label "Name"))
                       (lui:table-cell () (lui:label "Email")))))))
      (with-frame (context 40 10) (draw))
      ;; Both columns and their intervening gap belong to the same row.
      (dolist (x '(1 19 38))
        (with-frame (context 40 10 :events
                             (vector (make-event :kind :press :x x :y 1)
                                     (make-event :kind :release :x x :y 1)))
          (draw))
        (assert activated)))))

(defun test-container-clipping ()
  (let ((context (make-test-context))
        (activated nil)
        (visible t))
    (flet ((draw ()
             (lui:column (:width 15 :height 5 :clip-p t :scroll-p t)
               (when visible
                 (setf activated
                       (lui:column (:id :clipped :width 25 :height 12
                                    :clickable-p t)
                         (lui:label "Content")))))))
      (with-frame (context 40 20) (draw))
      (assert (null (hit context 20 2)))
      (assert (null (hit context 2 8)))
      (assert (equal (hit context 2 2) (lui:widget-id :clipped context)))
      (with-frame (context 40 20 :events
                           (vector (make-event :kind :press :x 2 :y 2)))
        (draw))
      ;; Resize invalidates captured pointer geometry before a release.
      (with-frame (context 41 20 :events
                           (vector (make-event :kind :release :x 2 :y 2)))
        (draw))
      (assert (not activated))
      (with-frame (context 41 20 :events
                           (vector (make-event :kind :tab)
                                   (make-event :kind :press :x 2 :y 2)))
        (draw))
      (setf visible nil)
      (with-frame (context 41 20) (draw))
      (assert (null (context-focus context)))
      (assert (null (context-active context))))))

(defun run-tests ()
  (test-clickable-table-row)
  (test-container-clipping)
  (test-clickable-containers)
  (test-disabled-child-hit-blocking)
  (dolist (name '("FN" "CONDITIONS" "TEXT" "LAYOUT" "FRAME"
                  "WIDGETS" "INTERACTION"))
    (assert (find-package (concatenate 'string "%LUI." name)))
    (assert (null (find-package (concatenate 'string "LUI." name)))))
  (dolist (pair '((:lui.toolkit "FIND-TOOLKIT")
                  (:lui.palette "RESOLVE-PALETTE")))
    (assert (eq :external
                (nth-value 1
                  (find-symbol (concatenate 'string "%" (second pair))
                               (first pair)))))
    (assert (not (eq :external
                     (nth-value 1 (find-symbol (second pair)
                                               (first pair)))))))
  (test-styling-package-boundaries)
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
                     (%lui.frame::context-ids context)))
                 (appearance (id) (element-content (node id)))
                 (draw ()
                   (lui:with-toolkit ((progn (incf evaluations) style))
                     (assert (eq style (lui:current-toolkit)))
                     (lui:label "Plain label")
                     (%lui.tests.support::draw-button "Plain button" (list
                    :id :plain))
                     (%lui.tests.support::draw-button "Sized" (list :id
                    :sized :width (progn (incf evaluations)
                                                       (fixed 9))
                                                               :height
                                                               (fixed 2)))
                     (%lui.tests.support::draw-tab "Tab" (list :id :tab
                                                          :selected-p t))
                     (setf checked (%lui.tests.support::draw-checkbox "Check"
                                     (list :id :check :value checked))
                       number (%lui.tests.support::draw-slider (list
                      :id :slider :value number :minimum 0 :maximum 10
                                                       :step 1))
                       text (%lui.tests.support::draw-text-field (list
                      :id :field :value text)))
                     (%lui.tests.support::draw-cell "Cell" (list :id :cell
                                                            :selected-p t))
                     (%lui.tests.support::draw-list-item "Item" (list :id
                    :item :selected-p t))
                     (%lui.tests.support::draw-gauge 0.5 (list :id :gauge))
                     (%lui.tests.support::draw-canvas nil (list :id
                                                           :canvas))
                     (lui:panel (:id :panel :width (fixed 15)
                                 :padding 1)
                       (%lui.tests.support::draw-button "Inside"
                         (list :id :inside))
                       (lui:with-toolkit (:garnet)
                         (%lui.tests.support::draw-button "Nested"
                           (list :id :nested))))
                     (%lui.tests.support::draw-button "After" (list :id
                                                               :after))))
                 (frame (&rest events)
                   (with-frame (context 50 50 :events events) (draw))))
          (frame)
          (assert (= 2 evaluations))
          (assert (eq outer (lui:current-toolkit)))
          (dolist (id '(:plain :sized :tab :check :slider :field :cell :item
                        :gauge :canvas :panel :inside :after))
            (assert (eq style (%lui.widgets:widget-style (appearance id)))))
          (assert (eq :garnet
                      (%lui.widgets:widget-style (appearance :nested))))
          (assert (equal (getf (lui.toolkit:toolkit-defaults style)
                               :background)
                         (%lui.widgets:widget-background (appearance :plain))))
          (assert (= 9 (box-width (element-box (node :sized)))))
          (assert (= 2 (box-height (element-box (node :sized)))))
          (assert (= 15 (box-width (element-box (node :panel)))))
          (assert (= 1 (element-padding (node :panel))))
          (assert (not (element-interactive-p (node :gauge))))
          (dolist (id '(:tab :cell :item))
            (assert (%lui.widgets:widget-value (appearance id))))
          (frame (make-event :kind :activate :id :check)
                 (make-event :kind :change :id :slider :value 7)
                 (make-event :kind :change :id :field :value "edited"))
          (assert checked)
          (assert (= 7 number))
          (assert (equal "edited" text)))))
    ;; An explicit NIL option overrides a true toolkit default.
    (let ((lui.glass:*glass-defaults*
            (append '(:disabled-p t) lui.glass:*glass-defaults*))
          (context (make-test-context)))
      (with-frame (context 20 5)
        (lui:with-toolkit (:glass)
          (%lui.tests.support::draw-button "Inherited" (list :id
                                                        :inherited))
          (%lui.tests.support::draw-button "Enabled" (list :id :enabled
                                                      :disabled-p nil))))
      (assert (not (element-interactive-p
                     (gethash (lui:widget-id :inherited context)
                       (%lui.frame::context-ids context)))))
      (assert (element-interactive-p
                (gethash (lui:widget-id :enabled context)
                  (%lui.frame::context-ids context)))))
    (assert (handler-case (progn (lui:with-toolkit (:unknown) t) nil)
              (error () t)))
    (assert (eq outer (lui:current-toolkit))))
  (let ((received nil)
        (options (list :width (fixed 12)))
        (context (make-test-context)))
    (lui.toolkit:register-toolkit
     :test :parent :motif :defaults '(:accent "#123456")
     :controls
     (list (cons :button
                 (lambda (id text opts)
                   (setf received (list id text opts))
                   (apply #'%lui.widgets:declare-widget :button
                          (lui:current-toolkit) id text
                          (append opts (lui.toolkit:toolkit-defaults)))))))
    (lui.toolkit:register-toolkit :test-child :parent :test)
    (with-frame (context 30 10)
      (lui:with-toolkit (:test)
        (assert (eq :test (lui:current-toolkit)))
        (%lui.tests.support::draw-button "Custom" (list* :id :custom options))
        (lui:label "Inherited")
        (lui:panel (:id :custom-panel)
          (lui:label "Child"))))
    (assert (equal (list (lui:widget-key (first received)) (second received))
              '(:custom "Custom")))
    (assert (equal (third received) options))
    (assert (equal "#123456"
                   (getf (lui.toolkit:toolkit-defaults :test) :accent)))
    (assert (equal "#b8b8b8"
                   (getf (lui.toolkit:toolkit-defaults :test-child)
                         :background)))
    (let ((widget (element-content
                    (gethash (lui:widget-id :custom context)
                      (%lui.frame::context-ids context)))))
      (assert (eq :test (%lui.widgets:widget-style widget)))
      (assert (equal "#123456" (%lui.widgets:widget-accent widget)))))
  (format t "Public toolkit scopes, controls, options and panels passed.~%")
  t)
