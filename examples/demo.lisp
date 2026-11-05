(defpackage #:lui.example
  (:use #:cl #:lui #:lui.layout #:lui.frame)
  (:export #:main #:draw))
(in-package #:lui.example)

(defvar *page* :controls)
(defvar *toolkit* :glass)
(defvar *name* "Common Lisp")
(defvar *volume* 0.4)
(defvar *enabled* t)
(defvar *count* 0)
(defvar *editor* "The quick brown fox jumps over the lazy dog.")
(defvar *filter* "")
(defvar *selection* 1)
(defvar *split* 0.35)
(defvar *alignment* :start)
(defvar *opacity* 0.6)
(defvar *frost* 12)
(defvar *radius* 12)
(defvar *preview* "Ocean")
(defvar *preview-color* "#335d91")
(defvar *preview-count* 0)
(defvar *fps* 0.0)
(defvar *frame-ms* 0.0)
(defvar *frame-count* 0)
(defvar *frame-start* nil)
(defparameter *pages*
  '((:controls "Controls") (:editing "Editing") (:layout "Layout")
    (:scroll "Scroll") (:styles "Styles")))

(defun toolkit-package ()
  (if (eq *toolkit* :glass) "LUI.GLASS" "LUI.MOTIF"))

(defun widget (name &rest arguments)
  (apply (symbol-function (find-symbol (symbol-name name) (toolkit-package)))
         arguments))

(defmacro panel ((&rest options) &body body)
  `(let ((*parent*
           (lui.widgets:declare-panel
            *toolkit* (append (list ,@options)
                             (symbol-value
                              (find-symbol "*DEFAULTS*"
                                           (toolkit-package)))))))
     ,@body))

(defun update-fps ()
  (let ((now (get-internal-real-time)))
    (unless *frame-start*
      (setf *frame-start* now)
      (return-from update-fps nil))
    (incf *frame-count*)
    (let ((elapsed (/ (- now *frame-start*)
                      (* 1.0 internal-time-units-per-second))))
      (when (>= elapsed 0.5)
        (setf *fps* (/ *frame-count* elapsed)
              *frame-ms* (/ (* elapsed 1000) *frame-count*)
              *frame-count* 0 *frame-start* now)))))

(defun controls-page ()
  (widget :label "Buttons, values, disabled controls, and shared state")
  (setf *name* (widget :text-field :name *name* :width (grow)))
  (setf *volume* (widget :slider :volume *volume* :width (grow)))
  (widget :label (format nil "Volume: ~D%" (round (* 100 *volume*))))
  (setf *enabled* (widget :checkbox :enabled *enabled* "Enabled"))
  (row (:gap (units 1))
    (when (widget :button :hello "Say hello") (incf *count*))
    (when (widget :button :reset "Reset") (setf *count* 0))
    (widget :button :disabled "Disabled" :disabled-p t))
  (widget :label (format nil "Hello ~A (~D)" *name* *count*))
  (widget :label "Hover, press, and use Tab to compare interaction states."))

(defun editing-page ()
  (widget :label "Readline-style editing")
  (setf *editor* (widget :text-field :editor *editor* :width (grow)))
  (widget :label (format nil "~D characters" (length *editor*)))
  (when (widget :button :restore-text "Restore sample")
    (setf *editor* "The quick brown fox jumps over the lazy dog."))
  (dolist (line '("Ctrl-A / Ctrl-E: beginning / end of line"
                  "Ctrl-B / Ctrl-F: backward / forward character"
                  "Alt-B / Alt-F: backward / forward word"
                  "Ctrl-K / Ctrl-U: kill to end / beginning"
                  "Ctrl-W / Alt-D: kill previous / next word"
                  "Ctrl-Y: yank killed text; Ctrl-T: transpose"
                  "Ctrl-D / Ctrl-H: delete / backspace"
                  "Shift + arrows: select; Ctrl-Shift-A: select all"))
    (widget :label line)))

(defun layout-page ()
  (widget :label "Resize the window: percentages and grow share the space.")
  (setf *split* (widget :slider :split *split* :minimum 0.15 :maximum 0.7
                        :step 0.05 :width (grow)))
  (row (:width (grow) :gap (units 1) :height (fixed (units 8)))
    (panel (:width (percent *split*) :height (grow) :padding (units 1))
      (widget :label (format nil "~D% width" (round (* 100 *split*))))
      (widget :label "Text wraps as this panel becomes narrower."))
    (panel (:width (grow) :height (grow) :padding (units 1))
      (widget :label "Grow")
      (widget :label "I take the remaining width, after gaps.")))
  (when (widget :button :align (format nil "Alignment: ~A" *alignment*))
    (setf *alignment* (case *alignment*
                        (:start :center) (:center :end) (otherwise :start))))
  (panel (:width (grow) :height (fixed (units 6)) :direction :row
          :align *alignment* :cross-align :center :padding (units 1)
          :gap (units 1))
    (widget :button :fit-a "Fit")
    (widget :button :fit-b "Content-sized")
    (widget :button :fit-c "Items")))

(defun scroll-page ()
  (widget :label "Filter, scroll, and select an item. Values survive page changes.")
  (setf *filter* (widget :text-field :filter *filter* :width (grow)))
  (widget :label (format nil "Selected item: ~D" *selection*))
  (panel (:id :results :width (grow) :height (grow) :scroll-p t
          :padding (units 1) :gap (units 1))
    (loop :for i :from 1 :to 60
          :for title := (format nil "Item ~2,'0D — selectable row" i)
          :when (search *filter* title :test #'char-equal)
            :do (when (widget :button (list :item i) title :width (grow)
                              :opacity (if (= i *selection*) 0.85 0.3))
                  (setf *selection* i)))))

(defun styles-page ()
  (widget :label "Customize the active collection without mixing toolkits.")
  (widget :label (format nil "Opacity: ~D%" (round (* 100 *opacity*))))
  (setf *opacity* (widget :slider :opacity *opacity* :width (grow)))
  (when (eq *toolkit* :glass)
    (widget :label (format nil "Frost: ~D; corner radius: ~D"
                           (round *frost*) (round *radius*)))
    (setf *frost* (widget :slider :frost *frost* :maximum 24 :step 1
                          :width (grow))
          *radius* (widget :slider :radius *radius* :maximum 24 :step 1
                           :width (grow))))
  (row (:width (grow) :gap (units 1))
    (loop :for color :in '("#335d91" "#81456d" "#286e63")
          :for title :in '("Ocean" "Orchid" "Forest")
          :do (panel (:width (grow) :padding (units 2) :gap (units 1)
                      :background color :opacity *opacity*
                      :frost *frost* :radius *radius*)
                (widget :label title :foreground "#ffffff")
                (when (widget :button (list :sample title) "Preview"
                              :background color :foreground "#ffffff"
                              :opacity *opacity* :frost *frost*
                              :radius *radius*)
                  (setf *preview* title *preview-color* color)))))
  (panel (:width (grow) :padding (units 1) :gap (units 1)
          :background *preview-color* :opacity *opacity*
          :frost *frost* :radius *radius*)
    (widget :label (format nil "Preview: ~A" *preview*)
            :foreground "#ffffff")
    (when (widget :button :preview-action "Try this style"
                  :background *preview-color* :foreground "#ffffff"
                  :opacity *opacity* :radius *radius* :frost *frost*)
      (incf *preview-count*))
    (widget :label (format nil "Activated ~D times" *preview-count*)
            :foreground "#ffffff")))

(defun draw ()
  (update-fps)
  (when (activated-p :toolkit)
    (setf *toolkit* (if (eq *toolkit* :glass) :motif :glass)))
  (panel (:id :window :width (grow) :height (grow)
          :background (if (eq *toolkit* :glass) "#202430" "#b8b8b8")
          :opacity 1 :radius 0 :frost 0
          :padding (units 1) :gap (units 1))
    (row (:width (grow) :gap (units 1) :cross-align :center)
      (widget :label "LUI feature gallery" :width (grow))
      (widget :button :toolkit
              (if (eq *toolkit* :glass) "Glass" "Motif")))
    (widget :label (if (= *unit* 1) "Terminal: event-driven rendering"
                       (format nil "~,1F FPS · ~,2F ms/frame"
                               *fps* *frame-ms*)))
    (row (:width (grow) :gap (units 1))
      (dolist (page *pages*)
        (when (widget :tab (list :page (first page)) (second page)
                      :selected-p (eq *page* (first page)))
          (setf *page* (first page)))))
    (panel (:id (list :body *page*) :width (grow) :height (grow)
            :scroll-p (not (eq *page* :scroll))
            :padding (units 1) :gap (units 1))
      (case *page*
        (:controls (controls-page))
        (:editing (editing-page))
        (:layout (layout-page))
        (:scroll (scroll-page))
        (:styles (styles-page))))))

(defun main ()
  (run #'draw :title "LUI feature gallery"))
