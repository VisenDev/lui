(defpackage #:lui.web.input
  (:use #:cl #:lui.fn #:lui.frame #:lui.widgets)
  (:import-from #:lui.js #:property #:invoke #:global #:new #:same-p)
  (:export #:install-input #:update-accessibility))

(in-package #:lui.web.input)

(fn (install-input function)
    (host canvas (context context) (queue function) &key page-scroll-p
                                                      scroll-page)
  "Install canvas input and one shared IME sink. Return an idempotent cleanup."
  (let ((sink (invoke (global "document") "createElement" "textarea"))
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
        (old-tab (invoke canvas "getAttribute" "tabindex"))
        (old-touch (property canvas "style" "touchAction"))
        (old-cursor (property canvas "style" "cursor")))
    (labels
        ((listen (node name callback)
           (setf callback (lui.js:callback callback))
           (let ((options (new (global "Object"))))
             (setf (property options "passive") nil)
             (invoke node "addEventListener" name callback options))
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
         (stop (event) (invoke event "preventDefault"))
         (flag (event name)
           (property event name))
         (focus-without-scroll (element)
           (let ((options (new (global "Object"))))
             (setf (property options "preventScroll") t)
             (invoke element "focus" options)))
         (release ()
           (let ((id pointer))
             (setf pointer nil)
             (when (and id (invoke canvas "hasPointerCapture" id))
               (invoke canvas "releasePointerCapture" id))))
         (cancel ()
           (setf touch-start nil touch-motion nil touch-y nil)
           (release)
           (send (make-event :kind :cancel :buttons 0)))
         (current-p (event)
           (or (null pointer)
               (eql pointer (property event "pointerId"))))
         (position-event (event kind &rest arguments)
           (let ((rect (invoke host "getBoundingClientRect")))
             (apply #'make-event :kind kind :x (- (property event "clientX")
                          (property rect "left"))
                    :y (- (property event "clientY")
                          (property rect "top")) arguments)))
         (pointer-event (event kind)
           (let ((input (position-event event kind
                         :buttons (truncate (property event "buttons"))
                         :button (if (= 2 (property event "button"))
                                     :secondary :primary)
                         :clicks (max 1 (truncate
                                         (property event "detail"))))))
             (setf (property canvas "style" "cursor")
                   (case (cursor-at context (event-x input) (event-y input))
                     (:pointer "pointer") (:text "text")
                     (:not-allowed "not-allowed")
                     (:resize-horizontal "ew-resize")
                     (:resize-vertical "ns-resize")
                     (otherwise "default")))
             (send input)))
         (text (value)
           (when (and value (not (same-p value lui.js:+null+))
                      (not (same-p value lui.js:+undefined+)))
             (unless (zerop (length value))
               (send (make-event :kind :text :value value))))))
      ;; A single offscreen control supplies browser text services for all fields.
      (invoke sink "setAttribute" "aria-label" "Text input")
      (setf (property sink "tabIndex") -1
            (property sink "style" "cssText")
            "position:absolute;left:0;top:0;width:1px;height:1px;opacity:0;pointer-events:none"
            (property canvas "tabIndex") 0
            (property canvas "style" "touchAction")
            (if page-scroll-p "pinch-zoom" "none"))
      (invoke host "appendChild" sink)
      (setf (context-copy context)
            (lambda (value)
              (let ((clipboard (property (global "navigator") "clipboard")))
                (unless (same-p clipboard lui.js:+undefined+)
                  (let ((promise (invoke clipboard "writeText" value)))
                    (invoke promise "catch"
                            (lui.js:callback
                             (lambda (error) (declare (ignore error))))))))))
      (listen canvas "focus"
              (lambda (event) (declare (ignore event))
                (unless page-scroll-p (focus-without-scroll sink))))
      (listen host "pointerdown"
              (lambda (event)
                (when (and (current-p event)
                           (or (same-p (property event "target") canvas)
                               (and page-scroll-p
                                    (not (same-p (property event "target")
                                                 sink))
                                    (equal (property event "pointerType") "touch"))))
                  (setf touch-native (not (same-p (property event "target")
                                                  canvas)))
                  (let ((touch (and page-scroll-p
                                    (equal (property event "pointerType") "touch"))))
                    (when touch (funcall scroll-page 0))
                    (setf touch-start (when touch
                                        (cons (property event "clientX")
                                              (property event "clientY"))))
                    ;; Suppress the compatibility mouse click that would refocus
                    ;; the canvas after we focus the editor.
                    (setf touch-time (property event "timeStamp")
                          touch-velocity 0 touch-motion (when touch :pending)
                          touch-y (when touch (property event "clientY")))
                    (unless touch-native (stop event))
                    (unless touch (focus-without-scroll sink))
                    (setf pointer (property event "pointerId"))
                    (unless touch-native
                      (invoke canvas "setPointerCapture" pointer)
                      (pointer-event event :press))))))
      (listen host "pointermove"
              (lambda (event)
                (when (and (current-p event)
                           (or pointer (same-p (property event "target")
                                               canvas)))
                  (cond
                    (touch-start
                     (let* ((x (property event "clientX"))
                            (y (property event "clientY"))
                            (dx (- x (car touch-start)))
                            (dy (- y (cdr touch-start)))
                            (selection (invoke (global
                                                "window") "getSelection"))
                            (selecting (and touch-native
                                            (not (same-p selection
 lui.js:+null+))
                                            (invoke selection "containsNode"
                                                    (property
                                                     event "target") t)
                                            (not (property selection
                                                           "isCollapsed")))))
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
                          (let ((elapsed (- (property event "timeStamp")
                                            touch-time)))
                            (when (plusp elapsed)
                              (setf touch-velocity (/ (- touch-y y)
                                                      elapsed))))
                          (funcall scroll-page (- touch-y y)))
                         (:horizontal
                          (unless touch-native (pointer-event event :move)))
                         (otherwise nil))
                       (unless (eq touch-motion :pending)
                         (setf touch-y y touch-time (property event "timeStamp")))))
                    (t (pointer-event event :move))))))
      (listen host "pointerup"
              (lambda (event)
                (when (and pointer (current-p event))
                  (when (eq touch-motion :pan)
                    (funcall scroll-page 0
                             (if (< (- (property event "timeStamp")
                                       touch-time) 100) touch-velocity 0)))
                  (unless (or touch-native (eq touch-motion :pan))
                    (pointer-event event :release))
                  (when (and (not touch-native)
                             (not (eq touch-motion :pan)) touch-start
                             (< (abs (- (car touch-start)
                                        (property event "clientX"))) 8)
                             (< (abs (- (cdr touch-start)
                                        (property event "clientY"))) 8))
                    (let ((input (input-context)) (position (position-event
                                                             event :release)))
                      (focus-without-scroll
                       (if (and (text-field-focused-p input)
                                (equal (context-focus input)
                                       (lui.frame::hit input (event-x
                                                              position)
                                                       (event-y position))))
                           sink canvas))))
                  (setf touch-start nil touch-motion nil touch-y nil
                        touch-native nil)
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
                  (let* ((mode (truncate (property event "deltaMode")))
                         (delta (property event "deltaY"))
                         (pixels (* delta (case mode
                                            (1 16)
                                            (2 (context-height context))
                                            (otherwise 1)))))
                    (if (and page-scroll-p scroll-page)
                        (funcall scroll-page pixels)
                        (send (position-event event :scroll
                               :scroll-mode (if (and (zerop mode)
                                                     (< (abs delta) 20))
                                                :immediate :smooth)
                               :value pixels)))))))
      ;; Touch taps can focus the canvas without summoning the software keyboard.
      (listen host "keydown"
              (lambda (event)
                (unless (or (not (or (same-p (property event "target") canvas)
                                     (same-p (property event "target") sink)))
                            composing (flag event "isComposing")
                            (= 229 (property event "keyCode")))
                  (let* ((key (property event "key"))
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
                       (send (make-event :kind :key
                              :key (if (and editing shift)
                                       (case command
                                         (:left :shift-left)
                                         (:right :shift-right)
                                         (:home :shift-home)
                                         (:end :shift-end)
                                         (otherwise command)) command)))))))))
      (listen sink "compositionstart"
              (lambda (event) (declare (ignore event))
                (setf composing t)))
      (listen sink "compositionend"
              (lambda (event)
                (setf composing nil)
                (text (property event "data"))
                (setf (property sink "value") "")))
      (listen sink "beforeinput"
              (lambda (event)
                (unless (or composing (flag event "isComposing"))
                  (stop event)
                  ;; Composition text was committed by COMPOSITIONEND.
                  (unless (member
                           (property event "inputType")
                           '("insertCompositionText" "insertFromComposition"
                             "insertFromPaste") :test #'string=)
                    (text (property event "data"))))))
      (listen sink "input"
              (lambda (event) (declare (ignore event))
                (unless composing
                  (setf (property sink "value") ""))))
      (listen sink "paste"
              (lambda (event)
                (stop event)
                (text (invoke (property event "clipboardData") "getData"
                                        "text/plain"))))
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
                                     (invoke (property event "clipboardData")
                                             "setData"
                                             "text/plain" value)))
                             (lui.draw::copy-selection context nodes
                              (or (context-selection context)
                                  (lui.draw::make-text-selection))))
                        (setf (context-copy context) original)))
                    (when (and copied (text-field-focused-p context)
                               (string= "cut"
                                        (property event "type")))
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
                (setf (property sink "value") "")
                (cancel)))
      (listen (global "window") "blur"
              (lambda (event) (declare (ignore event)) (cancel)))
      (lambda ()
        (when alive
          (cancel)
          (setf alive nil)
          (dolist (listener listeners)
            (destructuring-bind (node name callback) listener
              (invoke node "removeEventListener" name callback)))
          (invoke sink "remove")
          (if (same-p old-tab lui.js:+null+)
              (invoke canvas "removeAttribute" "tabindex")
              (invoke canvas "setAttribute" "tabindex" old-tab))
          (setf (property canvas "style" "touchAction") old-touch
                (property canvas "style" "cursor") old-cursor)
          (setf listeners nil (context-copy context) old-copy))))))


(fn (update-accessibility t) (canvas (context context))
  "Describe the focused canvas control through the shared browser input sink."
  (let* ((host (property canvas "parentNode"))
         (sink (invoke host "querySelector" "textarea"))
         (node (gethash (context-focus context)
                        (lui.frame::context-ids context)))
         (widget (when node (lui.layout:element-content node))))
    (unless (same-p sink lui.js:+null+)
      (let ((label (if (and widget (widget-p widget))
                       (or (widget-accessible-name widget)
                           (let ((text (widget-text widget)))
                             (if (plusp (length text)) text
                                 (princ-to-string (context-focus context)))))
                       "Canvas application"))
            (value (if (and widget (widget-p widget)
                            (eq (widget-kind widget) :text-field))
                       (widget-display-value widget) "")))
        (setf (property sink "spellcheck")
              (if (and (widget-p widget) (widget-password-p widget)) nil t))
        (invoke sink "setAttribute" "autocorrect" "off")
        (invoke sink "setAttribute" "autocapitalize" "off")
        (invoke sink "setAttribute" "aria-label" label)
        (invoke sink "setAttribute" "aria-valuetext" value)
        (invoke canvas "setAttribute" "aria-label" label)))))
