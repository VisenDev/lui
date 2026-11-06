(defpackage #:lui.example
  (:use #:cl #:lui #:lui.layout #:lui.frame #:lui.debug)
  (:shadow #:draw)
  (:export #:main #:draw))
(in-package #:lui.example)

(defvar *debug-state* (make-state))
(defvar *page* :controls)
(defvar *toolkit* :glass)
(defparameter *toolkits* '(:glass :motif :garnet))
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
    (:scroll "Scroll") (:styles "Styles") (:seven "7GUIs")))

(defparameter *items*
  (coerce (loop :for i :from 1 :to 60
                :collect (format nil "Item ~2,'0D — selectable row" i))
          'vector))

(defvar *filtered-items* nil)
(defvar *last-filter* nil)

(defun filtered-items ()
  (unless (equal *filter* *last-filter*)
    (setf *last-filter* (copy-seq *filter*)
          *filtered-items*
          (loop :for title :across *items* :for i :from 1
                :when (search *filter* title :test #'char-equal)
                :collect i)))
  *filtered-items*)

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
  (lui:label "Buttons, values, disabled controls, and shared state")
  (setf *name* (lui:text-field :name *name*
                               (lui:opt :width (grow))))
  (setf *volume* (lui:slider :volume *volume*
                             (lui:opt :width (grow))))
  (lui:label (format nil "Volume: ~D%" (round (* 100 *volume*))))
  (setf *enabled* (lui:checkbox :enabled *enabled* "Enabled"))
  (row (:gap (units 1))
    (when (lui:button :hello "Say hello") (incf *count*))
    (when (lui:button :reset "Reset") (setf *count* 0))
    (lui:button :disabled "Disabled"
                (lui:opt :disabled-p t)))
  (lui:label (format nil "Hello ~A (~D)" *name* *count*))
  (lui:label "Hover, press, and use Tab to compare interaction states."))

(defun editing-page ()
  (lui:label "Readline-style editing")
  (setf *editor* (lui:text-field :editor *editor*
                                 (lui:opt :width (grow))))
  (lui:label (format nil "~D characters" (length *editor*)))
  (when (lui:button :restore-text "Restore sample")
    (setf *editor* "The quick brown fox jumps over the lazy dog."))
  (dolist (line '("Ctrl-A / Ctrl-E: beginning / end of line"
                  "Ctrl-B / Ctrl-F: backward / forward character"
                  "Alt-B / Alt-F: backward / forward word"
                  "Ctrl-K / Ctrl-U: kill to end / beginning"
                  "Ctrl-W / Alt-D: kill previous / next word"
                  "Ctrl-Y: yank killed text; Ctrl-T: transpose"
                  "Ctrl-D / Ctrl-H: delete / backspace"
                  "Shift + arrows: select; Ctrl-Shift-A: select all"))
    (lui:label line)))

(defun layout-page ()
  (lui:label "Resize the window: percentages and grow share the space.")
  (setf *split* (lui:slider :split *split*
                            (lui:opt :minimum 0.15 :maximum 0.7
                                     :step 0.05 :width (grow))))
  (row (:id :split-panels :width (grow) :gap (units 1)
            :height (fit (units 8)))
    (lui:panel (lui:opt :id :split-panel :width (percent *split*) :height (grow)
                        :padding (units 1))
      (lui:label (format nil "~D% width" (round (* 100 *split*))))
      (lui:label "Text wraps as this panel becomes narrower."))
    (lui:panel (lui:opt :width (grow) :height (grow) :padding (units 1))
      (lui:label "Grow")
      (lui:label "I take the remaining width, after gaps.")))
  (when (lui:button :align (format nil "Alignment: ~A" *alignment*))
    (setf *alignment* (case *alignment*
                        (:start :center) (:center :end) (otherwise :start))))
  (lui:panel (lui:opt :width (grow) :height (fixed (units 6)) :direction :row
                      :align *alignment* :cross-align :center :padding (units 1)
                      :gap (units 1))
    (lui:button :fit-a "Fit")
    (lui:button :fit-b "Content-sized")
    (lui:button :fit-c "Items")))

(defun scroll-page ()
  (lui:label "Filter, scroll, and select an item. Values survive page changes.")
  (setf *filter* (lui:text-field :filter *filter*
                                 (lui:opt :width (grow))))
  (lui:label (format nil "Selected item: ~D" *selection*))
  (lui:panel (lui:opt :id :results :width (grow) :height (grow) :scroll-p t
                      :padding (units 1) :gap (units 1))
    (loop :for i :in (filtered-items)
          :for title := (aref *items* (1- i))
          :do (when (lui:button (list :item i) title
                                (lui:opt :width (grow)
                                         :opacity (if (= i *selection*) 0.85 0.3)))
                (setf *selection* i)))))

(defun styles-content ()
  (lui:label "Customize the active collection without mixing toolkits.")
  (when (and (eq *toolkit* :glass) (/= *unit* 1))
    (lui:label (format nil "Opacity: ~D%" (round (* 100 *opacity*))))
    (setf *opacity* (lui:slider :opacity *opacity*
                                (lui:opt :width (grow))))
    (lui:label (format nil "Frost: ~D; corner radius: ~D"
                       (round *frost*) (round *radius*)))
    (setf *frost* (lui:slider :frost *frost*
                              (lui:opt :maximum 24 :step 1
                                       :width (grow)))
          *radius* (lui:slider :radius *radius*
                               (lui:opt :maximum 24 :step 1
                                        :width (grow)))))
  (row (:width (grow) :gap (units 1))
    (loop :for color :in '("#335d91" "#81456d" "#286e63")
          :for title :in '("Ocean" "Orchid" "Forest")
          :do (if (eq *toolkit* :glass)
                  (when (lui:button (list :sample title) title
                                    (lui:opt :width (grow) :background color
                                             :foreground "#ffffff" :opacity *opacity*
                                             :frost *frost* :radius *radius*))
                    (setf *preview* title *preview-color* color))
                  (lui:panel (lui:opt :width (grow) :padding (units 2) :gap (units 1)
                                      :background color :opacity *opacity*
                                      :frost *frost* :radius *radius*)
                    (lui:label title
                               (lui:opt :foreground "#ffffff"))
                    (when (lui:button (list :sample title) "Preview"
                                      (lui:opt :background color :foreground "#ffffff"
                                               :opacity *opacity* :frost *frost*
                                               :radius *radius*))
                      (setf *preview* title *preview-color* color))))))
  (flet ((preview ()
           (lui:panel (lui:opt :id :style-preview :width (grow)
                               :padding (units 1) :gap (units 1)
                               :background *preview-color* :opacity *opacity*
                               :frost *frost* :radius *radius*)
             (lui:label (format nil "Preview: ~A" *preview*)
                        (lui:opt :foreground "#ffffff"))
             (when (lui:button :preview-action "Try this style"
                               (lui:opt :background *preview-color* :foreground "#ffffff"
                                        :opacity *opacity* :radius *radius* :frost *frost*))
               (incf *preview-count*))
             (lui:label (format nil "Activated ~D times" *preview-count*)
                        (lui:opt :foreground "#ffffff")))))
    (if (and (eq *toolkit* :glass) (/= *unit* 1))
        (progn
          (lui:label "Frost softens stripes; lower opacity reveals more backdrop.")
          (column (:width (grow) :height (fixed (units 14)) :clip-p t)
            ;; Opaque detail makes backdrop blur and tint independently visible.
            (row (:width (grow) :height (grow))
              (dotimes (stripe 48)
                (lui:panel (lui:opt :width (grow) :height (grow) :opacity 1
                                    :radius 0 :frost 0
                                    :background (if (evenp stripe) "#17304d" "#dbe7ed")))))
            (column (:floating-p t :offset-x (units 1) :offset-y (units 1)
                                 :width (percent 0.95))
              (preview))))
        (preview))))

(defun styles-page ()
  (if (= *unit* 1)
      (let ((*opacity* 1) (*frost* 0) (*radius* 0))
        (lui:label "Terminal preview uses solid colors; no blur or transparency.")
        (styles-content))
      (styles-content)))

(defun modal-p ()
  (lui.example.seven:modal-p lui.example.seven:*state*))

(defun draw-gallery ()
  (lui:panel (lui:opt :id :window :width (grow) :height (grow)
                      :background (ecase *toolkit*
                                    (:glass "#202430") (:motif "#b8b8b8")
                                    (:garnet "#ffffff"))
                      :opacity 1 :radius 0 :frost 0
                      :padding (units 1) :gap (units 1))
    (row (:width (grow) :gap (units 1) :cross-align :center)
      (lui:label "LUI feature gallery"
                 (lui:opt :width (grow)))
      (lui:button :toolkit
                  (ecase *toolkit*
                    (:glass "Glass") (:motif "Motif") (:garnet "Garnet"))
                  (lui:opt :disabled-p (modal-p)))
      (when (lui:button :debugger-toggle "Debug"
                        (lui:opt :disabled-p (modal-p)))
        (setf (state-open-p *debug-state*)
              (not (state-open-p *debug-state*)))
        (request-frame)))
    (lui:label (if (= *unit* 1) "Terminal: event-driven rendering"
                   (format nil "~,1F FPS · ~,2F ms/frame"
                           *fps* *frame-ms*)))
    (row (:width (grow) :gap (units 1))
      (dolist (page *pages*)
        (when (lui:tab (list :page (first page)) (second page)
                       (lui:opt :selected-p (eq *page* (first page))
                                :disabled-p (modal-p)))
          (setf *page* (first page)))))
    (lui:panel (lui:opt :id (list :body *page*) :width (grow) :height (grow)
                        :scroll-p (not (member *page* '(:scroll :seven)))
                        :padding (units 1) :gap (units 1))
      (case *page*
        (:controls (controls-page))
        (:editing (editing-page))
        (:layout (layout-page))
        (:scroll (scroll-page))
        (:styles (styles-page))
        (:seven
         (lui.example.seven:draw-content lui.example.seven:*state*))))))

(defun draw ()
  (update-fps)
  (when (and (not (modal-p)) (activated-p :toolkit))
    (setf *toolkit* (or (second (member *toolkit* *toolkits*))
                        (first *toolkits*))))
  (lui:with-toolkit (*toolkit*)
    (lui.debug:draw #'draw-gallery :state *debug-state* :toolkit *toolkit*)))

(defun main ()
  (run #'draw :title "LUI feature gallery"))
