(defpackage #:lui.web.input
  (:use #:cl #:lui.fn #:lui.frame #:lui.widgets)
  (:export #:install-input #:update-accessibility)
  (:import-from #:jscl/ffi #:clbool #:clstring #:jsstring #:new #:oget))

(in-package #:lui.web.input)

(defstruct input-session
  "Browser input resources and gesture state owned by one mounted application."
  (host nil :type t)
  (canvas nil :type t)
  (context (make-context) :type context)
  (queue #'identity :type function)
  (page-scroll-p nil :type boolean)
  (scroll-page nil :type (or null function))
  (sink nil :type t)
  (listeners nil :type list)
  (pending nil :type list)
  (pending-root nil :type (or null lui.layout:element))
  (pointer nil :type t)
  (touch-start nil :type list)
  (touch-motion nil :type symbol)
  (touch-y nil :type (or null real))
  (touch-native nil :type t)
  (touch-time nil :type (or null real))
  (touch-velocity 0 :type real)
  (composing nil :type boolean)
  (alive t :type boolean)
  (old-copy nil :type (or null function))
  (old-tab nil :type t)
  (old-touch nil :type t)
  (old-cursor nil :type t))

(fn (input-listen (values))
    ((session input-session) node (name string) (handler function))
  "Register a session event handler and retain its callback for cleanup."
  (let ((options (new #j:Object))
        (callback (lambda (event) (funcall handler session event))))
    (setf (oget options "passive") #j:false)
    ((oget node "addEventListener")
     (jsstring name) callback options)
    (push (list node name callback) (input-session-listeners session)))
  (values))

(fn (pending-session-context context) ((session input-session))
  "Resolve pending input against the current completed frame."
  (let ((context (input-session-context session)))
    (unless (eq (input-session-pending-root session) (context-root context))
      (setf (input-session-pending session) nil
            (input-session-pending-root session) (context-root context)))
    (pending-input-context context (input-session-pending session))))

(fn (input-send t)
    ((session input-session) event)
  "Queue input only while the session is alive, retaining pending focus changes."
  (when (input-session-alive session)
    (pending-session-context session)
    (push event (input-session-pending session))
    (funcall (input-session-queue session) event)))

(fn (input-stop t)
    (event)
  "Prevent the browser default action for an input event."
  ((oget event "preventDefault")))

(fn (input-flag boolean)
    (event (name string))
  "Read a JavaScript event flag as a Lisp boolean."
  (clbool (oget event name)))

(fn (input-focus-without-scroll t)
    (element)
  "Focus a native input element without moving its scroll container."
  (let ((options (new #j:Object)))
    (setf (oget options "preventScroll") #j:true)
    ((oget element "focus") options)))

(fn (input-release t)
    ((session input-session))
  "Release the session's captured pointer if capture is still held."
  (let ((id (input-session-pointer session)))
    (setf (input-session-pointer session) nil)
    (when (and id (clbool
                   ((oget (input-session-canvas session) "hasPointerCapture")
                    id)))
      ((oget (input-session-canvas session) "releasePointerCapture")
       id))))

(fn (input-cancel t)
    ((session input-session))
  "Cancel gesture state, release capture, and queue a cancellation event."
  (setf (input-session-touch-start session) nil
        (input-session-touch-motion session) nil
        (input-session-touch-y session) nil)
  (input-release session)
  (input-send session (make-event :kind :cancel :buttons 0)))

(fn (input-current-p boolean)
    ((session input-session) event)
  "Test whether EVENT belongs to the session's current pointer."
  (or (null (input-session-pointer session))
      (eql (input-session-pointer session) (oget event
                                                 "pointerId"))))

(fn (input-position-event event)
    ((session input-session) event kind &rest arguments)
  "Translate browser client coordinates into a LUI event relative to the host."
  (let ((rect ((oget (input-session-host session) "getBoundingClientRect"))))
    (apply #'make-event :kind kind
           :x (- (oget event "clientX")
                 (oget rect "left"))
           :y (- (oget event "clientY")
                 (oget rect "top")) arguments)))

(fn (input-pointer-event t)
    ((session input-session) event kind)
  "Queue pointer input and update the canvas cursor for its target."
  (let ((input (input-position-event session
                                     event kind
                                     :buttons (oget event "buttons")
                                     :button (if (= 2 (oget event "button"))
                                                 :secondary :primary)
                                     :clicks (max 1 (oget event "detail")))))
    (setf (oget (input-session-canvas session) "style" "cursor")
          (jsstring
           (case (cursor-at (input-session-context session) (event-x input)
                            (event-y input))
             (:pointer "pointer") (:text "text")
             (:not-allowed "not-allowed")
             (:resize-horizontal "ew-resize")
             (:resize-vertical "ns-resize")
             (otherwise "default"))))
    (input-send session input)))

(fn (input-text t)
    ((session input-session) value)
  "Queue nonempty text supplied by browser editing or clipboard events."
  (when (and value (not (eq value #j:null))
             (not (eq value #j:undefined)))
    (let ((value (clstring value)))
      (unless (zerop (length value))
        (input-send session (make-event :kind :text :value value))))))

(fn (dispose-input-session t) ((session input-session))
  "Remove listeners and the IME sink once, restoring the canvas and clipboard callback."
  (when (input-session-alive session)
    (input-cancel session)
    (setf (input-session-alive session) nil)
    (dolist (listener (input-session-listeners session))
      (destructuring-bind (node name callback) listener
        ((oget node "removeEventListener")
         (jsstring name) callback)))
    ((oget (input-session-sink session) "remove"))
    (if (eq (input-session-old-tab session) #j:null)
        ((oget (input-session-canvas session) "removeAttribute") #j"tabindex")
        ((oget (input-session-canvas session) "setAttribute") #j"tabindex"
         (input-session-old-tab session)))
    (setf (oget (input-session-canvas session) "style"
                "touchAction") (input-session-old-touch session)
                (oget (input-session-canvas session)
                      "style" "cursor")
                (input-session-old-cursor session))
    (setf (input-session-listeners session) nil (context-copy
                                                 (input-session-context
                                                  session))
          (input-session-old-copy session))))

(fn (configure-input-session (values)) ((session input-session))
  "Install the shared IME sink and clipboard writer for the session."
  ((oget (input-session-sink session) "setAttribute") #j"aria-label"
   #j"Text input")
  (setf (oget (input-session-sink session) "tabIndex") -1
        (oget (input-session-sink session) "style" "cssText")
        #j"position:absolute;left:0;top:0;width:1px;height:1px;opacity:0;pointer-events:none"
        (oget (input-session-canvas session) "tabIndex") 0
        (oget (input-session-canvas session) "style" "touchAction")
        (if (input-session-page-scroll-p session) #j"pinch-zoom" #j"none"))
  ((oget (input-session-host session) "appendChild")
   (input-session-sink session))
  (setf (context-copy (input-session-context session))
        (lambda (value)
          (let ((clipboard (oget #j:navigator "clipboard")))
            (unless (eq clipboard #j:undefined)
              (let ((promise ((oget clipboard "writeText")
                              (jsstring value))))
                ((oget promise "catch")
                 (lambda (error) (declare (ignore error)))))))))
  (values))

(fn (listen-input-session (values)) ((session input-session))
  "Register pointer, keyboard, composition, clipboard, and focus listeners."
  (flet ((attach (node bindings)
           (dolist (binding bindings)
             (input-listen session node (car binding)
                           (symbol-function (cdr binding))))))
    (attach (input-session-canvas session)
            '(("focus" . handle-browser-focus)
              ("pointerleave" . handle-browser-pointerleave)))
    (attach (input-session-host session)
            '(("pointerdown" . handle-browser-pointerdown)
              ("pointermove" . handle-browser-pointermove)
              ("pointerup" . handle-browser-pointerup)
              ("pointercancel" . handle-browser-cancel)
              ("lostpointercapture" . handle-browser-cancel)
              ("wheel" . handle-browser-wheel)
              ("keydown" . handle-browser-keydown)))
    (attach (input-session-sink session)
            '(("compositionstart" . handle-browser-compositionstart)
              ("compositionend" . handle-browser-compositionend)
              ("beforeinput" . handle-browser-beforeinput)
              ("input" . handle-browser-input)
              ("paste" . handle-browser-paste)
              ("copy" . handle-browser-clipboard)
              ("cut" . handle-browser-clipboard)
              ("blur" . handle-browser-blur))))
  (input-listen session #j:window "blur" #'handle-browser-window-blur)
  (values))

(fn (handle-browser-focus t)
    ((session input-session) event)
  "Handle the browser focus event for this input session."
  (declare (ignore event))
  (unless (input-session-page-scroll-p session)
    (input-focus-without-scroll (input-session-sink session))))

(fn (handle-browser-pointerdown t)
    ((session input-session) event)
  "Handle the browser pointerdown event for this input session."
  (when (and (input-current-p session event)
             (or (eq (oget event "target") (input-session-canvas
                                            session))
                 (and (input-session-page-scroll-p session)
                      (not (eq (oget event "target")
                               (input-session-sink session)))
                      (equal (oget event "pointerType") #j"touch"))))
    (setf (input-session-touch-native session)
          (not (eq (oget event "target") (input-session-canvas session))))
    (let ((touch (and (input-session-page-scroll-p session)
                      (equal (oget event "pointerType") #j"touch"))))
      (when touch (funcall (input-session-scroll-page session) 0))
      (setf (input-session-touch-start session) (when touch
                                                  (cons (oget event "clientX")
                                                        (oget event
                                                              "clientY"))))
      ;; Suppress the compatibility mouse click that would refocus
      ;; the canvas after we focus the editor.
      (setf (input-session-touch-time session) (oget event "timeStamp")
            (input-session-touch-velocity session) 0
            (input-session-touch-motion session) (when touch :pending)
            (input-session-touch-y session) (when touch (oget event
                                                              "clientY")))
      (unless (input-session-touch-native session) (input-stop event))
      (unless touch (input-focus-without-scroll (input-session-sink
                                                 session)))
      (setf (input-session-pointer session) (oget event "pointerId"))
      (unless (input-session-touch-native session)
        ((oget (input-session-canvas session) "setPointerCapture")
         (input-session-pointer session))
        (input-pointer-event session event :press)))))

(fn (native-touch-selection-p boolean)
    ((session input-session) selection event)
  "Test whether this touch is extending native browser text selection."
  (and (input-session-touch-native session)
       (not (eq selection #j:null))
       (clbool
        ((oget selection "containsNode")
         (oget event "target") #j:true))
       (not (clbool
             (oget selection "isCollapsed")))))

(fn (resolve-touch-direction (values))
    ((session input-session) (dx real) (dy real))
  "Resolve a pending gesture direction and cancel control activation when it becomes a pan."
  (when (and (eq (input-session-touch-motion session) :pending)
             (>= (max (abs dx) (abs dy)) 8))
    (setf (input-session-touch-motion session)
          (if (and (input-session-scroll-page session) (> (abs dy) (abs dx)))
              :pan :horizontal))
    (when (and (eq (input-session-touch-motion session) :pan)
               (not
                (input-session-touch-native session)))
      (input-send session (make-event :kind :cancel :buttons 0))))
  (values))

(fn (handle-browser-pointermove t)
    ((session input-session) event)
  "Handle the browser pointermove event for this input session."
  (when (and (input-current-p session event)
             (or (input-session-pointer session)
                 (eq (oget event "target") (input-session-canvas session))))
    (cond
      ((input-session-touch-start session)
       (let* ((x (oget event "clientX"))
              (y (oget event "clientY"))
              (dx (- x (car (input-session-touch-start session))))
              (dy (- y (cdr (input-session-touch-start session))))
              (selection (#j:window:getSelection))
              (selecting (native-touch-selection-p session selection event)))
         ;; Delay the shared drag until the gesture has a direction.
         ;; A pan cancels the press, so lifting cannot activate it.
         (when selecting (setf (input-session-touch-motion session)
                               :selection))
         (resolve-touch-direction session dx dy)
         (case (input-session-touch-motion session)
           (:pan
            (input-stop event)
            (let ((elapsed (- (oget event "timeStamp")
                              (input-session-touch-time session))))
              (when (plusp elapsed)
                (setf (input-session-touch-velocity session)
                      (/
                       (-
                        (input-session-touch-y session) y) elapsed))))
            (funcall (input-session-scroll-page session)
                     (-
                      (input-session-touch-y session) y)))
           (:horizontal
            (unless (input-session-touch-native session) (input-pointer-event
                                                          session event
                                                          :move)))
           (otherwise nil))
         (unless (eq (input-session-touch-motion session) :pending)
           (setf (input-session-touch-y session) y (input-session-touch-time
                                                    session) (oget
                                                    event "timeStamp")))))
      (t (input-pointer-event session event :move)))))

(fn (handle-browser-pointerup t)
    ((session input-session) event)
  "Handle the browser pointerup event for this input session."
  (when (and (input-session-pointer session) (input-current-p session event))
    (when (eq (input-session-touch-motion session) :pan)
      (funcall (input-session-scroll-page session) 0
               (if (< (- (oget event "timeStamp")
                         (input-session-touch-time session)) 100)
                   (input-session-touch-velocity session) 0)))
    (unless (or (input-session-touch-native session)
                (eq
                 (input-session-touch-motion session) :pan))
      (input-pointer-event session event :release))
    (when (and (not (input-session-touch-native session))
               (not
                (eq
                 (input-session-touch-motion session) :pan))
               (input-session-touch-start session)
               (< (abs (-
                        (car
                         (input-session-touch-start session))
                        (oget event "clientX"))) 8)
               (< (abs (-
                        (cdr
                         (input-session-touch-start session))
                        (oget event "clientY"))) 8))
      (let ((input (pending-session-context session)) (position
                                                       (input-position-event
                                                        session event
                                                        :release)))
        (input-focus-without-scroll (if
                                     (and (text-field-focused-p input)
                                          (equal (context-focus input)
                                                 (lui.frame::hit input
                                                                 (event-x
                                                                  position)
                                                                 (event-y
                                                                  position))))
                                     (input-session-sink session)
                                     (input-session-canvas session)))))
    (setf (input-session-touch-start session) nil
          (input-session-touch-motion session) nil
          (input-session-touch-y session) nil
          (input-session-touch-native session) nil)
    (input-release session)))

(fn (handle-browser-cancel t)
    ((session input-session) event)
  "Handle pointer capture cancellation."
  (when (and (input-session-pointer session) (input-current-p session event))
    (input-cancel session)))

(fn (handle-browser-pointerleave t)
    ((session input-session) event)
  "Handle the browser pointerleave event for this input session."
  (unless (input-session-pointer session) (input-pointer-event session event
                                                               :move)))

(fn (handle-browser-wheel t)
    ((session input-session) event)
  "Handle the browser wheel event for this input session."
  (unless (and (input-session-page-scroll-p session) (input-flag event "ctrlKey"))
    (input-stop event)
    (let* ((mode (oget event "deltaMode"))
           (delta (oget event "deltaY"))
           (pixels (* delta (case mode
                              (1 16)
                              (2 (context-height (input-session-context
                                                  session)))
                              (otherwise 1)))))
      (if (and (input-session-page-scroll-p session)
               (input-session-scroll-page session))
          (funcall (input-session-scroll-page session) pixels)
          (input-send session (input-position-event session
                                                    event :scroll
                                                    :scroll-mode
                                                    (if
                                                     (and
                                                      (zerop
                                                       mode)
                                                      (<
                                                       (abs
                                                        delta) 20))
                                                     :immediate :smooth)
                                                    :value pixels))))))

(fn (browser-key-command symbol)
    ((key string) editing meta control alt shift)
  "Resolve Readline commands and browser navigation key names."
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
                  :test #'string=))))

(fn (handle-browser-keydown t)
    ((session input-session) event)
  "Handle the browser keydown event for this input session."
  (unless (or (not (or (eq (oget event "target")
                           (input-session-canvas session))
                       (eq (oget event "target") (input-session-sink
                                                  session))))
              (input-session-composing session) (input-flag event "isComposing")
              (eql 229 (oget event "keyCode")))
    (let* ((key (clstring
                 (oget event "key")))
           (control (input-flag event "ctrlKey"))
           (alt (input-flag event "altKey"))
           (meta (input-flag event "metaKey"))
           (shift (input-flag event "shiftKey"))
           (input (pending-session-context session))
           (editing (text-field-focused-p input))
           (command
            (browser-key-command key editing meta control alt shift)))
      (cond
        ;; Clipboard shortcuts must reach browser clipboard events.
        ((and (or control meta) (not alt)
              (member (string-downcase key) '("c" "v" "x")
                      :test #'string=)))
        ((string= key "Tab")
         (input-stop event)
         (input-send session (make-event :kind :tab
                                         :key (when shift :backward))))
        ((or (string= key "Enter")
             (and (string= key " ")
                  (activation-focused-p input)))
         (input-stop event)
         (input-send session (make-event :kind
                                         :activate)))
        (command
         (input-stop event)
         (input-send session (make-event
                              :kind :key
                              :key (if (and editing shift)
                                       (case command
                                         (:left :shift-left)
                                         (:right :shift-right)
                                         (:home :shift-home)
                                         (:end :shift-end)
                                         (otherwise command))
                                       command))))))))

(fn (handle-browser-compositionstart t)
    ((session input-session) event)
  "Handle the browser compositionstart event for this input session."
  (declare (ignore event))
  (setf (input-session-composing session) t))

(fn (handle-browser-compositionend t)
    ((session input-session) event)
  "Handle the browser compositionend event for this input session."
  (setf (input-session-composing session) nil)
  (input-text session (oget event "data"))
  (setf (oget (input-session-sink session) "value") #j""))

(fn (handle-browser-beforeinput t)
    ((session input-session) event)
  "Handle the browser beforeinput event for this input session."
  (unless (or (input-session-composing session) (input-flag event "isComposing"))
    (input-stop event)
    ;; Composition text was committed by COMPOSITIONEND.
    (unless (member
             (clstring
              (oget event "inputType"))
             '("insertCompositionText" "insertFromComposition"
               "insertFromPaste") :test #'string=)
      (input-text session (oget event "data")))))

(fn (handle-browser-input t)
    ((session input-session) event)
  "Handle the browser input event for this input session."
  (declare (ignore event))
  (unless (input-session-composing session)
    (setf (oget (input-session-sink session) "value") #j"")))

(fn (handle-browser-paste t)
    ((session input-session) event)
  "Handle the browser paste event for this input session."
  (input-stop event)
  (input-text session ((oget event "clipboardData" "getData")
                       #j"text/plain")))

(fn (handle-browser-clipboard t)
    ((session input-session) event)
  "Handle browser copy and cut using the shared LUI selection."
  (input-stop event)
  ;; Shared selection handling owns both editor and label text.
  (let ((nodes (lui.draw::selectable-nodes (input-session-context session)))
        (copied nil))
    (let ((original (context-copy (input-session-context session))))
      (unwind-protect
           (progn
             (setf (context-copy (input-session-context session))
                   (lambda (value)
                     (setf copied t)
                     ((oget
                       event "clipboardData" "setData")
                      #j"text/plain"
                      (jsstring value))))
             (lui.draw::copy-selection
              (input-session-context session) nodes
              (or (context-selection (input-session-context session))
                  (lui.draw::make-text-selection))))
        (setf (context-copy (input-session-context session)) original)))
    (when (and copied (text-field-focused-p (input-session-context session))
               (string= "cut"
                        (clstring
                         (oget event "type"))))
      (let ((state (gethash (context-focus (input-session-context session))
                            (context-state (input-session-context session)))))
        (when (and (typep state 'edit-state)
                   (/= (edit-state-anchor state)
                       (edit-state-cursor state)))
          (input-send session (make-event :kind :key
                                          :key :backspace)))))))

(fn (handle-browser-blur t)
    ((session input-session) event)
  "Handle the browser blur event for this input session."
  (declare (ignore event))
  (setf (input-session-composing session) nil)
  (setf (oget (input-session-sink session) "value") #j"")
  (input-cancel session))

(fn (handle-browser-window-blur t)
    ((session input-session) event)
  "Handle the browser blur event for this input session."
  (declare (ignore event)) (input-cancel session))

(fn (install-input function)
    (host canvas (context context) (queue function) &key page-scroll-p
                                                      scroll-page)
  "Install canvas input and one shared IME sink. Return an idempotent cleanup."
  (let ((session (make-input-session :host host :canvas canvas :context
                                     context
                                     :queue queue :page-scroll-p page-scroll-p
                                     :scroll-page scroll-page
                                     :sink (#j:document:createElement #j"textarea")
                                     :pending-root (context-root context)
                                     :old-copy (context-copy context)
                                     :old-tab ((oget canvas "getAttribute")
                                               #j"tabindex")
                                     :old-touch (oget canvas "style"
                                                      "touchAction")
                                     :old-cursor (oget canvas
                                                       "style" "cursor"))))
    (configure-input-session session)
    (listen-input-session session)
    (values (lambda () (dispose-input-session session)))))


(fn (update-accessibility t) (canvas (context context))
  "Describe the focused canvas control through the shared browser input sink."
  (let* ((host (oget canvas "parentNode"))
         (sink ((oget host "querySelector") #j"textarea"))
         (node (gethash (context-focus context)
                        (lui.frame::context-ids context)))
         (widget (when node (lui.layout:element-content node))))
    (unless (eq sink #j:null)
      (let ((label (if (and widget (widget-p widget))
                       (or (widget-accessible-name widget)
                           (let ((text (widget-text widget)))
                             (if (plusp (length text)) text
                                 (princ-to-string (context-focus context)))))
                       "Canvas application"))
            (value (if (and widget (widget-p widget)
                            (eq (widget-kind widget) :text-field))
                       (widget-display-value widget) "")))
        (setf (oget sink "spellcheck")
              (if (and (widget-p widget) (widget-password-p widget))
                  #j:false #j:true))
        ((oget sink "setAttribute") #j"autocorrect" #j"off")
        ((oget sink "setAttribute") #j"autocapitalize" #j"off")
        ((oget sink "setAttribute") #j"aria-label"
         (jsstring label))
        ((oget sink "setAttribute") #j"aria-valuetext"
         (jsstring value))
        ((oget canvas "setAttribute") #j"aria-label"
         (jsstring label))))))

(defpackage #:lui.web
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.draw)
  (:import-from #:lui
                #:mount #:unmount #:refresh)
  (:export #:mount #:unmount #:refresh)
  (:import-from #:jscl/ffi #:clbool #:jsstring #:new #:oget))
(in-package #:lui.web)

(defstruct web-app
  #+lui-ecl-web (ffi-owner nil :type list)
  host stage overlay canvas graphics renderer context callback cleanup
  observer resize
  scrollport (scroll-listener nil :type (or null function)) (viewport-offset
                                                             0)
  (scroll-delta 0) (velocity 0) (scroll-time 0)
  (overlay-order #() :type vector) overlay-geometry overlay-cache
  animation-frame deadline-timer events pending-p (alive-p t))

(fn (page-scrollport t) (host)
  "Find the nearest vertically scrolling ancestor of HOST, or the browser window."
  (do ((element host (oget element "parentElement")))
      ((eq element #j:null) #j:window)
    (let ((overflow (oget
                     (#j:window:getComputedStyle element) "overflowY")))
      (when (or (equal overflow #j"auto") (equal overflow #j"scroll"))
        (return element)))))

(fn (page-viewport-height real) (port)
  "Return the visible height of a scroll container in CSS pixels."
  (if (eq port #j:window)
      #j:window:innerHeight
      (oget port "clientHeight")))

(fn (page-offset real) (stage port)
  "Return STAGE's vertical offset relative to its scroll container's viewport."
  (let ((top (oget
              ((oget stage "getBoundingClientRect")) "top")))
    (if (eq port #j:window)
        (- top)
        (- (+ (oget
               ((oget port "getBoundingClientRect")) "top")
              (oget port "clientTop"))
           top))))

(fn (page-scroll-by t) (port delta)
  "Move PORT immediately by DELTA CSS pixels without browser smooth scrolling."
  (let ((options (new #j:Object)))
    (setf (oget options "top") delta
          (oget options "behavior") #j"instant")
    ((oget port "scrollBy") options)))

(fn (rounded-path t) (g (box box) radius &optional (inset 0))
  "Begin a rounded rectangular Canvas path, optionally inset from BOX."
  ((oget g "beginPath"))
  ((oget g "roundRect")
   (+ inset (box-x box)) (+ inset (box-y box))
   (max 0 (- (box-width box) (* 2 inset)))
   (max 0 (- (box-height box) (* 2 inset))) (max 0 (- radius inset))))

(fn (canvas-surface t) (g box radius color alpha &optional stroke)
  "Paint a filled or stroked rounded Canvas surface."
  (setf (oget g "globalAlpha") alpha)
  (if stroke
      (setf (oget g "lineWidth") stroke
            (oget g "strokeStyle") (jsstring color))
      (setf (oget g "fillStyle") (jsstring color)))
  (cond ((zerop radius)
         (if stroke
             ((oget g "strokeRect")
              (+ (box-x box) (/ stroke 2))
              (+ (box-y box) (/ stroke 2))
              (max 0 (- (box-width box) stroke))
              (max 0 (- (box-height box) stroke)))
             ((oget g "fillRect") (box-x box) (box-y box)
              (box-width box) (box-height box))))
        (t
         (rounded-path g box radius (if stroke (/ stroke 2) 0))
         (if stroke
             ((oget g "stroke"))
             ((oget g "fill"))))))

(fn (canvas-polygons t) (g paths color alpha)
  "Fill closed Canvas contours with a shared color and alpha."
  (setf (oget g "fillStyle") (jsstring color)
        (oget g "globalAlpha") alpha)
  ((oget g "beginPath"))
  (dotimes (index (length paths))
    (let ((path (aref paths index)))
      (when (plusp (length path))
        ((oget g "moveTo") (car (aref path 0)) (cdr (aref path 0)))
        (dotimes (i (1- (length path)))
          (let ((p (aref path (1+ i))))
            ((oget g "lineTo") (car p) (cdr p))))
        ((oget g "closePath")))))
  ((oget g "fill")))

(fn (canvas-text t) (g font text x y color)
  "Paint text with the resolved browser font and baseline."
  (setf (oget g "globalAlpha") 1
        (oget g "font")
        (jsstring (lui.font:font-css font))
        (oget g "fillStyle") (jsstring color))
  ((oget g "fillText") (jsstring text) x y))

(fn (canvas-stipple t) (g tile ink patterns box border color)
  "Reuse a colored checkerboard pattern to fill a rectangle or border."
  (let ((pattern (gethash color patterns)))
    (unless pattern
      ((oget ink "clearRect") 0 0 2 2)
      (setf (oget ink "fillStyle") (jsstring color))
      ((oget ink "fillRect") 0 0 1 1)
      ((oget ink "fillRect") 1 1 1 1)
      (setf pattern ((oget g "createPattern") tile #j"repeat")
            (gethash color patterns) pattern))
    (setf (oget g "globalAlpha") 1
          (oget g "fillStyle") pattern))
  (rounded-path g box 0)
  (when (and border (> (box-width box) (* 2 border))
             (> (box-height box) (* 2 border)))
    ((oget g "rect") (+ (box-x box) border)
     (+ (box-y box) border) (- (box-width box) (* 2 border))
     (- (box-height box) (* 2 border))))
  ((oget g "fill") #j"evenodd"))

(fn (canvas-glass t) (canvas g sample blur box radius frost)
  "Sample the visible backdrop into a reduced scratch canvas and paint it through a rounded clip."
  (when (plusp frost)
    (let* ((scale #j:window:devicePixelRatio)
           (offset (oget canvas "luiViewportOffset"))
           (x (max 0 (box-x box))) (y (max offset (box-y box)))
           (w (max 0 (- (min (box-right box)
                             (/ (oget canvas "width") scale)) x)))
           (h (max 0 (- (min (box-bottom box)
                             (+ offset (/ (oget canvas "height")
                                          scale)))
                        y)))
           (step (max 1 (/ frost 2))) (sw (max 1 (ceiling (/ w step))))
           (sh (max 1 (ceiling (/ h step)))))
      ;; Restrict the scratch bitmap to the visible artwork. The original
      ;; rounded surface still supplies the destination clip.
      (when (and (plusp w) (plusp h))
        (when (> sw (oget sample "width"))
          (setf (oget sample "width") sw))
        (when (> sh (oget sample "height"))
          (setf (oget sample "height") sh))
        ((oget blur "clearRect") 0 0 sw sh)
        ((oget blur "drawImage") canvas
         (* scale x) (* scale (- y offset)) (* scale w) (* scale h) 0 0 sw sh)
        ((oget g "save"))
        (rounded-path g box radius)
        ((oget g "clip"))
        (setf (oget g "globalAlpha") 1)
        ((oget g "drawImage") sample 0 0 sw sh x y w h)
        ((oget g "restore"))))))

(fn (canvas-renderer renderer) (canvas g)
  "Create Canvas drawing callbacks with reusable stipple and backdrop scratch surfaces."
  (let* ((tile (#j:document:createElement #j"canvas"))
         (ink ((oget tile "getContext") #j"2d"))
         (sample (#j:document:createElement #j"canvas"))
         (blur ((oget sample "getContext") #j"2d")))
    (setf (oget tile "width") 2 (oget tile "height") 2)
    (let ((patterns (make-hash-table :test 'equal)))
      (make-renderer
       :font (lui.font:open-font)
       :surface
       (lambda (box radius color alpha &optional stroke)
         (canvas-surface g box radius color alpha stroke))
       :polygons
       (lambda (paths color alpha)
         (canvas-polygons g paths color alpha))
       :text
       (lambda (font text x y color)
         (canvas-text g font text x y color))
       :clip
       (lambda (box)
         ((oget g "restore"))
         ((oget g "save"))
         (rounded-path g box 0)
         ((oget g "clip")))
       :stipple
       (lambda (box border color)
         (canvas-stipple g tile ink patterns box border color))
       :glass
       (lambda (box radius frost)
         (canvas-glass canvas g sample blur box radius frost))))))

(fn (queue-event t) ((app web-app) (event event))
  "Queue an application input event and request a redraw."
  (when (web-app-alive-p app)
    (if (and (eq (event-kind event) :move)
             (web-app-events app)
             (eq (event-kind (first (web-app-events app))) :move))
        (setf (first (web-app-events app)) event)
        (push event (web-app-events app)))
    (refresh app)))

(fn (cancel-deadline (values)) ((app web-app))
  "Cancel APP's pending frame deadline and clear its timer handle."
  (when (web-app-deadline-timer app)
    (#j:clearTimeout (web-app-deadline-timer app))
    (setf (web-app-deadline-timer app) nil))
  (values))

(fn (schedule-deadline t) ((app web-app))
  "Schedule a redraw for the context's next animation or idle deadline."
  (unless (web-app-pending-p app)
    (cancel-deadline app)
    (let ((delay (lui.frame::frame-wait (web-app-context app))))
      (if (zerop delay)
          (refresh app)
          (setf (web-app-deadline-timer app)
                (#j:setTimeout (lambda () (refresh app))
                               (ceiling (* delay 1000))))))))

(defstruct dom-widget key element text style state geometry hidden-p)

(defparameter *overlay-cache-limit* 32)

(defstruct overlay-region x y right bottom candidate visible)

(defstruct overlay-scan
  "Occlusion index and reusable geometry accumulated during one overlay walk."
  (previous nil :type list) (seen nil :type list)
  (bands nil :type (or null hash-table))
  (entries (make-array 0 :element-type 'list :adjustable t :fill-pointer 0)
           :type (vector list)))

(fn (index-overlay-region t) ((scan overlay-scan) region)
  "Index a painted region by vertical bands for occlusion queries."
  (do ((band (floor (overlay-region-y region) 64) (1+ band))
       (end (ceiling (overlay-region-bottom region) 64)))
      ((>= band end))
    (push region (gethash band (overlay-scan-bands scan)))))

(fn (overlay-uncovered-p t) ((scan overlay-scan) x y right bottom)
  "Test whether a rectangle is unobstructed by earlier painted regions."
  (do ((band (floor y 64) (1+ band)) (end (ceiling bottom 64)))
      ((>= band end) t)
    (dolist (other (gethash band (overlay-scan-bands scan)))
      (when (and (< x (overlay-region-right other)) (< (overlay-region-x
                                                        other) right)
                 (< y (overlay-region-bottom other)) (< (overlay-region-y
                                                         other) bottom))
        (return-from overlay-uncovered-p nil)))))

(fn (overlay-region-visible-p t) ((scan overlay-scan) clip candidate)
  "Reuse unchanged visibility or update the scan's occlusion index."
  (let* ((x (box-x clip)) (y (box-y clip))
         (right (+ x (box-width clip))) (bottom (+ y (box-height clip)))
         (old (pop (overlay-scan-previous scan))))
    (cond ((and old (= x (overlay-region-x old))
                (= y (overlay-region-y old))
                (= right (overlay-region-right old))
                (= bottom (overlay-region-bottom old))
                (eq candidate (overlay-region-candidate old)))
           (push old (overlay-scan-seen scan))
           (overlay-region-visible old))
          (t
           (unless (overlay-scan-bands scan)
             (setf (overlay-scan-previous scan) nil (overlay-scan-bands scan)
                   (make-hash-table))
             (dolist (region (overlay-scan-seen scan)) (index-overlay-region
                                                        scan region)))
           (let* ((visible
                   (and candidate
                        (overlay-uncovered-p scan x y right bottom)))
                  (region
                   (make-overlay-region
                    :x x :y y :right right :bottom bottom
                    :candidate candidate :visible visible)))
             (push region (overlay-scan-seen scan))
             (index-overlay-region scan region)
             visible)))))

(fn (visit-overlay-node t) ((scan overlay-scan) node path interactive)
  "Walk children front to back and collect unoccluded native-label candidates."
  (let ((key (if (element-id node)
                 (list :id (element-id node)) path))
        (children (element-children node))
        (clip (element-clip node))
        (widget (element-content node)))
    (let ((count (length children)))
      (dotimes (offset count)
        (let ((i (- count offset 1)))
          (visit-overlay-node scan (aref children i) (cons i key)
                              (or interactive
                                  (element-interactive-p node))))))
    (when (and (plusp (box-width clip)) (plusp (box-height clip))
               (or (lui.widgets:widget-p widget)
                   (element-interactive-p node)))
      (let ((kind (and (lui.widgets:widget-p widget)
                       (lui.widgets:widget-kind widget))))
        (when (overlay-region-visible-p scan
                                        clip
                                        (and (member kind '(:cell :label
                                                            :button :tab
                                                            :list-item
                                                            :checkbox :radio))
                                             (or (not (eq kind :label))
                                                 (lui:toolkit-native-labels-p
                                                  (lui.widgets:widget-style
                                                   widget)))
                                             (not (lui.widgets:widget-painter
                                                   widget))))
          (vector-push-extend
           (list node (cons kind key) interactive) (overlay-scan-entries
                                                    scan)))))))

(fn (overlay-candidates (vector list)) ((app web-app) (root element))
  "Collect unoccluded native-label candidates, reusing unchanged occlusion results."
  ;; Earlier regions paint in front; an unchanged prefix retains its occlusion.
  (let ((scan (make-overlay-scan :previous (web-app-overlay-geometry app))))
    (visit-overlay-node scan root nil nil)
    (setf (web-app-overlay-geometry app) (nreverse (overlay-scan-seen scan)))
    (reverse (overlay-scan-entries scan))))

(fn (css-pixels t) ((n real))
  "Convert a numeric dimension to a JavaScript CSS pixel string."
  ((oget (#j:String n) "concat") #j"px"))

(fn (position-dom-widget (values)) ((record dom-widget) (box box) (clip box))
  "Update an overlay's position and clipping only when its geometry changes."
  (let* ((x (box-x box)) (y (box-y box)) (w (box-width box)) (h (box-height
                                                                 box))
         (left (- (box-x clip) x)) (top (- (box-y clip) y))
         (right (- w left (box-width clip))) (bottom (- h top (box-height
                                                               clip)))
         (old (dom-widget-geometry record)))
    (destructuring-bind (&optional ox oy ow oh otop oright obottom oleft) old
      (unless (and (eql x ox) (eql y oy) (eql w ow) (eql h oh)
                   (eql top otop) (eql right oright) (eql bottom obottom)
                   (eql left oleft))
        (let ((style (oget (dom-widget-element record) "style")))
          (unless (eql x ox) (setf (oget style "left") (css-pixels
                                                        x)))
          (unless (eql y oy) (setf (oget style "top") (css-pixels
                                                       y)))
          (unless (eql w ow) (setf (oget style "width") (css-pixels
                                                         w)))
          (unless (eql h oh) (setf (oget style "height") (css-pixels
                                                          h)))
          (unless (and (eql top otop) (eql right oright) (eql bottom obottom)
                       (eql left oleft))
            (setf (oget style "clipPath")
                  (if (= 0 top right bottom left) #j"none"
                      ((oget #j"inset(" "concat")
                       top #j"px " right #j"px " bottom #j"px " left
                       #j"px)"))))
          (setf (dom-widget-geometry record) (list x y w h top right bottom
                                                   left))))))
  (values))

(fn (make-semantic-button t) ((app web-app) (node element) (kind symbol))
  "Create an accessible native control that queues LUI activation for NODE."
  ;; The canvas keeps pointer capture and toolkit keyboard navigation. Native
  ;; button activation also lets assistive technology invoke the same action.
  (let ((button (#j:document:createElement #j"button")) (id (element-id
                                                             node)))
    (setf (oget button "type") #j"button"
          (oget button "tabIndex") -1
          (oget button "onclick")
          (lambda (event)
            (declare (ignore event))
            (queue-event app (make-event :kind :activate :id id))))
    (when (member kind '(:checkbox :radio))
      ((oget button "setAttribute") #j"role"
       (jsstring (string-downcase (symbol-name kind)))))
    button))

(fn (same-overlay-order-p boolean) ((records (vector dom-widget)) (entries
                                                                   (vector
                                                                    list)))
  "Test whether overlay records already match the candidate keys in order."
  (and (= (length records) (length entries))
       (loop :for record :across records :for entry :across entries
             :always (equal (dom-widget-key record) (second entry)))))

(fn (order-overlay-elements (values))
    (layer (order (vector dom-widget)))
  "Move visible native elements into layout order while leaving cached hidden nodes in place."
  (let ((cursor (oget layer "firstChild")))
    (loop :for record :across order :do
          (let ((element (dom-widget-element record)))
            (loop :while (and (not (eq cursor #j:null))
                              (equal (oget cursor "style" "visibility") #j"hidden"))
                  :do (setf cursor (oget cursor "nextSibling")))
            (unless (eq element cursor) ((oget layer "insertBefore")
                                         element cursor))
            (setf cursor (oget element "nextSibling")))))
  (values))

(fn (reconcile-overlay (vector dom-widget)) ((app web-app) (entries (vector
                                                                     list)))
  "Reuse keyed DOM records, reconcile their order, and bound the hidden-node cache."
  ;; Look up keyed nodes and inspect DOM order only when membership or order changes.
  (let ((order (web-app-overlay-order app)))
    (when (same-overlay-order-p order entries)
      (return-from reconcile-overlay order))
    (let ((old (make-hash-table :test 'equal)) (layer (web-app-overlay app))
          (next (make-array 0 :element-type 'dom-widget :adjustable t
                            :fill-pointer 0))
          (cache (web-app-overlay-cache app)) hidden)
      (loop :for record :across order
            :do (setf (gethash (dom-widget-key record) old) record))
      (dolist (record cache) (setf (gethash (dom-widget-key record) old)
                                   record))
      (loop :for entry :across entries :do
            (destructuring-bind (node key interactive) entry
              (declare (ignore interactive))
              (let* ((kind (car key))
                     (record
                      (or (gethash key old)
                          (make-dom-widget :key key :element
                                           (if (eq kind :label)
                                               (#j:document:createElement #j"span")
                                               (make-semantic-button
                                                app node kind))))))
                (remhash key old)
                (when (dom-widget-hidden-p record)
                  (setf (dom-widget-hidden-p record) nil
                        (oget (dom-widget-element record) "style"
                              "visibility") #j"visible"))
                (vector-push-extend record next))))
      ;; Prefer newly hidden nodes over older cached entries when evicting.
      (loop :for record :across order :do
            (when (gethash (dom-widget-key record) old)
              (setf (dom-widget-hidden-p record) t
                    (oget (dom-widget-element record) "style" "visibility")
                    #j"hidden")
              (push record hidden)))
      (setf hidden
            (nconc hidden
                   (loop :for record :in cache
                         :when (gethash (dom-widget-key record) old)
                         :collect record)))
      (loop :for record :in (nthcdr *overlay-cache-limit* hidden)
            :do ((oget (dom-widget-element record) "remove")))
      (when (nthcdr *overlay-cache-limit* hidden)
        (setf (cdr (nthcdr (1- *overlay-cache-limit*) hidden)) nil))
      (setf (web-app-overlay-cache app) hidden)
      (setf order next)
      (order-overlay-elements layer order)
      (setf (web-app-overlay-order app) order))))

(fn (sync-semantic-state (values))
    ((record dom-widget) (widget lui.widgets:widget) element (kind symbol))
  "Update native disabled and checked/pressed attributes only when widget state changes."
  (let ((state (list (not (null (lui.widgets:widget-value widget)))
                     (lui.widgets:widget-disabled-p widget))))
    (unless (equal state (dom-widget-state record))
      (setf (dom-widget-state record) state
            (oget element "disabled") (if (second state) #j:true
                                          #j:false))
      (when (member kind '(:checkbox :radio :tab))
        ((oget element "setAttribute")
         (if (eq kind :tab) #j"aria-pressed" #j"aria-checked")
         (if (first state) #j"true" #j"false")))))
  (values))

(fn (sync-label-style (values))
    ((app web-app) (record dom-widget) widget element appearance interactive
     label)
  "Update label font, color, alignment, and pointer policy only when appearance changes."
  (unless (equal appearance (dom-widget-style record))
    (let ((font (lui.draw::widget-font (web-app-renderer app)
                                       widget))
          (style (oget element "style")))
      (setf (oget style "pointerEvents") (if interactive
                                             #j"none" #j"auto")
            (oget style "font") (jsstring
                                 (lui.font:font-css font))
            (oget style "lineHeight") (css-pixels
                                       (lui.font:line-height font))
            (oget style "color") (jsstring
                                  (lui.widgets:widget-foreground
                                   widget))
            (oget style "textAlign")
            (if (and label (geometry-center-x (widget-geometry
                                               widget))) #j"center" #j"left")
            (dom-widget-style record) appearance)))
  (values))

(fn (sync-overlay hash-table) ((app web-app))
  "Update native labels and accessible controls; return the nodes painted by the DOM."
  (let* ((entries (overlay-candidates app (context-root (web-app-context
                                                         app))))
         (records (reconcile-overlay app entries))
         (external (make-hash-table :test 'eq)))
    (loop :for (node key interactive) :across entries
          :for record :across records :do
          (let* ((kind (car key)) (label (eq kind :label)) (widget
                                                            (element-content
                                                             node))
                 (element (dom-widget-element record))
                 (text (if label (lui.widgets:widget-text widget)
                           (or (lui.widgets:widget-accessible-name widget)
                               (lui.widgets:widget-text widget))))
                 (appearance (and label (list interactive
                                              (lui.widgets:widget-font-size
                                               widget)
                                              (lui.widgets:widget-font-family
                                               widget)
                                              (lui.widgets:widget-font-weight
                                               widget)
                                              (lui.widgets:widget-foreground
                                               widget)
                                              (geometry-center-x
                                               (widget-geometry widget))))))
            (unless (dom-widget-geometry record)
              (setf (oget element "style" "cssText")
                    (if label
                        #j"position:absolute;display:block;margin:0;padding:0;border:0;white-space:pre-wrap;overflow:hidden;user-select:text;-webkit-user-select:text;cursor:text"
                        #j"position:absolute;display:block;margin:0;padding:0;border:0;opacity:0;pointer-events:none;user-select:none")))
            (position-dom-widget record
                                 (if label (lui.draw::selection-area
                                            (web-app-renderer app) node)
                                     (element-box node)) (element-clip node))
            (sync-label-style app record widget element appearance
                              interactive label)
            (if label (setf (gethash node external) t)
                (sync-semantic-state record widget element kind))
            (unless (equal text (dom-widget-text record))
              (if label (setf (oget element "textContent")
                              (jsstring text))
                  ((oget element "setAttribute") #j"aria-label"
                   (jsstring text)))
              (setf (dom-widget-text record) text))))
    external))

(fn (queue-page-scroll t) ((app web-app) (delta real) &optional ((velocity
                                                                  real) 0))
  "Accumulate page scrolling and bounded momentum, then request a redraw."
  (incf (web-app-scroll-delta app) delta)
  (setf (web-app-velocity app) (max -4 (min 4 velocity))
        (web-app-scroll-time app) (#j:performance:now))
  (refresh app))

(fn (frame-scroll-delta real) ((app web-app))
  "Consume queued scrolling and advance exponentially decaying page momentum."
  (let ((delta (shiftf (web-app-scroll-delta app) 0))
        (speed (web-app-velocity app)))
    (unless (zerop speed)
      (let* ((now (#j:performance:now))
             (elapsed (min 50 (- now (web-app-scroll-time app))))
             (decay (exp (/ (- elapsed) 190))))
        (incf delta (* speed 190 (- 1 decay)))
        (setf (web-app-scroll-time app) now
              (web-app-velocity app)
              (if (< (* (abs speed) decay) 0.02f0) 0 (* speed decay)))))
    delta))

(fn (resize-canvas-bitmap (values))
    (canvas (width real) (height real) (scale real))
  "Resize the physical canvas bitmap only when its scaled dimensions change."
  (let ((w (round (* width scale))) (h (round (* height scale))))
    (unless (= w (oget canvas "width"))
      (setf (oget canvas "width") w))
    (unless (= h (oget canvas "height"))
      (setf (oget canvas "height") h)))
  (values))

(fn (draw-frame t) ((app web-app))
  "Solve and paint APP's next frame, updating viewport geometry and native overlays."
  (let* ((canvas (web-app-canvas app)) (g (web-app-graphics app))
         (context (web-app-context app)) (*unit* 8)
         (width (oget canvas "clientWidth"))
         (port (web-app-scrollport app))
         (stage (web-app-stage app))
         (origin (if port (page-offset stage port) 0))
         (delta (if port (frame-scroll-delta app) 0))
         (height (if port (page-viewport-height port)
                     (oget canvas "clientHeight")))
         (scale #j:window:devicePixelRatio)
         (events (nreverse (shiftf (web-app-events app) nil))))
    (resize-canvas-bitmap canvas width height scale)
    (setf (lui.frame::context-page-height-p context) (not (null port))
          (lui.frame::context-page-top context)
          (max 0 (min (- (context-height context) height) (+ origin delta))))
    (with-frame (context width height :events events)
      (funcall (web-app-callback app)))
    (when port
      (let ((page-height (context-height context))
            (requested (shiftf (lui.frame::context-requested-page-top context)
                               nil)))
        (when requested (setf delta (- requested origin)))
        (let ((offset (max 0 (min (- page-height height) (+ origin delta)))))
          (setf (web-app-viewport-offset app) offset
                (oget canvas "luiViewportOffset") offset
                (oget stage "style" "height") (css-pixels
                                               page-height)
                (oget canvas "style" "height") (css-pixels
                                                height)))))
    ((oget g "setTransform") scale 0 0 scale 0 0)
    (setf (oget g "fillStyle") #j"#202432")
    ((oget g "fillRect") 0 0 width height)
    ((oget g "translate") 0 (- (web-app-viewport-offset app)))
    ((oget g "save"))
    (unwind-protect
         (paint-frame (web-app-renderer app) context (sync-overlay app)
                      (when port
                        (make-box :x 0 :y (web-app-viewport-offset app)
                                  :width width :height height)))
      ((oget g "restore")))
    ;; Commit the matching scroll position only after the pixels and DOM are ready.
    (when (and port (not (zerop delta)))
      (page-scroll-by port delta)
      (when (< (abs (- (page-offset stage port) origin)) 0.01f0)
        (setf (web-app-velocity app) 0)))
    (unless (zerop (web-app-velocity app)) (refresh app))
    (when (some (lambda (e) (not (eq :move (event-kind e)))) events)
      (refresh app))
    (lui.web.input:update-accessibility canvas context)
    (schedule-deadline app)))

(fn (refresh t) ((app web-app))
  "Request one redraw of a mounted application, coalescing pending requests."
  #+lui-ecl-web
  (let ((lui.web.ffi:*owner* (web-app-ffi-owner app)))
    (schedule-refresh app))
  #-lui-ecl-web (schedule-refresh app))

(fn (schedule-refresh t) ((app web-app))
  "Arrange an animation callback while honoring the application's frame pacing."
  (when (and (web-app-alive-p app) (not (web-app-pending-p app)))
    (cancel-deadline app)
    (setf (web-app-pending-p app) t)
    (flet ((enqueue ()
             (setf (web-app-deadline-timer app) nil
                   (web-app-animation-frame app)
                   (#j:requestAnimationFrame
                    (lambda (time)
                      (declare (ignore time))
                      (setf (web-app-pending-p app) nil
                            (web-app-animation-frame app) nil)
                      (when (web-app-alive-p app)
                        (draw-frame app)))))))
      (let* ((context (web-app-context app))
             (wait (if (context-root context)
                       (lui.frame::frame-wait context t) 0)))
        (if (zerop wait)
            (enqueue)
            (setf (web-app-deadline-timer app)
                  (#j:setTimeout #'enqueue (ceiling (* wait 1000)))))))))

(fn (default-scroll-mode symbol) ()
  "Choose page scrolling for touch-first devices and a bounded viewport otherwise."
  (if (clbool
       (oget (#j:window:matchMedia #j"(pointer: coarse)") "matches"))
      :page :viewport))

(fn (mount-app-elements (values))
    ((app web-app) page-scroll-p)
  "Style and attach the application's stage, canvas, and native-label layer."
  (let ((host (web-app-host app)) (stage (web-app-stage app))
        (canvas (web-app-canvas app)) (labels (web-app-overlay app))
        (port (web-app-scrollport app)))
    (setf (oget canvas "style" "cssText")
          #j"display:block;width:100%;height:100%;touch-action:none"
          (oget canvas "luiApp") app
          (oget canvas "luiViewportOffset") 0)
    (setf (oget stage "style" "cssText")
          #j"position:relative;width:100%;height:100%;overflow:hidden;-webkit-tap-highlight-color:transparent"
          (oget labels "style" "cssText")
          #j"position:absolute;inset:0;pointer-events:none")
    (when page-scroll-p
      (setf (oget stage "style" "touchAction") #j"pinch-zoom"
            (oget stage "style" "overflow") #j"clip"
            (oget canvas "style" "position") #j"sticky"
            (oget canvas "style" "top") #j"0"
            (oget canvas "style" "height") (css-pixels
                                            (page-viewport-height
                                             port))
            (oget stage "style" "height") (css-pixels
                                           (page-viewport-height
                                            port))))
    ((oget stage "appendChild") canvas)
    ((oget stage "appendChild") labels)
    ((oget host "appendChild") stage))
  (values))

(fn (mount web-app) (host (callback function) &key (min-fps
                                                    lui.frame::*min-fps*)
                                                (max-fps lui.frame::*max-fps*)
                                                ((scroll-mode
                                                  (member :page
                                                          :viewport))
                                                 (default-scroll-mode)))
  "Mount a Canvas 2D app in HOST. SCROLL-MODE is :PAGE for content expansion or
:VIEWPORT for a fixed embedded view; the default is :PAGE on coarse pointers."
  (assert (< 0 min-fps)) (assert (<= min-fps max-fps))
  (let* (#+lui-ecl-web (lui.web.ffi:*owner* (list :web-app))
                       (page-scroll-p (eq scroll-mode :page))
                       (port (and page-scroll-p (page-scrollport host)))
                       (stage (#j:document:createElement #j"div"))
                       (labels (#j:document:createElement #j"div"))
                       (canvas (#j:document:createElement #j"canvas"))
                       (g ((oget canvas "getContext") #j"2d"))
                       (renderer (canvas-renderer canvas g))
                       (context
                        (make-render-context renderer
                                             :min-fps min-fps :max-fps
                                             max-fps))
                       (app (make-web-app
                             #+lui-ecl-web :ffi-owner
                             #+lui-ecl-web lui.web.ffi:*owner*
                             :host host :stage stage :overlay labels
                             :canvas canvas :graphics g :renderer renderer
                             :context context :callback callback :scrollport
                             port))
                       (resize (lambda (&rest ignored)
                                 (declare (ignore ignored)) (refresh app))))
    (mount-app-elements app page-scroll-p)
    (setf (web-app-cleanup app)
          (lui.web.input:install-input
           stage canvas context (lambda (event) (queue-event app event))
           :page-scroll-p page-scroll-p
           :scroll-page (lambda (delta &optional (speed 0))
                          (queue-page-scroll app delta speed)))
          (web-app-resize app) resize
          (web-app-observer app) (new #j:ResizeObserver resize))
    ((oget (web-app-observer app) "observe") host)
    (when (and port (not (eq port #j:window)) (not (eq port host)))
      ((oget (web-app-observer app) "observe") port))
    (#j:window:addEventListener #j"resize" resize)
    (when port
      (setf (web-app-scroll-listener app)
            (lambda (&rest ignored)
              (declare (ignore ignored))
              ;; A committed, prepainted scroll needs no second frame. Native
              ;; scrolling and clamping to a different offset still repaint.
              (unless (< (abs (- (page-offset stage port)
                                 (web-app-viewport-offset app))) 0.01f0)
                (refresh app))))
      ((oget port "addEventListener") #j"scroll"
       (web-app-scroll-listener app)))
    (refresh app)
    app))

(fn (unmount t) ((app web-app))
  "Cancel scheduled work and release the mounted canvas and input listeners."
  #+lui-ecl-web
  (let ((lui.web.ffi:*owner* (web-app-ffi-owner app)))
    (dispose-app app))
  #-lui-ecl-web (dispose-app app))

(fn (dispose-app t) ((app web-app))
  "Release APP's listeners, timers, rendering resources, and mounted DOM elements."
  (when (web-app-alive-p app)
    (setf (web-app-alive-p app) nil)
    (cancel-deadline app)
    (when (web-app-animation-frame app)
      (#j:cancelAnimationFrame (web-app-animation-frame app)))
    ((oget (web-app-observer app) "disconnect"))
    (#j:window:removeEventListener #j"resize" (web-app-resize app))
    (when (web-app-scrollport app)
      ((oget (web-app-scrollport app) "removeEventListener")
       #j"scroll" (web-app-scroll-listener app)))
    (funcall (web-app-cleanup app))
    (lui.font:close-font (renderer-font (web-app-renderer app)))
    (setf (web-app-overlay-order app) #()
          (web-app-overlay-cache app) nil
          (web-app-overlay-geometry app) nil)
    ((oget (web-app-stage app) "remove"))
    #+lui-ecl-web
    (progn
      (setf (oget (web-app-canvas app) "luiApp") #j:null)
      (lui.web.ffi:release-owner (web-app-ffi-owner app)))))

(fn (css-size t) (value fallback)
  "Convert a numeric CSS size to pixels, preserving strings and using FALLBACK for NIL."
  (if value ((oget (#j:String value) "concat") #j"px") fallback))

(fn (run-web web-app) ((draw function) &key title width height (interactive
                                                                t))
  "Create a browser host and mount DRAW with the requested title and dimensions."
  (declare (ignore interactive))
  (setf (oget #j:document "title") (jsstring title))
  (let ((scroll-mode (if height :viewport (default-scroll-mode)))
        (host (#j:document:createElement #j"main")))
    ((oget host "setAttribute") #j"aria-label"
     (jsstring title))
    (setf (oget host "style" "width")
          (css-size width #j"100%")
          (oget host "style" "height")
          (css-size height (if (eq scroll-mode :page) #j"auto" #j"100vh")))
    (#j:document:body:appendChild host)
    (mount host draw :scroll-mode scroll-mode)))

(register-backend #+lui-ecl-web :web-ecl #-lui-ecl-web :web #'run-web)
