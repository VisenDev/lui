(defpackage #:lui.debug
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.widgets)
  (:export #:set-enabled #:enabled-p #:wrap #:draw #:state #:make-state
           #:*state* #:state-open-p
           #:state-selected #:state-width))
(in-package #:lui.debug)

(defstruct* entry node key (depth 0 :type integer))
(defstruct* state
  "Inspector state: visibility, selected snapshot node, expansion, and pane width."
  (open-p nil :type boolean) selected
  (details-expanded-p nil :type boolean)
  (reveal-selection-p nil :type boolean)
  (width nil :type (or null real)) (grab nil :type (or null real))
  (collapsed (make-hash-table :test 'equal) :type hash-table)
  (nodes (make-hash-table :test 'equal) :type hash-table)
  (rows (make-array 0 :adjustable t :fill-pointer 0) :type vector))
(defvar *state* (make-state)
  "Default state for the legacy DRAW/WRAP helpers; SET-ENABLED owns context state.")

(fn id (name &optional key) (list :lui.debug name key))

(fn own-node-p ((node element))
  (let ((id (element-id node)))
    (and (consp id) (eq (first id) :lui.debug))))

(fn snapshot ((state state) (root element))
  ;; IDs survive redraws. Anonymous nodes use positions below the closest ID;
  ;; identical anonymous siblings cannot be distinguished after a reorder.
  ;; Duplicate IDs remain core errors rather than recoverable inspector warnings.
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

(fn box-label ((box box))
  (format nil "(~,2F, ~,2F) ~,2F x ~,2F"
          (box-x box) (box-y box) (box-width box) (box-height box)))

(fn clipped-p ((node element))
  (let ((box (element-box node)) (clip (element-clip node)))
    (not (and (= (box-x box) (box-x clip)) (= (box-y box) (box-y clip))
              (= (box-width box) (box-width clip))
              (= (box-height box) (box-height clip))))))

(fn offscreen-p ((node element))
  (or (zerop (box-width (element-clip node)))
      (zerop (box-height (element-clip node)))))

(fn preview ((text string))
  (let ((text (subseq text 0 (min 40 (length text)))))
    (map 'string (lambda (char)
                   (if (< (char-code char) 32) #\Space char)) text)))

(fn caption ((node element))
  (let ((widget (element-content node))
        (*print-level* 2) (*print-length* 4))
    (format nil "~A ~A~A"
            (if (widget-p widget) (widget-kind widget)
                (element-direction node))
            (or (element-id node)
                (when (widget-p widget) (preview (widget-text widget))) "")
            (cond ((offscreen-p node) " [offscreen]")
                  ((clipped-p node) " [clipped]") (t "")))))

(fn sizing-label ((rule sizing))
  (format nil "~A ~A [~A, ~A]" (lui.layout::sizing-kind rule)
          (lui.layout::sizing-value rule) (lui.layout::sizing-minimum rule)
          (or (lui.layout::sizing-maximum rule) "none")))

(defun property-text (value)
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

(defun flag-label (pairs empty)
  (let ((names (loop :for (name . enabled) :in pairs
                    :when enabled :collect name)))
    (if names (format nil "~{~A~^, ~}" names) empty)))

(defun properties (title width &rest pairs)
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

(fn details ((node element) (width real))
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
                  (list "Collection" (widget-style widget))
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

(fn highlight ((box box) (name symbol) (opacity real) (accent string))
  (when (and (plusp (box-width box)) (plusp (box-height box)))
    (emit (make-element
           :id (id name) :floating-p t :offset-x (box-x box)
           :offset-y (box-y box) :width (fixed (box-width box))
           :height (fixed (box-height box))
           :content (make-widget :kind :highlight :style (lui:current-toolkit)
                                 :background "#ffb347"
                                 :accent accent :opacity opacity)))))

(defun close-details (state)
  (setf (state-selected state) nil (state-details-expanded-p state) nil
        (state-reveal-selection-p state) nil)
  (request-frame))

(defun reveal-selection (state rows step height offset)
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

(fn tree ((state state) (width real))
  (lui:panel (lui:opt :id (id :tree) :width (grow) :height (grow)
                      :scroll-p t :padding (units 1) :opacity 1
                      :radius 0 :frost 0)
    (let* ((rows (state-rows state))
           (step (units (if (context-text-mode-p *context*) 1 3)))
           (viewport (previous-box (id :tree)))
           (height (if viewport (box-height viewport)
                       (/ (context-height *context*) 2)))
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

(fn inspector-width ((state state))
  (let* ((window (context-width *context*))
         (minimum (min window (units 25)))
         (maximum (max minimum (- window (units 12))))
         (width (min maximum (max minimum
                                  (if (state-width state)
                                      (units (state-width state))
                                      (* window 0.4))))))
    (dolist (event (events-for (id :resize)))
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
    width))

(fn resize-handle ((width real))
  (let ((size (units 1)))
    (emit (make-element
           :id (id :resize) :interactive-p t :pointer-focus-p t
           :floating-p t
           :offset-x (max 0 (- (context-width *context*) width (/ size 2)))
           :width (fixed size) :height (fixed (context-height *context*))
           :content (apply #'make-widget :kind :splitter
                           :style (lui:current-toolkit)
                           :value (/ width
                                     (max 1 (context-width *context*)))
                           :text "Inspector width"
                           (lui:toolkit-defaults))))))

(defun details-toggle (state full-width)
  (when (lui:button (id :expand-details)
                    (if (state-details-expanded-p state)
                        "Restore tree" "Expand details")
                    (lui:opt :width (if full-width (grow) (fit))
                             :disabled-p (null (state-selected state))))
    (setf (state-details-expanded-p state)
          (not (state-details-expanded-p state)))
    (request-frame)))

(fn inspector ((state state) (width real))
  (when (activated-p (id :close-details)) (close-details state))
  (unless (state-selected state) (setf (state-details-expanded-p state) nil))
  (lui:panel (lui:opt :id (id :inspector) :interactive-p t
                      :keyboard-focus-p nil :floating-p t
                      :offset-x (- (context-width *context*) width)
                      :width (fixed width)
                      :height (fixed (context-height *context*))
                      :padding (units 1) :gap (units 0.5) :opacity 1
                      :radius 0 :frost 0)
    (row (:width (grow) :gap (units 0.5))
      (lui:label "Layout inspector" (lui:opt :width (grow)))
      (when (lui:button (id :close) "Close")
        (setf (state-open-p state) nil)
        (request-frame))
      (when (>= width (units 48)) (details-toggle state nil)))
    (when (< width (units 48)) (details-toggle state t))
    (unless (state-details-expanded-p state) (tree state width))
    (let* ((node (gethash (state-selected state) (state-nodes state)))
           (overhead (units (cond ((context-text-mode-p *context*) 4)
                                  ((< width (units 48)) 11) (t 8))))
           (available (max 0 (- (context-height *context*) overhead))))
      (if node
          (column (:id (id :property-pane) :width (grow)
                   :height (if (state-details-expanded-p state) (grow)
                               (fixed (* available 0.75))))
            (row (:width (grow) :gap (units 0.5) :cross-align :center)
              (when (>= width (units 36))
                (lui:label "Properties" (lui:opt :width (grow))))
              (lui:button (id :close-details) "Close details"
                           (lui:opt :width (if (< width (units 36))
                                              (grow) (fit)))))
            (lui:panel (lui:opt :id (id :details) :width (grow) :height (grow)
                                :scroll-p t :padding (units 1)
                                :gap (if (context-text-mode-p *context*)
                                         0 (units 0.25))
                                :opacity 1 :radius 0 :frost 0)
              (details node width)))
          (lui:label "Select a tree row for properties."
                     (lui:opt :width (grow) :font-size 14))))))

(defun draw-inspector (state toolkit previous)
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
        (let ((width (inspector-width state)))
          (inspector state width)
          (resize-handle width))))))

(defun enabled-p (&optional (context *context*))
  "Whether CONTEXT currently has an open inspector attached to its overlay."
  (let ((state (context-overlay-state context)))
    (and state (state-open-p state))))

(defun set-enabled (enabled &key (context *context*) state toolkit)
  "Enable the context's inspector. Call on a toggle, not on every draw."
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
                (draw-inspector state style previous)
                (unless (state-open-p state)
                  (setf (context-overlay context) nil))))))
    (let ((*context* context)) (request-frame))
    enabled))

(fn draw ((function function) &key ((state state) *state*) (toolkit :glass))
  "Draw FUNCTION followed by an inspector using STATE and TOOLKIT.
Compatibility entry point; prefer SET-ENABLED for context-owned inspection."
  (funcall function)
  (draw-inspector state toolkit (context-previous-root *context*)))

(fn (wrap function) ((function function) &key ((state state) *state*)
                                           (toolkit :glass))
  "Return a drawing closure that calls FUNCTION and then draws STATE's inspector.
Compatibility helper; SET-ENABLED attaches an inspector without wrapping callbacks."
  (lambda () (draw function :state state :toolkit toolkit)))
