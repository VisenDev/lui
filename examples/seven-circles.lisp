(defpackage #:lui.example.seven.circles
  (:use #:cl #:lui #:lui.layout #:lui.frame #:lui.interaction
        #:lui.seven.model)
  (:shadow #:draw)
  (:export #:draw #:make-state #:state-model #:modal-p))
(in-package #:lui.example.seven.circles)

(defstruct state
  (model (make-circles) :type circles)
  hover
  (diameter 5 :type real)
  focus
  (focus-visible-p nil :type boolean)
  (restore-focus-p nil :type boolean))


(defun modal-p (state)
  (not (null (circles-editing (state-model state)))))

(defun begin-adjust (state id)
  (let ((model (state-model state)))
    (circle-begin-adjust model id)
    (setf (state-diameter state)
          (* 2 (circle-radius (circle-find model id)))
          (state-focus state) (context-focus *context*)
          (state-focus-visible-p state) (context-focus-visible-p *context*)
          (context-focus *context*) :circle-diameter
          (context-focus-visible-p *context*) t)
    (request-frame)))

(defun finish-adjust (state commit-p)
  (if commit-p (circle-commit (state-model state))
      (circle-cancel (state-model state)))
  (setf (context-focus *context*) (or (state-focus state) :circle-canvas)
        (context-focus-visible-p *context*) (state-focus-visible-p state)
        (state-restore-focus-p state) t)
  (request-frame))

(defun canvas-input (state)
  (unless (equal (context-hover *context*) :circle-canvas)
    (setf (state-hover state) nil))
  (let ((box (previous-box :circle-canvas)) (model (state-model state)))
    (when box
      (loop for event across (events-for :circle-canvas) do
        (when (and (not (modal-p state))
                   (member (event-kind event) '(:move :press)))
          (let* ((x (/ (- (event-x event) (box-x box)) *unit*))
                 (y (/ (- (event-y event) (box-y box)) *unit*))
                 (circle (circle-hit model x y)))
            (setf (state-hover state) (when circle (circle-id circle)))
            (when (eq (event-kind event) :press)
              (cond ((and circle (eq (event-button event) :secondary))
                     (begin-adjust state (circle-id circle)))
                    ((and (null circle)
                          (eq (event-button event) :primary))
                     (circle-add model x y 2.5)
                     (request-frame))))))))))

(defun commands (state)
  (loop :for circle :in (circles-items (state-model state))
        :collect (list :circle (units (circle-x circle))
                       (units (circle-y circle))
                       (units (circle-radius circle))
                       "#000000"
                       (when (eql (circle-id circle) (state-hover state))
                         "#c8c8c8"))))

(defun draw-dialog (state)
  (lui:panel (lui:opt :id :circle-dialog :width (grow)
                      :padding (units 1) :gap (units 1))
    (lui:label "Adjust circle diameter")
    (let* ((old (state-diameter state))
           (diameter (lui:slider :circle-diameter old
                                 (lui:opt :minimum 1 :maximum 20
                                          :step 0.1 :width (grow)))))
      (unless (= old diameter)
        (setf (state-diameter state) diameter)
        (circle-preview (state-model state) (/ diameter 2))
        (request-frame)))
    (lui:label (format nil "Diameter: ~,1F" (state-diameter state)))
    (row (:gap (units 1))
      (when (lui:button :circle-apply "Apply") (finish-adjust state t))
      (when (lui:button :circle-cancel "Cancel") (finish-adjust state nil)))))

(defun draw (state)
  (when (state-restore-focus-p state)
    (setf (context-focus *context*) (or (state-focus state) :circle-canvas)
          (context-focus-visible-p *context*) (state-focus-visible-p state)
          (state-restore-focus-p state) nil))
  (when (and (modal-p state) (key-pressed-p :escape))
    (finish-adjust state nil))
  (unless (modal-p state) (canvas-input state))
  (let ((model (state-model state)))
    (row (:gap (units 1))
      (when (lui:button :circle-undo "Undo"
                        (lui:opt :disabled-p
                                 (or (modal-p state)
                                     (null (circles-undo model)))))
        (circle-undo model)
        (request-frame))
      (when (lui:button :circle-redo "Redo"
                        (lui:opt :disabled-p
                                 (or (modal-p state)
                                     (null (circles-redo model)))))
        (circle-redo model)
        (request-frame)))
    (lui:label "Click empty space to add; right-click a circle to resize.")
    (lui:canvas :circle-canvas (commands state)
                (lui:opt :background "#ffffff" :width (grow)
                         :height (grow) :disabled-p (modal-p state)))
    (when (modal-p state) (draw-dialog state))))
