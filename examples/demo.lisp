(defpackage #:lui.example
  (:use #:cl)
  (:export #:main #:draw #:make-gallery #:make-demo))
(in-package #:lui.example)

(defstruct gallery
  (seven (lui.example.seven:make-state))
  (page :controls)
  (toolkit :qt)
  (palette :default)
  (name "Common Lisp")
  (volume 0.4)
  (enabled t)
  (greeting "Hello")
  (tone :casual)
  (count 0)
  (editor "The quick brown fox jumps over the lazy dog.")
  (date nil)
  (filter "")
  (selection 1)
  (split 0.35)
  (alignment :start)
  (opacity 0.6)
  (frost 12)
  (radius 12)
  (preview "Ocean")
  (preview-color "#335d91")
  (preview-count 0)
  (frame-rate (lui.frame::make-frame-rate))
  (filtered-items nil)
  (last-filter nil))

(defparameter *toolkits* '(:glass :motif :garnet :macos :qt))
(defparameter *pages*
  '((:controls "Controls") (:editing "Editing") (:layout "Layout")
    (:scroll "Scroll") (:styles "Styles") (:seven "7GUIs")))

(defparameter *items*
  (coerce (loop :for i :from 1 :to 60
                :collect (format nil "Item ~2,'0D — selectable row" i))
          'vector))


(defun filtered-items (g)
  (unless (equal (gallery-filter g) (gallery-last-filter g))
    (setf (gallery-last-filter g) (copy-seq (gallery-filter g))
          (gallery-filtered-items g)
          (loop :for title :across *items* :for i :from 1
                :when (search (gallery-filter g) title :test #'char-equal)
                :collect i)))
  (gallery-filtered-items g))

(defun controls-page (g)
  (lui:label "Buttons, values, disabled controls, and shared state")
  (setf (gallery-name g) (lui:text-field :name (gallery-name g)
                                         (lui:opt :width (lui:grow))))
  (setf (gallery-volume g) (lui:slider :volume (gallery-volume g)
                                       (lui:opt :width (lui:grow))))
  (lui:label (format nil "Volume: ~D%" (round (* 100 (gallery-volume g)))))
  (setf (gallery-enabled g) (lui:checkbox :enabled (gallery-enabled g)
                                          "Enabled"))
  (lui:row (:gap (lui:units 1))
    (when (lui:button :hello "Say hello") (incf (gallery-count g)))
    (when (lui:button :reset "Reset") (setf (gallery-count g) 0))
    (lui:button :disabled "Disabled"
                (lui:opt :disabled-p t)))
  (lui:table (:width (lui:grow) :column-gap (lui:units 1) :gap (lui:units 0.5))
    (lui:table-row ()
      (lui:label "Greeting")
      (lui:table-cell ()
        (setf (gallery-greeting g)
              (lui:searchable-combobox :greeting (gallery-greeting g)
                                       '("Hello" "Bonjour" "Hola" "Hallo" "Ciao")
                                       (lui:opt :width (lui:grow) :accessible-name "Greeting")))))
    (lui:table-row ()
      (lui:label "Tone")
      (lui:row (:gap (lui:units 0.5))
        (setf (gallery-tone g)
              (lui:radio :casual (gallery-tone g) :casual "Casual")
              (gallery-tone g)
              (lui:radio :excited (gallery-tone g) :excited "Excited")))))
  (lui:label (format nil "~A ~A~A (~D)" (gallery-greeting g) (gallery-name g)
                     (if (eq (gallery-tone g) :excited) "!" "") (gallery-count g)))
  (lui:label "Hover, press, and use Tab to compare interaction states."))

(defun editing-page (g)
  (lui:label "Date")
  (setf (gallery-date g)
        (lui:date-picker :appointment (gallery-date g)))
  (lui:label "Readline-style editing")
  (setf (gallery-editor g) (lui:text-field :editor (gallery-editor g)
                                           (lui:opt :width (lui:grow))))
  (lui:label (format nil "~D characters" (length (gallery-editor g))))
  (when (lui:button :restore-text "Restore sample")
    (setf (gallery-editor g) "The quick brown fox jumps over the lazy dog."))
  (dolist (line '("Ctrl-A / Ctrl-E: beginning / end of line"
                  "Ctrl-B / Ctrl-F: backward / forward character"
                  "Alt-B / Alt-F: backward / forward word"
                  "Ctrl-K / Ctrl-U: kill to end / beginning"
                  "Ctrl-W / Alt-D: kill previous / next word"
                  "Ctrl-Y: yank killed text; Ctrl-T: transpose"
                  "Ctrl-D / Ctrl-H: delete / backspace"
                  "Shift + arrows: select; Ctrl-Shift-A: select all"))
    (lui:label line)))

(defun layout-page (g)
  (lui:label "Resize the window: percentages and grow share the space.")
  (setf (gallery-split g) (lui:slider :split (gallery-split g)
                                      (lui:opt :minimum 0.15 :maximum 0.7
                                               :step 0.05 :width (lui:grow))))
  (lui:row (:id :split-panels :width (lui:grow) :gap (lui:units 1)
            :height (lui:fit (lui:units 8)))
    (lui:panel (lui:opt :id :split-panel :width (lui:percent (gallery-split g))
                        :height (lui:grow)
                        :padding (lui:units 1))
      (lui:label (format nil "~D% width" (round (* 100 (gallery-split g)))))
      (lui:label "Text wraps as this panel becomes narrower."))
    (lui:panel (lui:opt :width (lui:grow) :height (lui:grow) :padding (lui:units 1))
      (lui:label "Grow")
      (lui:label "I take the remaining width, after gaps.")))
  (when (lui:button :align (format nil "Alignment: ~A" (gallery-alignment g)))
    (setf (gallery-alignment g) (case (gallery-alignment g)
                                  (:start :center) (:center :end)
                                  (otherwise :start))))
  (lui:panel (lui:opt :width (lui:grow) :height (lui:fixed (lui:units 6)) :direction :row
                      :align (gallery-alignment g) :cross-align :center
                      :padding (lui:units 1)
                      :gap (lui:units 1))
    (lui:button :fit-a "Fit")
    (lui:button :fit-b "Content-sized")
    (lui:button :fit-c "Items")))

(defun scroll-page (g)
  (lui:label
   "Filter, scroll, and select an item. Values survive page changes.")
  (setf (gallery-filter g) (lui:text-field :filter (gallery-filter g)
                                           (lui:opt :width (lui:grow))))
  (lui:label (format nil "Selected item: ~D" (gallery-selection g)))
  (lui:panel (lui:opt :id :results :width (lui:grow) :height (lui:grow) :scroll-p t
                      :padding (lui:units 1) :gap (lui:units 1))
    (loop :for i :in (filtered-items g)
          :for title := (aref *items* (1- i))
          :for alpha := (if (= i (gallery-selection g)) 0.85 0.3)
          :do (when (lui:button (list :item i) title
                                (lui:opt :width (lui:grow)
                                         :opacity alpha))
                (setf (gallery-selection g) i)))))

(defun styles-content (g)
  (lui:label "Customize the active toolkit.")
  (when (and (eq (gallery-toolkit g) :glass)
             (not (lui.frame:context-text-mode-p lui.frame:*context*)))
    (lui:label (format nil "Opacity: ~D%"
                       (round (* 100 (gallery-opacity g)))))
    (setf (gallery-opacity g) (lui:slider :opacity (gallery-opacity g)
                                          (lui:opt :width (lui:grow))))
    (lui:label (format nil "Frost: ~D; corner radius: ~D"
                       (round (gallery-frost g)) (round (gallery-radius g))))
    (setf (gallery-frost g) (lui:slider :frost (gallery-frost g)
                                        (lui:opt :maximum 24 :step 1
                                                 :width (lui:grow)))
          (gallery-radius g) (lui:slider :radius (gallery-radius g)
                                         (lui:opt :maximum 24 :step 1
                                                  :width (lui:grow)))))
  (let* ((terminal (lui.frame:context-text-mode-p lui.frame:*context*))
         (opacity (if terminal 1 (gallery-opacity g)))
         (frost (if terminal 0 (gallery-frost g)))
         (radius (if terminal 0 (gallery-radius g))))
    (flet ((sample (id title color)
             (lui:button id title
                         (lui:opt :width (lui:grow) :background color
                                  :foreground "#ffffff" :opacity opacity
                                  :radius radius :frost frost))))
      (lui:row (:width (lui:grow) :gap (lui:units 1))
        (loop :for color :in '("#335d91" "#81456d" "#286e63")
              :for title :in '("Ocean" "Orchid" "Forest")
              :for id := (list :sample title)
              :when
              (if (eq (gallery-toolkit g) :glass)
                  (sample id title color)
                  (lui:panel (lui:opt :width (lui:grow) :padding (lui:units 2)
                                      :gap (lui:units 1) :background color)
                    (lui:label title (lui:opt :foreground "#ffffff"))
                    (sample id "Preview" color)))
                :do (setf (gallery-preview g) title
                          (gallery-preview-color g) color)))
      (flet ((preview ()
               (let ((color (gallery-preview-color g)))
                 (lui:panel (lui:opt :id :style-preview :width (lui:grow)
                                     :padding (lui:units 1) :gap (lui:units 1)
                                     :background color :opacity opacity
                                     :frost frost :radius radius)
                   (lui:label (format nil "Preview: ~A" (gallery-preview g))
                              (lui:opt :foreground "#ffffff"))
                   (when (sample :preview-action "Try this style" color)
                     (incf (gallery-preview-count g)))
                   (lui:label (format nil "Activated ~D times"
                                      (gallery-preview-count g))
                              (lui:opt :foreground "#ffffff"))))))
        (if (or terminal (not (eq (gallery-toolkit g) :glass)))
            (preview)
            (progn
              (lui:label
               "Frost softens stripes; lower opacity reveals more backdrop.")
              (lui:column (:width (lui:grow) :height (lui:fixed (lui:units 14)) :clip-p t)
                (lui:row (:width (lui:grow) :height (lui:grow))
                  (dotimes (i 48)
                    (let ((color (if (evenp i) "#17304d" "#dbe7ed")))
                      (lui:panel (lui:opt :width (lui:grow) :height (lui:grow)
                                          :opacity 1 :radius 0 :frost 0
                                          :background color)))))
                (lui:column (:floating-p t :offset-x (lui:units 1) :offset-y (lui:units 1)
                         :width (lui:percent 0.95))
                  (preview)))))))))

(defun styles-page (g)
  (when (lui.frame:context-text-mode-p lui.frame:*context*)
    (lui:label
     "Terminal preview uses solid colors; no blur or transparency."))
  (styles-content g))

(defun modal-p (g)
  (lui.example.seven:modal-p (gallery-seven g)))

(defun draw-gallery (g)
  (lui:panel (lui:opt :id :window :width (lui:grow) :height (lui:grow)
                      :background (let ((colors (lui:toolkit-palette)))
                                    (getf colors :window-background (getf colors :background)))
                      :opacity 1 :radius 0 :frost 0
                      :padding (lui:units 1) :gap (lui:units 1))
    (lui:row (:width (lui:grow) :gap (lui:units 1) :cross-align :center)
      (lui:label "LUI feature gallery"
                 (lui:opt :width (lui:grow)))
      (lui:label (ecase (gallery-toolkit g)
                   (:glass "Toolkit: Glass") (:motif "Toolkit: Motif")
                   (:garnet "Toolkit: Garnet") (:macos "Toolkit: macOS") (:qt "Toolkit: Qt")))
      (lui:button :toolkit "Cycle toolkit"
                  (lui:opt :disabled-p (modal-p g)))
      (when (lui:button :debugger-toggle "Show debugger"
                        (lui:opt :disabled-p (modal-p g)))
        (lui:set-debugger-enabled t)))
    (lui:row (:width (lui:grow) :gap (lui:units 1) :cross-align :center)
      (lui:label (format nil "Palette: ~A" (string-capitalize (symbol-name (gallery-palette g)))))
      (lui:button :palette "Cycle palette" (lui:opt :disabled-p (modal-p g))))
    (lui:label (lui.frame::frame-rate-label (gallery-frame-rate g)))
    (lui:row (:width (lui:grow) :gap (lui:units 1))
      (dolist (page *pages*)
        (when (lui:tab (list :page (first page)) (second page)
                       (lui:opt :selected-p (eq (gallery-page g) (first page))
                                :disabled-p (modal-p g)))
          (setf (gallery-page g) (first page)))))
    (lui:panel (lui:opt :id (list :body (gallery-page g)) :width (lui:grow)
                        :height (lui:grow)
                        :scroll-p (not (member (gallery-page g)
                                              '(:scroll :seven)))
                        :padding (lui:units 1) :gap (lui:units 1))
      (case (gallery-page g)
        (:controls (controls-page g))
        (:editing (editing-page g))
        (:layout (layout-page g))
        (:scroll (scroll-page g))
        (:styles (styles-page g))
        (:seven
         (lui.example.seven:draw-content (gallery-seven g)))))))

(defun draw (g)
  (when (and (not (modal-p g)) (lui:activated-p :toolkit))
    (setf (gallery-toolkit g) (or (second (member (gallery-toolkit g)
                                                  *toolkits*))
                                  (first *toolkits*))))
  (when (and (not (modal-p g)) (lui:activated-p :palette))
    (let ((names (lui:available-palettes)))
      (setf (gallery-palette g)
            (aref names (mod (1+ (position (gallery-palette g) names)) (length names))))))
  (lui:with-toolkit ((gallery-toolkit g))
    (lui:with-palette ((gallery-palette g))
      (draw-gallery g))))

(defun make-demo (&optional (gallery (make-gallery)))
  (lambda () (draw gallery)))

(defun main ()
  (lui:run (make-demo) :title "LUI feature gallery"))
