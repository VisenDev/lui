(defpackage #:lui.debug
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.widgets)
  (:export #:set-enabled #:enabled-p #:state #:make-state
           #:state-open-p
           #:state-selected #:state-width))
(in-package #:lui.debug)

(defstruct entry node key (depth 0 :type integer))
(defstruct state
  "Debugger state: visibility, selected snapshot node, expansion, and pane width."
  (open-p nil :type boolean) selected
  (details-height nil :type (or null real))
  (details-grab nil :type (or null cons))
  (reveal-selection-p nil :type boolean)
  (width nil :type (or null real)) (grab nil :type (or null real))
  (collapsed (make-hash-table :test 'equal) :type hash-table)
  (nodes (make-hash-table :test 'equal) :type hash-table)
  (rows (make-array 0 :adjustable t :fill-pointer 0) :type vector))
(fn (id list) (name &optional key) (list :lui.debug name key))

(fn (own-node-p boolean) ((node element))
  (let ((id (element-id node)))
    (and (consp id) (eq (first id) :lui.debug))))

(fn (snapshot null) ((state state) (root element))
  ;; IDs survive redraws. Anonymous nodes use positions below the closest ID;
  ;; identical anonymous siblings cannot be distinguished after a reorder.
  ;; Duplicate IDs remain core errors rather than recoverable debugger warnings.
  (setf (fill-pointer (state-rows state)) 0)
  (clrhash (state-nodes state))
  (labels ((visit (node anchor path depth shown)
             (unless (own-node-p node)
               (let* ((explicit (element-id node))
                      (anchor (or explicit anchor))
                      (path (if explicit nil path))
                      (key (if explicit (list :id explicit)
                               (list :path anchor (reverse path)))))
                 (setf (gethash key (state-nodes state)) node)
                 (when shown
                   (vector-push-extend
                    (make-entry :node node :key key :depth depth)
                    (state-rows state)))
                 (loop :for child :across (element-children node)
                       :for index :from 0
                       :do (visit child anchor (cons index path) (1+ depth)
                                  (and shown
                                       (not (gethash key
                                                     (state-collapsed
                                                      state))))))))))
    (visit root nil nil 0 t))
  (unless (gethash (state-selected state) (state-nodes state))
    (setf (state-selected state) nil)))

(fn (box-label string) ((box box))
  (format nil "(~,2F, ~,2F) ~,2F x ~,2F"
          (box-x box) (box-y box) (box-width box) (box-height box)))

(fn (clipped-p boolean) ((node element))
  (let ((box (element-box node)) (clip (element-clip node)))
    (not (and (= (box-x box) (box-x clip)) (= (box-y box) (box-y clip))
              (= (box-width box) (box-width clip))
              (= (box-height box) (box-height clip))))))

(fn (offscreen-p boolean) ((node element))
  (or (zerop (box-width (element-clip node)))
      (zerop (box-height (element-clip node)))))

(fn (preview string) ((text string))
  (let ((text (subseq text 0 (min 40 (length text)))))
    (map 'string (lambda (char)
                   (if (< (char-code char) 32) #\Space char)) text)))

(fn (caption string) ((node element))
  (let* ((widget (element-content node))
         (kind (if (widget-p widget) (widget-kind widget)
                   (element-direction node)))
         (name (or (element-id node)
                   (when (widget-p widget) (preview (widget-text widget))) ""))
         (status (cond ((offscreen-p node) " [offscreen]")
                       ((clipped-p node) " [clipped]") (t "")))
         (*print-level* 2) (*print-length* 4))
    (lui.frame::memoized
     (list :caption kind name status *package* #-jscl *print-case* *print-base*
           *print-radix* #-jscl *print-pretty* *print-circle* *readtable*)
     (lambda () (format nil "~A ~A~A" kind name status)))))

(fn (sizing-label string) ((rule sizing))
  (format nil "~A ~A [~A, ~A]" (lui.layout::sizing-kind rule)
          (lui.layout::sizing-value rule) (lui.layout::sizing-minimum rule)
          (or (lui.layout::sizing-maximum rule) "none")))

(fn (property-text string) (value)
  (cond
    ((stringp value)
     (if (> (length value) 160)
         (concatenate 'string (subseq value 0 160) "...") value))
    ((or (null value) (numberp value) (symbolp value) (characterp value))
     (format nil "~S" value))
    ((consp value)
     ;; Bound traversal before printing: JSCL ignores printer length limits.
     (let ((items nil) (tail value))
       (dotimes (i 5)
         (when (consp tail) (push (car tail) items) (setf tail (cdr tail))))
       (if (and (null tail) (< (length items) 5) (every #'atom items))
           (format nil "~S" (nreverse
                             (mapcar (lambda (item)
                                       (if (stringp item)
                                           (subseq item 0
                                                   (min 32 (length item)))
                                           (if (or (null item) (numberp item)
                                                   (symbolp item)
                                                   (characterp item)) item
                                               :object))) items)))
           (format nil "List (~D~A items)" (length items)
                   (if tail "+" "")))))
    ((vectorp value) (format nil "Vector (~D items)" (length value)))
    (t (let ((type (type-of value)))
         (format nil "#<~A>" (if (symbolp type) (symbol-name type) "Object"))))))

(fn (flag-label string) ((pairs list) (empty string))
  (let ((names (loop :for (name . enabled) :in pairs
                    :when enabled :collect name)))
    (if names (format nil "~{~A~^, ~}" names) empty)))

(fn (properties null) ((title string) (width real) &rest pairs)
  (let ((accent (getf (toolkit-defaults) :accent "#258bff")))
    (row (:width (grow) :gap (units 0.5))
      (lui:label "—" (lui:opt :width (fixed (units 2)) :font-size 14
                             :foreground accent))
      (lui:label title (lui:opt :width (grow) :font-size 14 :font-weight :bold
                               :foreground accent))))
  (dolist (pair pairs)
    (when pair
      (let ((stacked (< width (units 32))))
        (flet ((emit-pair ()
                 (lui:label (concatenate 'string (first pair) ":")
                            (lui:opt :width (if stacked (grow)
                                               (fixed (units 13)))
                                     :font-size 14 :font-weight :bold))
                 (lui:label (property-text (second pair))
                            (lui:opt :width (grow) :font-size 14
                                     :font-weight :normal))))
          (if stacked
              (column (:width (grow)) (emit-pair))
              (row (:width (grow) :gap (units 1)) (emit-pair))))))))

(fn (details null) ((node element) (width real))
  (let* ((widget (element-content node)) (node-id (element-id node))
         (container (plusp (length (element-children node))))
         (focused (and node-id (equal node-id (context-focus *context*)))))
    (lui:label (caption node)
               (lui:opt :width (grow) :font-size 14 :font-weight :bold))
    (properties "Geometry" width
                (list "Bounds" (box-label (element-box node)))
                (list "Clip" (box-label (element-clip node))))
    (properties "Layout" width
                (list "Width" (sizing-label (element-width node)))
                (list "Height" (sizing-label (element-height node)))
                (when (or container (plusp (element-padding node))
                          (plusp (element-gap node)))
                  (list "Flow" (format nil "~A; padding ~A; gap ~A"
                                     (element-direction node)
                                     (element-padding node)
                                     (element-gap node))))
                (when container
                  (list "Alignment" (format nil "main ~A; cross ~A"
                                          (element-align node)
                                          (element-cross-align node))))
                (when (or (element-floating-p node)
                          (not (zerop (element-offset-x node)))
                          (not (zerop (element-offset-y node))))
                  (list "Position" (format nil "floating ~A; offset ~A / ~A"
                                         (element-floating-p node)
                                         (element-offset-x node)
                                         (element-offset-y node))))
                (when (or (element-clip-p node) (element-scroll-p node)
                          (element-scrollbar-p node))
                  (list "Clipping" (format nil "children ~A; scrollbar ~A (~A)"
                                         (element-clip-p node)
                                         (element-scrollbar-p node)
                                         (element-scrollbar-width node))))
                (when (or (element-scroll-p node)
                          (not (zerop (element-scroll-x node)))
                          (not (zerop (element-scroll-y node))))
                  (list "Scroll" (format nil "enabled ~A; ~,2F / ~,2F; max Y ~,2F"
                                       (element-scroll-p node)
                                       (element-scroll-x node)
                                       (element-scroll-y node)
                                       (element-scroll-limit-y node)))))
    (when (widget-p widget)
      (properties "Appearance" width
                  (list "Toolkit" (widget-style widget))
                  (list "Foreground" (widget-foreground widget))
                  (list "Background" (widget-background widget))
                  (list "Accent" (widget-accent widget))
                  (list "Surface" (format nil "opacity ~A; radius ~A; frost ~A"
                                          (widget-opacity widget)
                                          (widget-radius widget)
                                          (widget-frost widget)))
                  (list "Font" (format nil "~A ~A ~A"
                                       (widget-font-family widget)
                                       (widget-font-weight widget)
                                       (widget-font-size widget)))))
    (properties "Content" width
                (list "ID" node-id)
                (list "Kind" (format nil "~A; ~D children"
                                     (if (widget-p widget)
                                         (widget-kind widget)
                                         (element-direction node))
                                     (length (element-children node))))
                (list "Text" (if (widget-p widget) (widget-text widget) ""))
                (list "Value" (when (widget-p widget) (widget-value widget))))
    (properties
     "Input" width
     (list "Flags"
           (flag-label
            (list (cons "Interactive" (element-interactive-p node))
                  (cons "Tab stop" (and (element-interactive-p node)
                                         (element-keyboard-focus-p node)))
                  (cons "Pointer focus" (element-pointer-focus-p node))
                  (cons "Disabled" (and (widget-p widget)
                                         (widget-disabled-p widget))))
            "None"))
     (list "State"
           (flag-label
            (list (cons "Focused" focused)
                  (cons "Focus ring"
                        (and focused (context-focus-visible-p *context*)))
                  (cons "Hovered" (hovered-p node-id))
                  (cons "Pressed" (and node-id
                                       (equal node-id
                                              (context-active *context*)))))
            "Idle")))))

(fn (highlight (or null element)) ((box box) (name symbol) (opacity real) (accent string))
  (when (and (plusp (box-width box)) (plusp (box-height box)))
    (emit (make-element
           :id (id name) :floating-p t :offset-x (box-x box)
           :offset-y (box-y box) :width (fixed (box-width box))
           :height (fixed (box-height box))
           :content (make-widget :kind :highlight :style (lui:current-toolkit)
                                 :background "#ffb347"
                                 :accent accent :opacity opacity)))))

(fn (close-details real) ((state state))
  (setf (state-selected state) nil (state-details-height state) nil
        (state-details-grab state) nil (state-reveal-selection-p state) nil)
  (request-frame))

(fn (reveal-selection real)
    ((state state) (rows vector) (step (real 0 *)) (height real) (offset real))
  (when (state-reveal-selection-p state)
    (setf (state-reveal-selection-p state) nil)
    (let ((index (position (state-selected state) rows :key #'entry-key
                           :test #'equal)))
      (when index
        (let* ((top (* index step))
               (viewport (max step (- height (units 2)))))
          (setf offset
                (max 0 (min top (max offset (- (+ top step) viewport)))))
          (scroll-to (id :tree) 0 offset)))))
  offset)

(fn (tree null) ((state state) (width real))
  (lui:panel (lui:opt :id (id :tree) :width (grow) :height (grow)
                      :scroll-p t :padding (units 1) :opacity 1
                      :radius 0 :frost 0)
    (let* ((rows (state-rows state))
           (step (units (if (context-text-mode-p *context*) 1 3)))
           (viewport (previous-box (id :tree)))
           (height (if viewport (box-height viewport)
                       (/ (lui.frame::context-viewport-height *context*) 2)))
           (offset (reveal-selection
                    state rows step height
                    (nth-value 1 (scroll-position (id :tree)))))
           (limit (max 0 (- (* step (length rows)) height)))
           (first (max 0 (floor (min offset limit) step)))
           (end (min (length rows) (+ first (ceiling height step) 1))))
      (column (:width (grow) :height (fixed (* step (length rows))))
        (loop :for index :from first :below end
              :for entry := (aref rows index)
              :for node := (entry-node entry)
              :for key := (entry-key entry)
              :do (row (:floating-p t :offset-y (* index step)
                                    :width (grow) :height (fixed step)
                                    :gap (units 0.25) :cross-align :center)
                    (emit (make-element
                           :width
                           (fixed (min (/ width 3)
                                       (units (* 2 (entry-depth entry)))))))
                    (if (plusp (length (element-children node)))
                        (when (lui:list-item
                               (id :collapse key)
                               (if (gethash key (state-collapsed state))
                                   "+" "-")

                               (lui:opt :width (fixed (units 3))
                                        :height (fixed step)))
                          (setf (gethash key (state-collapsed state))
                                (not (gethash key (state-collapsed state))))
                          (request-frame))
                        (emit (make-element :width (fixed (units 3)))))
                    (when (lui:list-item
                           (id :row key) (caption node)

                           (lui:opt :width (grow) :height (fixed step)
                                    :selected-p
                                    (equal key (state-selected state))))
                      (if (equal key (state-selected state))
                          (close-details state)
                          (setf (state-selected state) key
                                (state-reveal-selection-p state) t))
                      (request-frame))))))))

(fn (debugger-width real) ((state state))
  (let* ((window (context-width *context*))
         (minimum (min window (units 25)))
         (maximum (max minimum (- window (units 12))))
         (width (min maximum (max minimum
                                  (if (state-width state)
                                      (units (state-width state))
                                      (* window 0.4))))))
    (loop for event across (events-for (id :resize)) do
      (when (or (eq (event-kind event) :cancel)
                (and (eq (event-kind event) :move)
                     (not (event-dragging-p event))))
        (setf (state-grab state) nil))
      (when (or (and (eq (event-kind event) :press)
                     (eq (event-button event) :primary))
                (and (state-grab state)
                     (member (event-kind event) '(:move :release)))
                (and (eq (event-kind event) :key)
                     (member (event-key event) '(:left :right :home :end))))
        (case (event-kind event)
          (:press
           (setf (state-grab state) (- (event-x event) (- window width))
                 (context-focus *context*) (id :resize)))
          ((:move :release)
           (setf width (+ (- window (event-x event)) (state-grab state)))
           (when (eq (event-kind event) :release)
             (setf (state-grab state) nil)))
          (:key
           (case (event-key event)
             (:left (incf width (units 2)))
             (:right (decf width (units 2)))
             (:home (setf width minimum)) (:end (setf width maximum)))))
        (setf width (min maximum (max minimum width))
              (state-width state) (/ width *unit*))
        (request-frame)))
    (unless (equal (context-active *context*) (id :resize))
      (setf (state-grab state) nil))
    width))

(fn (resize-handle element) ((width real))
  (let ((size (units 1)))
    (emit (make-element
           :id (id :resize) :interactive-p t :pointer-focus-p t
           :floating-p t
           :offset-y (lui.frame::context-page-top *context*)
           :offset-x (max 0 (- (context-width *context*) width (/ size 2)))
           :width (fixed size) :height (fixed (lui.frame::context-viewport-height *context*))
           :content (apply #'make-widget :kind :splitter
                           :style (lui:current-toolkit)
                           :value (/ width
                                     (max 1 (context-width *context*)))
                           :text "Debugger width"
                           (lui:toolkit-defaults))))))

(fn (details-height real) ((state state) (maximum (real 0 *)))
  (let* ((minimum (min maximum (units (if (context-text-mode-p *context*)
                                         6 12))))
         (height (min maximum
                      (max minimum (if (state-details-height state)
                                       (units (state-details-height state))
                                       (* maximum 0.75))))))
    (loop for event across (events-for (id :details-resize)) do
      (when (or (eq (event-kind event) :cancel)
                (and (eq (event-kind event) :move)
                     (not (event-dragging-p event))))
        (setf (state-details-grab state) nil))
      (when (or (and (eq (event-kind event) :press)
                     (eq (event-button event) :primary))
                (and (state-details-grab state)
                     (member (event-kind event) '(:move :release)))
                (and (eq (event-kind event) :key)
                     (member (event-key event) '(:up :down :home :end))))
        (case (event-kind event)
          (:press
           (setf (state-details-grab state) (cons (event-y event) height)
                 (context-focus *context*) (id :details-resize)))
          ((:move :release)
           (setf height (+ (cdr (state-details-grab state))
                           (- (car (state-details-grab state))
                              (event-y event))))
           (when (eq (event-kind event) :release)
             (setf (state-details-grab state) nil)))
          (:key
           (case (event-key event)
             (:up (incf height (units 2))) (:down (decf height (units 2)))
             (:home (setf height maximum)) (:end (setf height 0)))))
        (if (<= height (units 2))
            (close-details state)
            (setf height (min maximum (max minimum height))
                  (state-details-height state) (/ height *unit*)))
        (request-frame)))
    (unless (equal (context-active *context*) (id :details-resize))
      (setf (state-details-grab state) nil))
    height))

(fn (details-divider element) ((height real))
  (emit (make-element
         :id (id :details-resize) :interactive-p t :pointer-focus-p t
         :width (grow) :height (fixed (units 1))
         :content (apply #'make-widget :kind :splitter
                         :style (current-toolkit) :orientation :horizontal
                         :text "Properties height"
                         :value (/ height (max 1 (lui.frame::context-viewport-height *context*)))
                         (toolkit-defaults)))))

(fn (debugger-header-height real) ((header element) (width real))
  (let* ((children (element-children header))
         (title (aref children 0)) (close (aref children 1))
         (title-padding (* 2 (element-padding title)))
         (close-padding (* 2 (element-padding close))))
    (multiple-value-bind (close-width close-height)
        (funcall (element-measure close) nil)
      (max (+ close-height close-padding)
           (+ title-padding
              (nth-value 1
                (funcall (element-measure title)
                         (max 0 (- width close-width close-padding
                                   (element-gap header)
                                   title-padding)))))))))

(fn (debugger (or null element)) ((state state) (width real))
  (when (activated-p (id :close-details)) (close-details state))
  (lui:panel (lui:opt :id (id :debugger) :interactive-p t
                      :keyboard-focus-p nil :floating-p t
                      :offset-y (lui.frame::context-page-top *context*)
                      :offset-x (- (context-width *context*) width)
                      :width (fixed width)
                      :height (fixed (lui.frame::context-viewport-height *context*))
                      :padding (units 1) :gap (units 0.5) :opacity 1
                      :radius 0 :frost 0)
    (let ((header nil))
      (row (:id (id :header) :width (grow) :gap (units 0.5))
        (setf header *parent*)
        (lui:label "Layout debugger" (lui:opt :width (grow)))
        (when (lui:button (id :close) "Close")
          (setf (state-open-p state) nil)
          (request-frame)))
      (let* ((header-height
               (debugger-header-height header (- width (units 2))))
             ;; Root/tree padding, three gaps and the divider also need room.
             (maximum (max 0 (- (lui.frame::context-viewport-height *context*) header-height
                                (units 6.5))))
             (height (details-height state maximum)))
        (setf (element-height header) (fit header-height))
        (tree state width)
        (let ((node (gethash (state-selected state) (state-nodes state))))
          (if node
              (progn
                (details-divider height)
                (column (:id (id :property-pane) :width (grow)
                         :height (fixed height) :gap (units 0.5))
                  (row (:width (grow) :gap (units 0.5) :cross-align :center)
                    (lui:label "Properties" (lui:opt :width (grow)))
                    (lui:button (id :close-details) "×"
                                 (lui:opt :width (fixed (units 5))
                                          :font-size 14
                                          :accessible-name "Close details")))
                  (lui:panel (lui:opt :id (id :details)
                                      :width (grow) :height (grow)
                                      :scroll-p t :padding (units 1)
                                      :gap (if (context-text-mode-p *context*)
                                               0 (units 0.25))
                                      :opacity 1 :radius 0 :frost 0)
                    (details node width))))
              (lui:label "Select a tree row for properties."
                         (lui:opt :width (grow) :font-size 14))))))))

(fn (draw-debugger (or null element)) ((state state) (toolkit symbol) previous)
  (when (and (state-open-p state) (null previous)) (request-frame))
  (when (and (state-open-p state) previous)
    (snapshot state previous)
    (lui:with-toolkit (toolkit)
      (let* ((hover (context-hover *context*))
             (key (when (and (consp hover) (eq (first hover) :lui.debug)
                             (member (second hover) '(:row :collapse)))
                    (third hover)))
             (node (gethash key (state-nodes state))))
        (when node
          (highlight (element-box node) :bounds 0.18 "#ff8c00")
          (when (clipped-p node)
            (highlight (element-clip node) :clip 0 "#00c0ff")))
        (let ((width (debugger-width state)))
          (debugger state width)
          (resize-handle width))))))

(fn (enabled-p boolean) (&optional (context *context*))
  "Whether CONTEXT currently has an open debugger attached to its overlay."
  (let ((state (context-overlay-state context)))
    (and state (state-open-p state))))

(fn (set-enabled boolean) ((enabled boolean) &key ((context context) *context*) state toolkit)
  "Enable the context's debugger. Call on a toggle, not on every draw."
  (let ((state (or state (context-overlay-state context) (make-state))))
    (setf (state-open-p state) enabled
          (context-overlay-state context) state
          (context-overlay context)
          (when enabled
            (lambda (previous)
              (let* ((children (element-children (context-root context)))
                     (first (when (plusp (length children))
                              (element-content (aref children 0))))
                     (style (or toolkit (and (widget-p first)
                                             (widget-style first))
                                (current-toolkit))))
                (draw-debugger state style previous)
                (unless (state-open-p state)
                  (setf (context-overlay context) nil))))))
    (let ((*context* context)) (request-frame))
    enabled))
