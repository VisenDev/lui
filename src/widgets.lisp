(defpackage #:lui.widgets
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame)
  (:export #:widget #:widget-p #:widget-kind #:widget-style #:widget-text
           #:widget-foreground #:widget-background #:widget-radius
           #:widget-frost
           #:widget-terminal-text #:declare-panel #:declare-widget #:value-widget
           #:make-widget
           #:widget-value #:widget-minimum #:widget-maximum #:widget-step
           #:widget-font-size #:widget-opacity #:widget-accent
           #:widget-disabled-p
           #:widget-painter #:edit-state #:edit-state-cursor
           #:edit-state-anchor))

(in-package #:lui.widgets)

(defstruct widget
  (kind :label :type symbol)
  (style :glass :type symbol)
  value
  (minimum 0 :type real)
  (maximum 1 :type real)
  (step 0.01 :type real)
  (font-size 16 :type real)
  (opacity 0.85 :type real)
  (accent "#258bff" :type string)
  (disabled-p nil :type boolean)
  (painter nil :type (or null function))
  (text "" :type string)
  (terminal-text "" :type string)
  (foreground "#ffffff" :type string)
  (background "#303040" :type string)
  (radius 12 :type real)
  (frost 12 :type real))

(fn declare-widget
    ((kind symbol) (style symbol) id (text string) &key ((width sizing) (fit))
     ((height sizing) (fit)) ((padding real) 0)
     ((foreground string) "#ffffff") ((background string) "#303040")
     ((radius real) 12) ((frost real) 12) value ((minimum real) 0)
     ((maximum real) 1) ((step real) 0.01) ((font-size real) 16)
     ((opacity real) 0.85) ((accent string) "#258bff") (disabled-p nil)
     painter)
  (let ((measure (or (context-measure *context*)
                     (error "A backend text measurer is required.")))
        (widget
          (make-widget
           :kind kind :style style :text text :foreground foreground
           :background background :radius radius :frost frost :value value
           :minimum minimum :maximum maximum :step step :font-size font-size
           :opacity opacity :accent accent
           :disabled-p (not (null disabled-p)) :painter painter
           :terminal-text
           (case kind
             (:label text)
             (:checkbox (format nil "[~A] ~A" (if value "x" " ") text))
             (:slider
              (format nil "~A [~D%]" text
                      (round (* 100 (/ (- value minimum)
                                        (- maximum minimum))))))
             (:text-field (format nil "[~A]" value))
             (otherwise
              (format nil (if (eq style :motif) "[ ~A ]" "( ~A )") text))))))
    (emit (make-element
           :id id :content widget :width width :height height :padding padding
           :interactive-p (and (not disabled-p) (not (eq kind :label)))
           :measure (lambda (available) (funcall measure widget available))))
    (and (not disabled-p) (eq kind :button) (activated-p id))))

(defstruct edit-state
  (cursor 0 :type integer)
  (anchor 0 :type integer))

(fn edit-text ((text string) (state edit-state) (events list))
  (dolist (event events)
    (setf (edit-state-cursor state)
          (min (length text) (edit-state-cursor state))
          (edit-state-anchor state)
          (min (length text) (edit-state-anchor state)))
    (let ((start (min (edit-state-cursor state) (edit-state-anchor state)))
          (end (max (edit-state-cursor state) (edit-state-anchor state))))
      (labels ((replace-selection (replacement)
                 (setf text
                       (concatenate 'string (subseq text 0 start) replacement
                                    (subseq text end))
                       (edit-state-cursor state)
                       (+ start (length replacement))
                       (edit-state-anchor state)
                       (edit-state-cursor state)))
               (move-cursor (position &optional extend)
                 (setf (edit-state-cursor state)
                       (max 0 (min (length text) position)))
                 (unless extend
                   (setf (edit-state-anchor state)
                         (edit-state-cursor state)))))
        (case (event-kind event)
          (:change
           (when (stringp (event-value event))
             (setf text (event-value event))
             (move-cursor (length text))))
          (:text (replace-selection (event-value event)))
          (:key
           (case (event-key event)
             (:left (move-cursor (if (< start end) start (1- start))))
             (:right (move-cursor (if (< start end) end (1+ end))))
             (:shift-left
              (move-cursor (1- (edit-state-cursor state)) t))
             (:shift-right
              (move-cursor (1+ (edit-state-cursor state)) t))
             (:home (move-cursor 0))
             (:end (move-cursor (length text)))
             (:select-all
              (setf (edit-state-anchor state) 0
                    (edit-state-cursor state) (length text)))
             (:backspace
              (when (= start end) (setf start (max 0 (1- start))))
              (replace-selection ""))
             (:delete
              (when (= start end)
                (setf end (min (length text) (1+ end))))
              (replace-selection ""))
             (otherwise nil)))
          (otherwise nil)))))
  text)

(fn value-widget
    ((kind symbol) (style symbol) id value (text string) (options list))
  (let ((original value)
        (events (unless (getf options :disabled-p) (events-for id))))
    (ecase kind
      (:checkbox
       (when (and (not (getf options :disabled-p)) (activated-p id))
         (setf value (not value)))
       (dolist (event events)
         (when (eq (event-kind event) :change)
           (setf value (not (null (event-value event)))))))
      (:slider
       (let ((minimum (getf options :minimum 0))
             (maximum (getf options :maximum 1))
             (step (getf options :step 0.01))
             (box (previous-box id)))
         (assert (and (< minimum maximum) (> step 0)))
         (dolist (event events)
           (case (event-kind event)
             (:change
              (when (realp (event-value event))
                (setf value (event-value event))))
             ((:press :move)
              (when (and box (plusp (box-width box)))
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
    (apply #'declare-widget kind style id text :value value options)
    (values value (not (equal original value)))))


(fn (declare-panel element) ((style symbol) (options list))
  "Declare a styled layout container without introducing retained widgets."
  (let ((appearance nil) (layout nil))
    (loop :for (key value) :on options :by #'cddr
          :do (if (member key '(:foreground :background :radius :frost
                               :opacity :accent :font-size :painter))
                  (setf appearance (append appearance (list key value)))
                  (setf layout (append layout (list key value)))))
    (emit (apply #'make-element
                 :content (apply #'make-widget :kind :panel :style style
                                 appearance)
                 layout))))
