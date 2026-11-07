(defpackage #:lui.web.input
  (:use #:cl #:lui.fn #:lui.frame #:lui.widgets)
  (:export #:install-input #:update-accessibility))

(in-package #:lui.web.input)

(fn (install-input function)
    (host canvas (context context) (queue function) &key page-scroll-p scroll-page)
  "Install canvas input and one shared IME sink. Return an idempotent cleanup."
  (let ((sink (#j:document:createElement #j"textarea"))
        (listeners nil)
        (pending nil)
        (pending-root (context-root context))
        (pointer nil)
        (touch-start nil)
        (touch-motion nil)
        (touch-y nil)
        (touch-native nil)
        (touch-time nil)
        (touch-velocity 0)
        (composing nil)
        (alive t)
        (old-copy (context-copy context))
        (old-tab ((jscl/ffi:oget canvas "getAttribute") #j"tabindex"))
        (old-touch (jscl/ffi:oget canvas "style" "touchAction"))
        (old-cursor (jscl/ffi:oget canvas "style" "cursor")))
    (labels
        ((listen (node name callback)
           (let ((options (jscl/ffi:new #j:Object)))
             (setf (jscl/ffi:oget options "passive") #j:false)
             ((jscl/ffi:oget node "addEventListener")
              (jscl/ffi:jsstring name) callback options))
           (push (list node name callback) listeners))
         (input-context ()
           (unless (eq pending-root (context-root context))
             (setf pending nil pending-root (context-root context)))
           (pending-input-context context pending))
         (send (event)
           (when alive
             (input-context)
             (push event pending)
             (funcall queue event)))
         (stop (event) ((jscl/ffi:oget event "preventDefault")))
         (flag (event name)
           (jscl/ffi:clbool (jscl/ffi:oget event name)))
         (focus-without-scroll (element)
           (let ((options (jscl/ffi:new #j:Object)))
             (setf (jscl/ffi:oget options "preventScroll") #j:true)
             ((jscl/ffi:oget element "focus") options)))
         (release ()
           (let ((id pointer))
             (setf pointer nil)
             (when (and id (jscl/ffi:clbool
                            ((jscl/ffi:oget canvas "hasPointerCapture") id)))
               ((jscl/ffi:oget canvas "releasePointerCapture") id))))
         (cancel ()
           (setf touch-start nil touch-motion nil touch-y nil)
           (release)
           (send (make-event :kind :cancel :buttons 0)))
         (current-p (event)
           (or (null pointer)
               (eql pointer (jscl/ffi:oget event "pointerId"))))
         (position-event (event kind &rest arguments)
           (let ((rect ((jscl/ffi:oget host "getBoundingClientRect"))))
             (apply #'make-event :kind kind
                    :x (- (jscl/ffi:oget event "clientX")
                          (jscl/ffi:oget rect "left"))
                    :y (- (jscl/ffi:oget event "clientY")
                          (jscl/ffi:oget rect "top")) arguments)))
         (pointer-event (event kind)
           (let ((input (position-event
                         event kind
                         :buttons (jscl/ffi:oget event "buttons")
                         :button (if (= 2 (jscl/ffi:oget event "button"))
                                     :secondary :primary)
                         :clicks (max 1 (jscl/ffi:oget event "detail")))))
             (setf (jscl/ffi:oget canvas "style" "cursor")
                   (jscl/ffi:jsstring
                    (case (cursor-at context (event-x input) (event-y input))
                      (:pointer "pointer") (:text "text")
                      (:not-allowed "not-allowed")
                      (:resize-horizontal "ew-resize")
                      (:resize-vertical "ns-resize")
                      (otherwise "default"))))
             (send input)))
         (text (value)
           (when (and value (not (eq value #j:null))
                      (not (eq value #j:undefined)))
             (let ((value (jscl/ffi:clstring value)))
               (unless (zerop (length value))
                 (send (make-event :kind :text :value value)))))))
      ;; A single offscreen control supplies browser text services for all fields.
      ((jscl/ffi:oget sink "setAttribute") #j"aria-label" #j"Text input")
      (setf (jscl/ffi:oget sink "tabIndex") -1
            (jscl/ffi:oget sink "style" "cssText")
            #j"position:absolute;left:0;top:0;width:1px;height:1px;opacity:0;pointer-events:none"
            (jscl/ffi:oget canvas "tabIndex") 0
            (jscl/ffi:oget canvas "style" "touchAction")
            (if page-scroll-p #j"pinch-zoom" #j"none"))
      ((jscl/ffi:oget host "appendChild") sink)
      (setf (context-copy context)
            (lambda (value)
              (let ((clipboard (jscl/ffi:oget #j:navigator "clipboard")))
                (unless (eq clipboard #j:undefined)
                  (let ((promise ((jscl/ffi:oget clipboard "writeText")
                                  (jscl/ffi:jsstring value))))
                    ((jscl/ffi:oget promise "catch")
                     (lambda (error) (declare (ignore error)))))))))
      (listen canvas "focus"
              (lambda (event) (declare (ignore event))
                (unless page-scroll-p (focus-without-scroll sink))))
      (listen host "pointerdown"
              (lambda (event)
                (when (and (current-p event)
                           (or (eq (jscl/ffi:oget event "target") canvas)
                               (and page-scroll-p
                                    (not (eq (jscl/ffi:oget event "target") sink))
                                    (equal (jscl/ffi:oget event "pointerType") #j"touch"))))
                  (setf touch-native (not (eq (jscl/ffi:oget event "target") canvas)))
                  (let ((touch (and page-scroll-p
                                    (equal (jscl/ffi:oget event "pointerType") #j"touch"))))
                    (when touch (funcall scroll-page 0))
                    (setf touch-start (when touch
                                        (cons (jscl/ffi:oget event "clientX")
                                              (jscl/ffi:oget event "clientY"))))
                    ;; Suppress the compatibility mouse click that would refocus
                    ;; the canvas after we focus the editor.
                    (setf touch-time (jscl/ffi:oget event "timeStamp")
                          touch-velocity 0
                          touch-motion (when touch :pending)
                          touch-y (when touch (jscl/ffi:oget event "clientY")))
                    (unless touch-native (stop event))
                    (unless touch (focus-without-scroll sink))
                    (setf pointer (jscl/ffi:oget event "pointerId"))
                    (unless touch-native
                      ((jscl/ffi:oget canvas "setPointerCapture") pointer)
                      (pointer-event event :press))))))
      (listen host "pointermove"
              (lambda (event)
                (when (and (current-p event)
                           (or pointer (eq (jscl/ffi:oget event "target") canvas)))
                  (cond
                    (touch-start
                     (let* ((x (jscl/ffi:oget event "clientX"))
                            (y (jscl/ffi:oget event "clientY"))
                            (dx (- x (car touch-start)))
                            (dy (- y (cdr touch-start)))
                            (selection (#j:window:getSelection))
                            (selecting (and touch-native
                                            (not (eq selection #j:null))
                                            (jscl/ffi:clbool
                                             ((jscl/ffi:oget selection "containsNode")
                                              (jscl/ffi:oget event "target") #j:true))
                                            (not (jscl/ffi:clbool
                                                  (jscl/ffi:oget selection "isCollapsed"))))))
                       ;; Delay the shared drag until the gesture has a direction.
                       ;; A pan cancels the press, so lifting cannot activate it.
                       (when selecting (setf touch-motion :selection))
                       (when (and (eq touch-motion :pending)
                                  (>= (max (abs dx) (abs dy)) 8))
                         (setf touch-motion
                               (if (and scroll-page (> (abs dy) (abs dx)))
                                   :pan :horizontal))
                         (when (and (eq touch-motion :pan) (not touch-native))
                           (send (make-event :kind :cancel :buttons 0))))
                       (case touch-motion
                         (:pan
                          (stop event)
                          (let ((elapsed (- (jscl/ffi:oget event "timeStamp") touch-time)))
                            (when (plusp elapsed)
                              (setf touch-velocity (/ (- touch-y y) elapsed))))
                          (funcall scroll-page (- touch-y y)))
                         (:horizontal (unless touch-native (pointer-event event :move))))
                       (unless (eq touch-motion :pending)
                         (setf touch-y y touch-time (jscl/ffi:oget event "timeStamp")))))
                    (t (pointer-event event :move))))))
      (listen host "pointerup"
              (lambda (event)
                (when (and pointer (current-p event))
                  (when (eq touch-motion :pan)
                    (funcall scroll-page 0
                             (if (< (- (jscl/ffi:oget event "timeStamp") touch-time) 100)
                                 touch-velocity 0)))
                  (unless (or touch-native (eq touch-motion :pan))
                    (pointer-event event :release))
                  (when (and (not touch-native) (not (eq touch-motion :pan)) touch-start
                             (< (abs (- (car touch-start) (jscl/ffi:oget event "clientX"))) 8)
                             (< (abs (- (cdr touch-start) (jscl/ffi:oget event "clientY"))) 8))
                    (let ((input (input-context)) (position (position-event event :release)))
                      (focus-without-scroll
                       (if (and (text-field-focused-p input)
                                (equal (context-focus input)
                                       (lui.frame::hit input (event-x position) (event-y position))))
                           sink canvas))))
                  (setf touch-start nil touch-motion nil touch-y nil touch-native nil)
                  (release))))
      (dolist (name '("pointercancel" "lostpointercapture"))
        (listen host name
                (lambda (event)
                  (when (and pointer (current-p event)) (cancel)))))
      (listen canvas "pointerleave"
              (lambda (event)
                (unless pointer (pointer-event event :move))))
      (listen host "wheel"
              (lambda (event)
                ;; Keep browser zoom shortcuts native.
                (unless (and page-scroll-p (flag event "ctrlKey"))
                  (stop event)
                  (let* ((mode (jscl/ffi:oget event "deltaMode"))
                         (delta (jscl/ffi:oget event "deltaY"))
                         (pixels (* delta (case mode
                                            (1 16)
                                            (2 (context-height context))
                                            (otherwise 1)))))
                    (if (and page-scroll-p scroll-page)
                        (funcall scroll-page pixels)
                        (send (position-event
                               event :scroll
                               :scroll-mode (if (and (zerop mode)
                                                     (< (abs delta) 20))
                                                :immediate :smooth)
                               :value pixels)))))))
      ;; Touch taps can focus the canvas without summoning the software keyboard.
      (listen host "keydown"
              (lambda (event)
                (unless (or (not (or (eq (jscl/ffi:oget event "target") canvas)
                                     (eq (jscl/ffi:oget event "target") sink)))
                            composing (flag event "isComposing")
                            (eql 229 (jscl/ffi:oget event "keyCode")))
                  (let* ((key (jscl/ffi:clstring
                               (jscl/ffi:oget event "key")))
                         (control (flag event "ctrlKey"))
                         (alt (flag event "altKey"))
                         (meta (flag event "metaKey"))
                         (shift (flag event "shiftKey"))
                         (input (input-context))
                         (editing (text-field-focused-p input))
                         (command
                           (or (when (and editing (not meta)
                                          (not (and control alt)))
                                 (readline-key key :control control
                                                   :alt alt :shift shift))
                               (cdr (assoc key
                                      '(("ArrowLeft" . :left)
                                        ("ArrowRight" . :right)
                                        ("ArrowUp" . :up)
                                        ("ArrowDown" . :down)
                                        ("Home" . :home) ("End" . :end)
                                        ("PageUp" . :page-up)
                                        ("PageDown" . :page-down)
                                        ("Backspace" . :backspace)
                                        ("Delete" . :delete)
                                        ("Escape" . :escape))
                                      :test #'string=)))))
                    (cond
                      ;; Clipboard shortcuts must reach browser clipboard events.
                      ((and (or control meta) (not alt)
                            (member (string-downcase key) '("c" "v" "x")
                                    :test #'string=)))
                      ((string= key "Tab")
                       (stop event)
                       (send (make-event :kind :tab
                                         :key (when shift :backward))))
                      ((or (string= key "Enter")
                           (and (string= key " ")
                                (activation-focused-p input)))
                       (stop event) (send (make-event :kind :activate)))
                      (command
                       (stop event)
                       (send (make-event
                              :kind :key
                              :key (if (and editing shift)
                                       (case command
                                         (:left :shift-left)
                                         (:right :shift-right)
                                         (:home :shift-home)
                                         (:end :shift-end)
                                         (otherwise command))
                                       command)))))))))
      (listen sink "compositionstart"
              (lambda (event) (declare (ignore event))
                (setf composing t)))
      (listen sink "compositionend"
              (lambda (event)
                (setf composing nil)
                (text (jscl/ffi:oget event "data"))
                (setf (jscl/ffi:oget sink "value") #j"")))
      (listen sink "beforeinput"
              (lambda (event)
                (unless (or composing (flag event "isComposing"))
                  (stop event)
                  ;; Composition text was committed by COMPOSITIONEND.
                  (unless (member
                           (jscl/ffi:clstring
                            (jscl/ffi:oget event "inputType"))
                           '("insertCompositionText" "insertFromComposition"
                             "insertFromPaste") :test #'string=)
                    (text (jscl/ffi:oget event "data"))))))
      (listen sink "input"
              (lambda (event) (declare (ignore event))
                (unless composing
                  (setf (jscl/ffi:oget sink "value") #j""))))
      (listen sink "paste"
              (lambda (event)
                (stop event)
                (text ((jscl/ffi:oget event "clipboardData" "getData")
                       #j"text/plain"))))
      (dolist (name '("copy" "cut"))
        (listen sink name
                (lambda (event)
                  (stop event)
                  ;; Shared selection handling owns both editor and label text.
                  (let ((nodes (lui.draw::selectable-nodes context))
                        (context context)
                        (copied nil))
                    (let ((original (context-copy context)))
                      (unwind-protect
                           (progn
                             (setf (context-copy context)
                                   (lambda (value)
                                     (setf copied t)
                                     ((jscl/ffi:oget
                                       event "clipboardData" "setData")
                                      #j"text/plain"
                                      (jscl/ffi:jsstring value))))
                             (lui.draw::copy-selection
                              context nodes
                              (or (context-selection context)
                                  (lui.draw::make-text-selection))))
                        (setf (context-copy context) original)))
                    (when (and copied (text-field-focused-p context)
                               (string= "cut"
                                        (jscl/ffi:clstring
                                         (jscl/ffi:oget event "type"))))
                      (let ((state (gethash (context-focus context)
                                            (context-state context))))
                        (when (and (typep state 'edit-state)
                                   (/= (edit-state-anchor state)
                                       (edit-state-cursor state)))
                          (send (make-event :kind :key
                                            :key :backspace)))))))))
      (listen sink "blur"
              (lambda (event) (declare (ignore event))
                (setf composing nil)
                (setf (jscl/ffi:oget sink "value") #j"")
                (cancel)))
      (listen #j:window "blur"
              (lambda (event) (declare (ignore event)) (cancel)))
      (lambda ()
        (when alive
          (cancel)
          (setf alive nil)
          (dolist (listener listeners)
            (destructuring-bind (node name callback) listener
              ((jscl/ffi:oget node "removeEventListener")
               (jscl/ffi:jsstring name) callback)))
          ((jscl/ffi:oget sink "remove"))
          (if (eq old-tab #j:null)
              ((jscl/ffi:oget canvas "removeAttribute") #j"tabindex")
              ((jscl/ffi:oget canvas "setAttribute") #j"tabindex" old-tab))
          (setf (jscl/ffi:oget canvas "style" "touchAction") old-touch
                (jscl/ffi:oget canvas "style" "cursor") old-cursor)
          (setf listeners nil (context-copy context) old-copy))))))


(fn (update-accessibility t) (canvas (context context))
  "Describe the focused canvas control through the shared browser input sink."
  (let* ((host (jscl/ffi:oget canvas "parentNode"))
         (sink ((jscl/ffi:oget host "querySelector") #j"textarea"))
         (node (gethash (context-focus context)
                        (lui.frame::context-ids context)))
         (widget (when node (lui.layout:element-content node))))
    (unless (eq sink #j:null)
      (let* ((label (if (and widget (widget-p widget))
                        (or (widget-accessible-name widget)
                            (let ((text (widget-text widget)))
                              (if (plusp (length text)) text
                                  (princ-to-string (context-focus context)))))
                        "Canvas application"))
             (value (if (and widget (widget-p widget)
                             (eq (widget-kind widget) :text-field))
                        (widget-value widget) "")))
        ((jscl/ffi:oget sink "setAttribute") #j"aria-label"
         (jscl/ffi:jsstring label))
        ((jscl/ffi:oget sink "setAttribute") #j"aria-valuetext"
         (jscl/ffi:jsstring value))
        ((jscl/ffi:oget canvas "setAttribute") #j"aria-label"
         (jscl/ffi:jsstring label))))))
