(defpackage #:lui.widgets
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame)
  (:export #:widget #:widget-p #:widget-kind #:widget-style #:widget-text
           #:widget-color #:widget-palette #:widget-foreground #:widget-background #:widget-radius
           #:widget-frost #:widget-terminal-border
           #:widget-terminal-text #:declare-panel #:declare-widget
           #:value-widget
           #:scrollbar-thumb #:make-widget
           #:widget-display-value #:widget-password-p
           #:widget-value #:widget-minimum #:widget-maximum #:widget-step
           #:widget-font-size #:widget-font-family #:widget-font-weight
           #:widget-opacity #:widget-accent
           #:widget-disabled-p #:widget-orientation #:widget-accessible-name
           #:widget-painter
           #:edit-state #:edit-state-cursor
           #:edit-state-anchor #:make-edit-state #:edit-text #:readline-key
           #:text-field-focused-p #:activation-focused-p #:cursor-at))

(in-package #:lui.widgets)

(fn (muted-ink string) ((foreground string) (background string))
  "Soften a foreground color against its surface for secondary text."
  (if (every (lambda (color) (and (= (length color) 7) (char= (char color 0) #\#)))
             (list foreground background))
      (with-output-to-string (stream)
        (write-char #\# stream)
        (loop :for i :in '(1 3 5)
              :for fg := (parse-integer foreground
                                       :start i :end (+ i 2) :radix 16)
              :for bg := (parse-integer background
                                       :start i :end (+ i 2) :radix 16)
              :do (format stream "~2,'0X" (round (+ (* 2 fg) bg) 3))))
      foreground))

(defparameter *base-palette*
  '(:foreground "#ffffff" :background "#303040" :accent "#258bff"
    :disabled "#777777" :selection "#e7effa" :border "#939ba5" :outline "#000000"
    :thumb "#ffffff" :on-accent "#ffffff" :light "#ffffff" :shadow "#000000" :track "#777777"
    :disabled-accent "#999999" :disabled-surface "#a0a0a0"
    :bevel-light "#ffffff" :bevel-dark "#505050"
    :disabled-bevel-light "#d0d0d0" :disabled-bevel-dark "#989898"
    :cell-background "#ffffff" :cell-foreground "#202430"))

(defstruct widget
  "Backend-neutral control content, values, appearance, and extension callbacks."
  (palette (copy-list *base-palette*) :type list)
  (kind :label :type symbol)
  (style :glass :type symbol)
  icon
  (center-text-p nil :type boolean)
  (orientation :vertical :type (member :vertical :horizontal))
  (accessible-name nil :type (or null string))
  value
  (password-p nil :type boolean)
  (minimum 0 :type real)
  (maximum 1 :type real)
  (step 0.01f0 :type real)
  (font-size 16 :type real)
  (font-family :sans-serif :type (member :sans-serif :monospace))
  (font-weight :normal :type (member :normal :bold))
  (opacity 0.85f0 :type real)
  (accent "#258bff" :type string)
  (disabled-p nil :type boolean)
  (terminal-label nil :type (or null function))
  ;; Top-left/right, bottom-left/right, horizontal and vertical glyphs.
  (terminal-border nil :type (or null (string 6)))
  (painter nil :type (or null function))
  (text "" :type string)
  (terminal-cache nil :type (or null string))
  (foreground "#ffffff" :type string)
  (background "#303040" :type string)
  (radius 12 :type real)
  (frost 12 :type real))

(fn (palette-color (or null string)) ((palette list) (role symbol)
                                     &optional ((default (or null string)) nil))
  ;; Palette lookup stays small and allocation-free in the per-widget hot path.
  (cond ((null palette) default)
        ((eq (car palette) role) (cadr palette))
        (t (palette-color (cddr palette) role default))))

(fn (widget-color (or null string)) ((widget widget) (role symbol))
  "Resolve ROLE using WIDGET's color overrides and captured semantic palette."
  (case role
    (:foreground (widget-foreground widget))
    (:background (widget-background widget))
    (:accent (widget-accent widget))
    (otherwise (palette-color (widget-palette widget) role))))

(fn (widget-display-value t) ((widget widget))
  "Return the value for presentation, masking password fields."
  (let ((value (widget-value widget)))
    (if (and (widget-password-p widget)
             (eq (widget-kind widget) :text-field))
        (make-string (length value) :initial-element #\*) value)))

(fn (widget-terminal-text string) ((widget widget))
  "Return WIDGET's portable text representation, computing it lazily as needed.
An optional terminal-label callback overrides the standard kind-based label."
  (or (widget-terminal-cache widget)
      (setf (widget-terminal-cache widget)
            (if (widget-terminal-label widget)
                (funcall (widget-terminal-label widget) widget)
                (let ((text (widget-text widget))
                      (value (widget-display-value widget)))
              (case (widget-kind widget)
                ((:label :list-item :cell) text)
                ((:panel :canvas) "")
                (:gauge
                 (let ((filled (round (* 10 (min 1 (max 0 value))))))
                   (format nil "[~A~A] ~D%"
                           (make-string filled :initial-element #\#)
                           (make-string (- 10 filled) :initial-element #\.)
                           (round (* 100 (min 1 (max 0 value)))))))
                (:checkbox (format nil "[~A] ~A" (if value "x" " ") text))
                (:radio (format nil "(~A) ~A" (if value "*" " ") text))
                (:slider
                 (format nil "~A [~D%]" text
                         (round (* 100 (/ (- value (widget-minimum widget))
                                           (- (widget-maximum widget)
                                              (widget-minimum widget)))))))
                (:text-field (format nil "[~A]" (if (zerop (length value)) text value)))
                (:tab (format nil (if value "[ ~A ]" "  ~A  ") text))
                (otherwise
                 (format nil (if (zerop (widget-radius widget))
                                 "[ ~A ]" "( ~A )") text))))))))

(fn (tab-arrow-p boolean) ((event event))
  (and (eq (event-kind event) :key)
       (not (null (member (event-key event) '(:left :right :home :end))))))

(fn (navigate-tabs (values)) ()
  (when (and (not (context-tabs-handled-p *context*))
             (context-previous-root *context*)
             (loop :for events :being :the :hash-values
                     :of (context-events *context*)
                   :thereis (some #'tab-arrow-p events)))
    (setf (context-tabs-handled-p *context*) t)
    (walk-elements
     (context-previous-root *context*)
     (lambda (parent)
       (let ((tabs (remove-if-not
                    (lambda (node)
                      (let ((widget (element-content node)))
                        (and (widget-p widget) (eq (widget-kind widget) :tab)
                             (element-interactive-p node))))
                    (coerce (element-children parent) 'list))))
         (dolist (tab tabs)
           (let* ((id (element-id tab))
                  (events (gethash id (context-events *context*)))
                  (arrows (remove-if-not #'tab-arrow-p (reverse events))))
             (dolist (event arrows)
               (let* ((index (or (position (context-focus *context*) tabs
                                           :key #'element-id
                                           :test #'equal) 0))
                      (next (ecase (event-key event)
                              (:home 0) (:end (1- (length tabs)))
                              (:left (mod (1- index) (length tabs)))
                              (:right (mod (1+ index) (length tabs)))))
                      (target (element-id (nth next tabs))))
                 (dolist (node tabs)
                   (remhash (element-id node) (context-activated *context*)))
                 (setf (context-focus-visible-p *context*) t
                       (context-focus *context*) target)
                 (record-activation *context* target)))
             (when arrows
               (setf (gethash id (context-events *context*))
                     (remove-if (lambda (event) (member event arrows))
                                events)))))))))
  (values))

(fn (declare-widget boolean)
    ((kind symbol) (style symbol) id (text string) &key ((width sizing) (fit))
     ((height sizing) (fit)) ((padding real) 0)
     ((floating-p boolean) nil) ((offset-x real) 0) ((offset-y real) 0)
     ((foreground string) "#ffffff") ((background string) "#303040")
     ((radius real) 12) ((frost real) 12) value ((minimum real) 0)
     ((maximum real) 1) ((step real) 0.01f0) ((font-size real) 16)
     ((font-family symbol) :sans-serif) ((font-weight symbol) :normal)
     ((opacity real) 0.85f0) ((accent string) "#258bff") (disabled-p nil)
     painter terminal-label ((terminal-border (or null (string 6))) nil)
     accessible-name icon center-text-p (password-p nil)
     (palette *base-palette*))
  "Declare a low-level widget in the current frame using STYLE and stable ID.
Layout, typography, colors, optical effects, and backend extension callbacks
are supplied as keywords. Return activation for enabled actionable kinds.
Most applications should use the public LUI controls with LUI:OPT instead."
  (when (eq kind :tab) (navigate-tabs))
  (let ((measure (or (context-measure *context*)
                     (error "A backend text measurer is required.")))
        (widget
          (make-widget
           :kind kind :style style :palette (copy-list palette) :text text :foreground foreground
           :background background :radius radius :frost frost :value value
           :minimum minimum :maximum maximum :step step :font-size font-size
           :font-family font-family :font-weight font-weight
           :opacity opacity :accent accent
           :disabled-p (not (null disabled-p)) :painter painter
           :icon icon :center-text-p center-text-p :terminal-label terminal-label
           :password-p (not (null password-p))
           :terminal-border terminal-border
           :accessible-name accessible-name)))
    (emit (make-element
           :id id :content widget :width width :height height :padding padding
           :floating-p floating-p :offset-x offset-x :offset-y offset-y
           :interactive-p (and (not disabled-p)
                               (not (or (eq kind :label) (eq kind :gauge))))
           :pointer-focus-p (eq kind :text-field)
           :measure (lambda (available) (funcall measure widget available))))
    (and (not disabled-p)
         (or (eq kind :button) (eq kind :tab)
             (eq kind :list-item) (eq kind :cell))
         (activated-p id))))

(defstruct edit-state
  "Persistent text-editor caret, selection anchor, kill buffer, and command history."
  (cursor 0 :type integer)
  (anchor 0 :type integer)
  (kill "" :type string)
  (last-command nil :type symbol))

(fn (focused-widget (or null widget)) ((context context))
  (when (context-root context)
    (let ((node (gethash (context-focus context)
                         (lui.frame::context-ids context))))
      (when node (element-content node)))))

(fn (text-field-focused-p boolean) ((context context))
  "Whether CONTEXT focuses an enabled text field in its current completed tree."
  (let ((widget (focused-widget context)))
    (and (widget-p widget) (eq (widget-kind widget) :text-field)
         (not (widget-disabled-p widget)))))

(fn (activation-focused-p boolean) ((context context))
  "Whether CONTEXT focuses an enabled button, checkbox, tab, list item, or cell.
Backends use this to activate controls with Space without stealing editor text."
  (let ((widget (focused-widget context)))
    (and (widget-p widget) (not (widget-disabled-p widget))
         (not (null (member (widget-kind widget)
                            '(:button :checkbox :radio :tab :list-item :cell)))))))

(fn (cursor-at symbol) ((context context) (x real) (y real))
  "Return the cursor kind at X,Y, respecting clipping and topmost widgets.
Kinds include :DEFAULT, :POINTER, :TEXT, both resize directions, and :NOT-ALLOWED."
  (let ((cursor :default))
    (when (context-root context)
      (walk-elements
       (context-root context)
       (lambda (node)
         (let ((widget (element-content node))
               (clip (element-clip node)))
           (when (and (widget-p widget)
                      (<= (box-x clip) x)
                      (< x (+ (box-x clip) (box-width clip)))
                      (<= (box-y clip) y)
                      (< y (+ (box-y clip) (box-height clip))))
             (setf cursor
                   (cond ((widget-disabled-p widget)
                          (if (eq (widget-kind widget) :cell)
                              :default :not-allowed))
                         ((eq (widget-kind widget) :splitter)
                          (if (eq (widget-orientation widget) :horizontal)
                              :resize-vertical :resize-horizontal))
                         ((member (widget-kind widget) '(:label :text-field))
                          :text)
                         ((member (widget-kind widget)
                                  '(:button :checkbox :radio :tab :slider
                                    :list-item :cell)) :pointer)
                         (t :default))))))))
    cursor))

(fn (readline-key symbol) ((key string) &key control alt shift)
  "Translate modified keys to shared editor commands; NIL leaves native handling."
  (let* ((name (string-downcase key))
         (arrow (cond ((member name '("left" "arrowleft") :test #'string=)
                       :word-left)
                      ((member name '("right" "arrowright") :test #'string=)
                       :word-right))))
    (cond
      ((and control (string= name "c")) :copy)
      ((and control shift (string= name "a")) :select-all)
      ((and (or control alt) arrow)
       (if shift
           (if (eq arrow :word-left) :shift-word-left :shift-word-right)
           arrow))
      (control
       (let ((command (cdr (assoc name
                                 '(("a" . :home) ("e" . :end)
                                   ("b" . :left) ("f" . :right)
                                   ("p" . :up) ("n" . :down)
                                   ("d" . :delete) ("h" . :backspace)
                                   ("k" . :kill-end) ("u" . :kill-start)
                                   ("w" . :kill-word) ("y" . :yank)
                                   ("t" . :transpose))
                                 :test #'string=))))
         (if shift
             (case command
               (:home :shift-home) (:end :shift-end)
               (:left :shift-left) (:right :shift-right)
               (otherwise command))
             command)))
      (alt
       (cdr (assoc name '(("b" . :word-left) ("f" . :word-right)
                         ("d" . :kill-word-forward)
                         ("backspace" . :kill-word))
                   :test #'string=))))))

(fn (line-start integer) ((text string) (cursor integer))
  (let ((newline (position #\Newline text :end cursor :from-end t)))
    (if newline (1+ newline) 0)))

(fn (line-end integer) ((text string) (cursor integer))
  (or (position #\Newline text :start cursor) (length text)))

(fn (word-position integer) ((text string) (cursor integer)
                            (direction integer) &optional whitespace)
  (let ((index (if (minusp direction) (1- cursor) cursor)))
    (flet ((word-p (character)
             (if whitespace
                 (not (member (char-code character) '(9 10 13 32)))
                 (alphanumericp character))))
      (loop :while (and (<= 0 index) (< index (length text))
                        (not (word-p (char text index))))
            :do (incf index direction))
      (loop :while (and (<= 0 index) (< index (length text))
                        (word-p (char text index)))
            :do (incf index direction)))
    (if (minusp direction) (1+ index) index)))

(fn (edit-text string) ((text string) (state edit-state) (events sequence))
  "Apply ordered editor EVENTS to TEXT using mutable caret/selection STATE.
Return the new text; preserve the editor's kill/yank state between frames.
Events include semantic Readline keys, text insertion, and replacement changes."
  (loop :for event-index :below (length events)
        :for event := (elt events event-index) :do
    (setf (edit-state-cursor state)
          (max 0 (min (length text) (edit-state-cursor state)))
          (edit-state-anchor state)
          (max 0 (min (length text) (edit-state-anchor state))))
    (let* ((cursor (edit-state-cursor state))
           (start (min cursor (edit-state-anchor state)))
           (end (max cursor (edit-state-anchor state))))
      (labels ((replace-selection (replacement)
                 (setf text
                       (concatenate 'string (subseq text 0 start) replacement
                                    (subseq text end))
                       (edit-state-cursor state)
                       (+ start (length replacement))
                       (edit-state-anchor state) (edit-state-cursor state)))
               (move-cursor (position &optional extend)
                 (setf (edit-state-cursor state)
                       (max 0 (min (length text) position)))
                 (unless extend
                   (setf (edit-state-anchor state)
                         (edit-state-cursor state))))
               (kill-selection (backward)
                 (when (< start end)
                   (let ((killed (subseq text start end)))
                     (setf (edit-state-kill state)
                           (if (member (edit-state-last-command state)
                                       '(:kill-end :kill-start :kill-word
                                         :kill-word-forward))
                               (if backward
                                   (concatenate 'string killed
                                                (edit-state-kill state))
                                   (concatenate
                                    'string (edit-state-kill state) killed))
                               killed)))
                   (replace-selection "")))
               (move-line (direction)
                 (let* ((left (line-start text cursor))
                        (column (- cursor left))
                        (next (if (minusp direction)
                                  (1- left) (1+ (line-end text cursor)))))
                   (when (<= 0 next (length text))
                     (let ((begin (line-start text next)))
                       (move-cursor (min (line-end text next)
                                         (+ begin column))))))))
        (case (event-kind event)
          (:change
           (when (stringp (event-value event))
             (setf text (event-value event))
             (move-cursor (length text))))
          (:text (replace-selection (event-value event)))
          (:key
           (case (event-key event)
             (:left (move-cursor (if (< start end) start (1- cursor))))
             (:right (move-cursor (if (< start end) end (1+ cursor))))
             (:shift-left (move-cursor (1- cursor) t))
             (:shift-right (move-cursor (1+ cursor) t))
             (:home (move-cursor (line-start text cursor)))
             (:end (move-cursor (line-end text cursor)))
             (:shift-home (move-cursor (line-start text cursor) t))
             (:shift-end (move-cursor (line-end text cursor) t))
             (:up (move-line -1))
             (:down (move-line 1))
             ((:word-left :shift-word-left)
              (move-cursor (word-position text cursor -1)
                           (eq (event-key event) :shift-word-left)))
             ((:word-right :shift-word-right)
              (move-cursor (word-position text cursor 1)
                           (eq (event-key event) :shift-word-right)))
             (:select-all
              (setf (edit-state-anchor state) 0
                    (edit-state-cursor state) (length text)))
             (:backspace
              (when (= start end) (setf start (max 0 (1- cursor))))
              (replace-selection ""))
             (:delete
              (when (= start end) (setf end (min (length text) (1+ cursor))))
              (replace-selection ""))
             (:kill-end
              (when (= start end)
                (setf end (line-end text cursor))
                (when (< end (length text))
                  (when (= cursor end) (incf end))))
              (kill-selection nil))
             (:kill-start
              (when (= start end) (setf start (line-start text cursor)))
              (kill-selection t))
             (:kill-word
              (when (= start end)
                (setf start (word-position text cursor -1 t)))
              (kill-selection t))
             (:kill-word-forward
              (when (= start end) (setf end (word-position text cursor 1)))
              (kill-selection nil))
             (:yank (replace-selection (edit-state-kill state)))
             (:transpose
              (when (and (plusp cursor) (> (length text) 1))
                (let ((right (min cursor (1- (length text)))))
                  (setf text (copy-seq text))
                  (rotatef (char text (1- right)) (char text right))
                  (move-cursor (1+ right)))))
             (otherwise nil)))
          (otherwise nil))
        (setf (edit-state-last-command state)
              (and (eq (event-kind event) :key) (event-key event))))))
  text)

(fn (value-widget (values t boolean))
    ((kind symbol) (style symbol) id value (text string) (options list))
  "Declare a value control, apply its current input, and return the updated value.
KIND is :CHECKBOX, :RADIO, :SLIDER, or :TEXT-FIELD; OPTIONS is a widget keyword plist."
  (let ((original value)
        (events (if (getf options :disabled-p) #() (events-for id))))
    (ecase kind
      (:checkbox
       (when (and (not (getf options :disabled-p)) (activated-p id))
         (setf value (not value)))
       (loop :for event :across events :do
         (when (eq (event-kind event) :change)
           (setf value (not (null (event-value event)))))))
      (:radio
       (when (and (not (getf options :disabled-p)) (activated-p id))
         (setf value (getf options :choice)))
       (loop :for event :across events :do
         (when (eq (event-kind event) :change)
           (setf value (event-value event)))))
      (:slider
       (let ((minimum (getf options :minimum 0))
             (maximum (getf options :maximum 1))
             (step (getf options :step 0.01f0))
             (box (previous-box id)))
         (assert (and (< minimum maximum) (> step 0)))
         (loop :for event :across events :do
           (case (event-kind event)
             (:change
              (when (realp (event-value event))
                (setf value (event-value event))))
             ((:press :move)
              (when (and box (plusp (box-width box))
                         (eq (event-button event) :primary)
                         (or (eq (event-kind event) :press)
                             (event-dragging-p event)))
                (setf value
                      (+ minimum
                         (* (- maximum minimum)
                            (/ (- (event-x event) (box-x box))
                               (box-width box)))))))
             (:key
              (case (event-key event)
                ((:right :up) (incf value step))
                ((:left :down) (decf value step))
                (:home (setf value minimum))
                (:end (setf value maximum))
                (otherwise nil)))
             (otherwise nil)))
         (setf value
               (max minimum
                    (min maximum
                         (+ minimum
                            (* step (round (/ (- value minimum) step)))))))))
      (:text-field
       (let ((state
              (or (gethash id (context-state *context*))
                  (setf (gethash id (context-state *context*))
                        (make-edit-state :cursor (length value)
                                         :anchor (length value))))))
         (setf value (edit-text value state events)))))
    (apply #'declare-widget kind style id text
           :value (if (eq kind :radio)
                      (equal value (getf options :choice)) value)
           (if (eq kind :radio)
               (loop :for (key option) :on options :by #'cddr
                     :unless (eq key :choice) :append (list key option))
               options))
    (values value (not (equal original value)))))


(defstruct scrollbar-state
  node
  grab)

(fn (scrollbar-thumb box) ((node element))
  "Return the scrollbar thumb's solved screen bounds from its true extent."
  (let* ((track (element-box node))
         (value (widget-value (element-content node)))
         (offset (first value)) (viewport (second value))
         (extent (third value))
         (height (min (box-height track)
                      (max (* 2 (box-width track))
                           (* (box-height track) (/ viewport extent))))))
    (make-box :x (box-x track) :width (box-width track) :height height
              :y (+ (box-y track)
                    (* (- (box-height track) height)
                       (/ offset (max 1 (- extent viewport))))))))

(fn (scrollbar-input t) (id owner)
  (let* ((events (events-for id))
         (state (when (plusp (length events)) (gethash id (context-state *context*))))
         (old (when state (scrollbar-state-node state))))
    (when old
      (let* ((value (widget-value (element-content old)))
             (offset (nth-value 1 (scroll-position owner)))
             (handled nil) (page (second value))
             (limit (- (third value) page))
             (track (element-box old)) (thumb (scrollbar-thumb old))
             (travel (- (box-height track) (box-height thumb))))
        (loop :for event :across events :do
          (case (event-kind event)
            (:press
             (when (eq (event-button event) :primary)
               (setf handled t (scrollbar-state-grab state) nil)
               (if (<= (box-y thumb) (event-y event)
                       (+ (box-y thumb) (box-height thumb)))
                   (setf (scrollbar-state-grab state)
                         (- (event-y event) (box-y thumb)))
                   (incf offset (if (< (event-y event) (box-y thumb))
                                    (- page) page)))))
            (:move
             (when (and (scrollbar-state-grab state) (plusp travel)
                        (event-dragging-p event))
               (setf handled t offset
                     (* limit (/ (- (event-y event) (box-y track)
                                     (scrollbar-state-grab state)) travel)))))
            ((:release :cancel) (setf (scrollbar-state-grab state) nil))
            (:key
             (when (member (event-key event)
                           '(:up :left :down :right :page-up :page-down
                             :home :end))
               (setf handled t))
             (case (event-key event)
               ((:up :left) (decf offset (max 1 (/ page 10))))
               ((:down :right) (incf offset (max 1 (/ page 10))))
               (:page-up (decf offset page))
               (:page-down (incf offset page))
               (:home (setf offset 0))
               (:end (setf offset limit)) (otherwise nil))) (otherwise nil))
          (setf offset (max 0 (min limit offset))))
        (when handled (scroll-to owner (scroll-position owner) offset))))))

(fn (decorate-scrollbar (or null element)) ((owner element) id)
  (when (plusp (element-scroll-limit-y owner))
    (let* ((bounds (element-box owner)) (padding (element-padding owner))
           (width (scroll-gutter owner))
           (height (max 0 (- (box-height bounds) (* 2 padding))))
           (widget (element-content owner))
           (box (make-box :x (- (+ (box-x bounds) (box-width bounds))
                                padding width)
                          :y (+ (box-y bounds) padding)
                          :width width :height height))
           (node (make-element
                  :id id :box box :clip (intersect-boxes box
                                                       (element-clip owner))
                  :floating-p t :interactive-p t :pointer-focus-p t
                  :content
                  (make-widget
                   :kind :scrollbar :style (widget-style widget)
                   :palette (widget-palette widget)
                   :text "Scroll" :opacity 1 :radius 0 :frost 0
                   :background (widget-background widget)
                   :foreground (widget-foreground widget)
                   :accent (widget-accent widget)
                   :value (list (element-scroll-y owner) height
                                (+ height (element-scroll-limit-y owner))))))
           (*parent* owner)
           (state (or (gethash id (context-state *context*))
                      (setf (gethash id (context-state *context*))
                            (make-scrollbar-state)))))
      (setf (scrollbar-state-node state) node)
      (emit node))))

(fn (declare-panel element) ((style symbol) (options list))
  "Declare a styled layout container without introducing retained widgets."
  (let ((appearance nil) (layout nil))
    (do ((tail options (cddr tail))) ((null tail))
      (let ((key (car tail)) (value (cadr tail)))
        (case key
          ((:palette :foreground :background :radius :frost :opacity :accent
            :font-size :font-family :font-weight :painter :terminal-label :terminal-border
            :accessible-name)
           (push key appearance)
           (push value appearance))
          (otherwise
           (push key layout)
           (push value layout)))))
    (setf appearance (nreverse appearance) layout (nreverse layout))
    (let* ((node (apply #'make-element
                        :content (apply #'make-widget :kind :panel
                                        :style style appearance)
                        layout))
           (enabled (and (element-scroll-p node)
                         (getf options :scrollbar-p t)))
           (width (getf options :scrollbar-width
                        (if (context-text-mode-p *context*) 1 12))))
      (when (and enabled (plusp width))
        (setf (element-scrollbar-p node) t
              (element-scrollbar-width node) width)
        (let ((id (list :lui.scrollbar (element-id node))))
          (scrollbar-input id (element-id node))
          (push (lambda () (decorate-scrollbar node id))
                (lui.frame::context-after-layout *context*))))
      (emit node))))
