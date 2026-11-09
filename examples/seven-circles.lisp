(defpackage #:lui.example.seven.circles
  (:use #:cl)
  (:export #:draw #:make-state #:state-model #:modal-p))
(in-package #:lui.example.seven.circles)

(defstruct state
  (model (lui.seven.model:make-circles) :type lui.seven.model:circles)
  hover
  (diameter 5 :type real)
  focus
  (focus-visible-p nil :type boolean)
  (restore-focus-p nil :type boolean))


(defun modal-p (state)
  (not (null (lui.seven.model:circles-editing (state-model state)))))

(defun begin-adjust (state id)
  (let ((model (state-model state)))
    (lui.seven.model:circle-begin-adjust model id)
    (setf (state-diameter state)
          (* 2 (lui.seven.model:circle-radius (lui.seven.model:circle-find model id)))
          (state-focus state) (lui.frame:context-focus lui.frame:*context*)
          (state-focus-visible-p state) (lui.frame:context-focus-visible-p lui.frame:*context*)
          (lui.frame:context-focus lui.frame:*context*) :circle-diameter
          (lui.frame:context-focus-visible-p lui.frame:*context*) t)
    (lui:request-frame)))

(defun finish-adjust (state commit-p)
  (if commit-p (lui.seven.model:circle-commit (state-model state))
      (lui.seven.model:circle-cancel (state-model state)))
  (setf (lui.frame:context-focus lui.frame:*context*) (or (state-focus state) :circle-canvas)
        (lui.frame:context-focus-visible-p lui.frame:*context*) (state-focus-visible-p state)
        (state-restore-focus-p state) t)
  (lui:request-frame))

(defun canvas-input (state)
  (unless (equal (lui.frame:context-hover lui.frame:*context*) :circle-canvas)
    (setf (state-hover state) nil))
  (let ((box (lui:previous-box :circle-canvas)) (model (state-model state)))
    (when box
      (loop for event across (lui.frame:events-for :circle-canvas) do
        (when (and (not (modal-p state))
                   (member (lui:event-kind event) '(:move :press)))
          (let* ((x (/ (- (lui:event-x event) (lui:box-x box)) lui:*unit*))
                 (y (/ (- (lui:event-y event) (lui:box-y box)) lui:*unit*))
                 (circle (lui.seven.model:circle-hit model x y)))
            (setf (state-hover state) (when circle (lui.seven.model:circle-id circle)))
            (when (eq (lui:event-kind event) :press)
              (cond ((and circle (eq (lui:event-button event) :secondary))
                     (begin-adjust state (lui.seven.model:circle-id circle)))
                    ((and (null circle)
                          (eq (lui:event-button event) :primary))
                     (lui.seven.model:circle-add model x y 2.5)
                     (lui:request-frame))))))))))

(defun commands (state)
  (loop :for circle :in (lui.seven.model:circles-items (state-model state))
        :collect (list :circle (lui:units (lui.seven.model:circle-x circle))
                       (lui:units (lui.seven.model:circle-y circle))
                       (lui:units (lui.seven.model:circle-radius circle))
                       "#000000"
                       (when (eql (lui.seven.model:circle-id circle) (state-hover state))
                         "#c8c8c8"))))

(defun draw-dialog (state)
  (lui:panel (lui:opt :id :circle-dialog :width (lui:grow)
                      :padding (lui:units 1) :gap (lui:units 1))
    (lui:label "Adjust circle diameter")
    (let* ((old (state-diameter state))
           (diameter (lui:slider :circle-diameter old
                                 (lui:opt :minimum 1 :maximum 20
                                          :step 0.1 :width (lui:grow)))))
      (unless (= old diameter)
        (setf (state-diameter state) diameter)
        (lui.seven.model:circle-preview (state-model state) (/ diameter 2))
        (lui:request-frame)))
    (lui:label (format nil "Diameter: ~,1F" (state-diameter state)))
    (lui:row (:gap (lui:units 1))
      (when (lui:button :circle-apply "Apply") (finish-adjust state t))
      (when (lui:button :circle-cancel "Cancel") (finish-adjust state nil)))))

(defun draw (state)
  (when (state-restore-focus-p state)
    (setf (lui.frame:context-focus lui.frame:*context*) (or (state-focus state) :circle-canvas)
          (lui.frame:context-focus-visible-p lui.frame:*context*) (state-focus-visible-p state)
          (state-restore-focus-p state) nil))
  (when (and (modal-p state) (lui:key-pressed-p :escape))
    (finish-adjust state nil))
  (unless (modal-p state) (canvas-input state))
  (let ((model (state-model state)))
    (lui:row (:gap (lui:units 1))
      (when (lui:button :circle-undo "Undo"
                        (lui:opt :disabled-p
                                 (or (modal-p state)
                                     (null (lui.seven.model:circles-undo model)))))
        (lui.seven.model:circle-undo model)
        (lui:request-frame))
      (when (lui:button :circle-redo "Redo"
                        (lui:opt :disabled-p
                                 (or (modal-p state)
                                     (null (lui.seven.model:circles-redo model)))))
        (lui.seven.model:circle-redo model)
        (lui:request-frame)))
    (lui:label "Click empty space to add; right-click a circle to resize.")
    (lui:canvas :circle-canvas (commands state)
                (lui:opt :background "#ffffff" :width (lui:grow)
                         :height (lui:grow) :disabled-p (modal-p state)))
    (when (modal-p state) (draw-dialog state))))
