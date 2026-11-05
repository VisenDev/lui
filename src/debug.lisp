(defpackage #:lui.debug
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.widgets)
  (:export #:wrap #:draw #:state #:make-state #:*state* #:state-open-p
           #:state-selected))
(in-package #:lui.debug)

(defstruct* entry node key (depth 0 :type integer))
(defstruct* state
  (open-p nil :type boolean) selected
  (collapsed (make-hash-table :test 'equal) :type hash-table)
  (nodes (make-hash-table :test 'equal) :type hash-table)
  (rows (make-array 0 :adjustable t :fill-pointer 0) :type vector))
(defvar *state* (make-state))

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

(fn package-name-for ((toolkit symbol))
  (ecase toolkit (:glass "LUI.GLASS") (:motif "LUI.MOTIF")
         (:garnet "LUI.GARNET")))

(fn control ((toolkit symbol) (kind symbol) &rest arguments)
  (apply (symbol-function
          (find-symbol (symbol-name kind) (package-name-for toolkit)))
         arguments))

(fn pane ((toolkit symbol) &rest options)
  (declare-panel toolkit
    (append options
            (symbol-value (find-symbol "*DEFAULTS*"
                                        (package-name-for toolkit))))))

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

(fn details ((toolkit symbol) (node element))
  (control toolkit :label (caption node) :width (grow))
  (dolist (line (list (format nil "Bounds: ~A" (box-label (element-box node)))
                     (format nil "Clip: ~A" (box-label (element-clip node)))
                     (format nil "Width: ~A"
                             (sizing-label (element-width node)))
                     (format nil "Height: ~A"
                             (sizing-label (element-height node)))
                     (format nil "~A; padding ~A; gap ~A"
                             (element-direction node) (element-padding node)
                             (element-gap node))
                     (format nil "Align ~A / ~A" (element-align node)
                             (element-cross-align node))
                     (format nil "Scroll ~,2F / ~,2F; limit ~,2F"
                             (element-scroll-x node) (element-scroll-y node)
                             (element-scroll-limit-y node))))
    (control toolkit :label line))
  (let ((widget (element-content node)))
    (when (widget-p widget)
      (control toolkit :label
               (format nil "~A / ~A; ~A ~A ~A"
                       (widget-kind widget) (widget-style widget)
                       (widget-font-family widget) (widget-font-weight widget)
                       (widget-font-size widget)))
      (control toolkit :label
               (format nil "Disabled ~A; focus ~A" (widget-disabled-p widget)
                       (equal (element-id node) (context-focus *context*))))
      (control toolkit :label (preview (widget-text widget))))))

(fn highlight ((box box) (name symbol) (opacity real) (accent string))
  (when (and (plusp (box-width box)) (plusp (box-height box)))
    (emit (make-element
           :id (id name) :floating-p t :offset-x (box-x box)
           :offset-y (box-y box) :width (fixed (box-width box))
           :height (fixed (box-height box))
           :content (make-widget :kind :highlight :background "#ffb347"
                                 :accent accent :opacity opacity)))))

(fn tree ((state state) (toolkit symbol) (width real))
  (let* ((*parent* (pane toolkit :id (id :tree) :width (grow) :height (grow)
                        :scroll-p t :padding (units 1) :opacity 1
                        :radius 0 :frost 0))
         (rows (state-rows state)) (step (units 3))
         (viewport (previous-box (id :tree)))
         (height (if viewport (box-height viewport)
                     (/ (context-height *context*) 2)))
         (offset (nth-value 1 (scroll-position (id :tree))))
         (first (max 0 (floor (min offset
                                  (max 0 (- (* step (length rows)) height)))
                              step)))
         (end (min (length rows) (+ first (ceiling height step) 1))))
    (let ((*parent*
            (emit (make-element :width (grow)
                                :height (fixed (* step (length rows)))))))
      (loop :for index :from first :below end
            :for entry := (aref rows index)
            :for node := (entry-node entry)
            :for key := (entry-key entry)
            :do (row (:floating-p t :offset-y (* index step)
                      :width (grow) :height (fixed step)
                      :gap (units 0.25) :cross-align :center)
                  (emit (make-element
                         :width (fixed (min (/ width 3)
                                            (units (entry-depth entry))))))
                  (if (plusp (length (element-children node)))
                      (when (control toolkit :button (id :collapse key)
                                     (if (gethash key (state-collapsed state))
                                         "+" "-")
                                     :width (fixed (units 5)))
                        (setf (gethash key (state-collapsed state))
                              (not (gethash key (state-collapsed state))))
                        (request-frame))
                      (control toolkit :label "." :width (fixed (units 5))))
                  (when (control toolkit :list-item (id :row key)
                                 (caption node) :width (grow)
                                 :height (fixed step)
                                 :selected-p
                                 (equal key (state-selected state)))
                    (setf (state-selected state) key)
                    (request-frame)))))))

(fn inspector ((state state) (toolkit symbol))
  (let* ((width (min (context-width *context*)
                     (max (units 25) (* (context-width *context*) 0.4))))
         (*parent* (pane toolkit :id (id :inspector) :interactive-p t
                        :keyboard-focus-p nil
                        :floating-p t
                        :offset-x (- (context-width *context*) width)
                        :width (fixed width)
                        :height (fixed (context-height *context*))
                        :padding (units 1) :gap (units 0.5) :opacity 1
                        :radius 0 :frost 0)))
    (row (:width (grow) :gap (units 0.5))
      (control toolkit :label "Layout inspector" :width (grow))
      (when (control toolkit :button (id :close) "Close")
        (setf (state-open-p state) nil)
        (request-frame)))
    (tree state toolkit width)
    (let ((*parent* (pane toolkit :id (id :details) :width (grow)
                         :height (fixed (min (units 18)
                                             (* (context-height *context*)
                                                0.4)))
                         :scroll-p t :padding (units 1) :opacity 1
                         :radius 0 :frost 0)))
      (let ((node (gethash (state-selected state) (state-nodes state))))
        (if node (details toolkit node)
            (control toolkit :label
                     "Select a row for details. Offscreen/clipped are informational; duplicate IDs remain errors."))))))

(fn draw ((function function) &key ((state state) *state*) (toolkit :glass))
  ;; App tab navigation may consume CONTEXT-PREVIOUS-ROOT during declaration.
  (let ((previous (context-previous-root *context*)))
    (funcall function)
    (when (and (state-open-p state) (null previous)) (request-frame))
    (when (and (state-open-p state) previous)
      (snapshot state previous)
      (let* ((*parent* (context-root *context*))
             (hover (context-hover *context*))
             (key (when (and (consp hover) (eq (first hover) :lui.debug)
                             (member (second hover) '(:row :collapse)))
                    (third hover)))
             (node (gethash key (state-nodes state))))
        (when node
          (highlight (element-box node) :bounds 0.18 "#ff8c00")
          (when (clipped-p node)
            (highlight (element-clip node) :clip 0 "#00c0ff")))
        (inspector state toolkit)))))

(fn (wrap function) ((function function) &key ((state state) *state*)
                    (toolkit :glass))
  (lambda () (draw function :state state :toolkit toolkit)))
