(defpackage #:lui.web
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui)
  (:export #:mount #:unmount #:refresh))

(in-package #:lui.web)

(defstruct* web-app
  host
  measure-node
  style-node
  (tab-focus-p nil :type boolean)
  (order-dirty-p t :type boolean)
  callback
  context
  (nodes (make-hash-table :test 'equal) :type hash-table)
  (tablists (make-hash-table :test 'equal) :type hash-table)
  (measurements (make-hash-table :test 'equal) :type hash-table)
  hover-id
  (events nil :type list)
  (pending-p nil :type boolean)
  (alive-p t :type boolean)
  resize-handler
  resize-observer
  animation-frame
  deadline-timer
  wheel-handler
  (listeners nil :type list))

(fn create-node ((tag string))
  (#j:document:createElement (jscl/ffi:jsstring tag)))

(fn create-svg-node ((tag string))
  (#j:document:createElementNS #j"http://www.w3.org/2000/svg"
                              (jscl/ffi:jsstring tag)))

(fn queue-pointer ((app web-app) event kind)
  (let ((rect ((jscl/ffi:oget (web-app-host app)
                             "getBoundingClientRect"))))
    (queue-event
     app (make-event :kind kind
                     :button (if (= 2 (jscl/ffi:oget event "button"))
                                 :secondary :primary)
                     :clicks (max 1 (jscl/ffi:oget event "detail"))
                     :x (- (jscl/ffi:oget event "clientX")
                           (jscl/ffi:oget rect "left"))
                     :y (- (jscl/ffi:oget event "clientY")
                           (jscl/ffi:oget rect "top"))))))

(fn node-cache (node (name string))
  (let ((cache (jscl/ffi:oget node name)))
    (if (eq cache #j:undefined)
        (setf (jscl/ffi:oget node name) (jscl/ffi:new #j:Object))
        cache)))

(fn style (node (name string) (value string))
  (let ((cache (node-cache node "luiStyles"))
        (native (jscl/ffi:jsstring value)))
    (unless (eq native (jscl/ffi:oget cache name))
      ((jscl/ffi:oget node "style" "setProperty")
       (jscl/ffi:jsstring name) native)
      (setf (jscl/ffi:oget cache name) native))))

(fn px ((value real))
  (jscl/ffi:clstring
   ((jscl/ffi:oget (#j:String value) "concat") #j"px")))

(fn attribute (node (name string) (value string))
  (let ((cache (node-cache node "luiAttributes"))
        (native (jscl/ffi:jsstring value)))
    (unless (eq native (jscl/ffi:oget cache name))
      ((jscl/ffi:oget node "setAttribute") (jscl/ffi:jsstring name) native)
      (setf (jscl/ffi:oget cache name) native))))

(fn property (node (name string) value)
  (unless (eq value (jscl/ffi:oget node name))
    (setf (jscl/ffi:oget node name) value)))

(fn node-text (node (text string))
  (property node "textContent" (jscl/ffi:jsstring text)))

(fn listen ((app web-app) node (name string) (function function)
            &optional capture)
  (let ((options (jscl/ffi:new #j:Object)))
    (setf (jscl/ffi:oget options "capture") (jscl/ffi:jsbool capture)
          (jscl/ffi:oget options "passive") #j:false)
    ((jscl/ffi:oget node "addEventListener")
     (jscl/ffi:jsstring name) function options))
  (push (list node name function capture) (web-app-listeners app)))

(fn remove-node ((app web-app) node)
  (setf (web-app-listeners app)
        (delete-if
         (lambda (listener)
           (destructuring-bind (target name function capture) listener
             (when (or (eq target node)
                       (jscl/ffi:clbool
                        ((jscl/ffi:oget node "contains") target)))
               ((jscl/ffi:oget target "removeEventListener")
                (jscl/ffi:jsstring name) function (jscl/ffi:jsbool capture))
               t)))
         (web-app-listeners app)))
  ((jscl/ffi:oget node "remove")))

(fn queue-event ((app web-app) (event event))
  (when (web-app-alive-p app)
    (if (and (eq (event-kind event) :move)
             (web-app-events app)
             (eq (event-kind (first (web-app-events app))) :move))
        (setf (first (web-app-events app)) event)
        (push event (web-app-events app)))
    (refresh app)))

(fn control-change ((app web-app) control kind id)
  ;; A rejected native edit must still restore the unchanged model value.
  (setf (jscl/ffi:oget
         (if (eq kind :checkbox)
             (jscl/ffi:oget control "parentNode") control)
         "luiSignature")
        #j:undefined)
  (queue-event
   app
   (make-event :kind :change :id id :value
               (case kind
                 (:checkbox
                  (jscl/ffi:clbool (jscl/ffi:oget control "checked")))
                 (:slider (jscl/ffi:oget control "valueAsNumber"))
                 (otherwise
                  (jscl/ffi:clstring (jscl/ffi:oget control "value")))))))

(fn reset-native-edit (control)
  (edit-text (jscl/ffi:clstring (jscl/ffi:oget control "value"))
             (jscl/ffi:oget control "luiEditState")
             (list (make-event :kind :move))))

(fn dom-text-index ((text string) (index integer))
  (jscl/ffi:oget (jscl/ffi:jsstring (subseq text 0 index)) "length"))

(fn native-application-key ((app web-app) id event)
  (unless (or (jscl/ffi:clbool (jscl/ffi:oget event "isComposing"))
              (jscl/ffi:clbool (jscl/ffi:oget event "ctrlKey"))
              (jscl/ffi:clbool (jscl/ffi:oget event "metaKey"))
              (jscl/ffi:clbool (jscl/ffi:oget event "altKey")))
    (let ((key (jscl/ffi:clstring (jscl/ffi:oget event "key"))))
      (when (member key '("Enter" "Escape") :test #'string=)
        ((jscl/ffi:oget event "preventDefault"))
        (queue-event app (if (string= key "Enter")
                             (make-event :kind :activate :id id)
                             (make-event :kind :key :key :escape :id id)))
        t))))

(fn native-text-key ((app web-app) control id event)
  (unless (or (jscl/ffi:clbool (jscl/ffi:oget event "isComposing"))
              (eql 229 (jscl/ffi:oget event "keyCode"))
              (jscl/ffi:clbool (jscl/ffi:oget control "luiComposing"))
              (jscl/ffi:clbool (jscl/ffi:oget event "metaKey"))
              (and (jscl/ffi:clbool (jscl/ffi:oget event "ctrlKey"))
                   (jscl/ffi:clbool (jscl/ffi:oget event "altKey"))))
    (when (native-application-key app id event)
      (return-from native-text-key nil))
    (let* ((key (jscl/ffi:clstring (jscl/ffi:oget
                                    event "key")))
           (command (readline-key key
                                  :control (jscl/ffi:clbool
                                            (jscl/ffi:oget event "ctrlKey"))
                                  :alt (jscl/ffi:clbool
                                        (jscl/ffi:oget event "altKey"))
                                  :shift (jscl/ffi:clbool
                                          (jscl/ffi:oget event "shiftKey")))))
      ;; Native input copy uses the browser clipboard and DOM selection.
      (when (eq command :copy) (setf command nil))
      (if (null command)
          (unless (member key '("Control" "Alt" "Shift" "Meta" "CapsLock")
                          :test #'string=)
            (reset-native-edit control))
          (let* ((value (jscl/ffi:oget control "value"))
                 (text (jscl/ffi:clstring value))
                 (state (jscl/ffi:oget control "luiEditState"))
                 (start (length
                         (jscl/ffi:clstring
                          ((jscl/ffi:oget value "slice") 0
                           (jscl/ffi:oget control "selectionStart")))))
                 (end (length
                       (jscl/ffi:clstring
                        ((jscl/ffi:oget value "slice") 0
                         (jscl/ffi:oget control "selectionEnd")))))
                 (backward
                  (string= "backward"
                           (jscl/ffi:clstring
                            (jscl/ffi:oget control "selectionDirection")))))
            ((jscl/ffi:oget event "preventDefault"))
            (setf (edit-state-cursor state) (if backward start end)
                  (edit-state-anchor state) (if backward end start))
            (let* ((edited (edit-text text state
                                      (list (make-event :kind :key
                                                        :key command))))
                   (cursor (dom-text-index edited (edit-state-cursor state)))
                   (anchor (dom-text-index edited (edit-state-anchor state))))
              (unless (string= text edited)
                (setf (jscl/ffi:oget control "value")
                      (jscl/ffi:jsstring edited))
                (control-change app control :text-field id))
              ((jscl/ffi:oget control "setSelectionRange")
               (min cursor anchor) (max cursor anchor)
               (jscl/ffi:jsstring (if (< cursor anchor)
                                      "backward" "forward")))))))))

(fn native-tab-key ((app web-app) id event)
  (unless (or (jscl/ffi:clbool (jscl/ffi:oget event "ctrlKey"))
              (jscl/ffi:clbool (jscl/ffi:oget event "altKey"))
              (jscl/ffi:clbool (jscl/ffi:oget event "metaKey")))
    (let ((key (cdr (assoc
                     (jscl/ffi:clstring (jscl/ffi:oget event "key"))
                     '(("ArrowLeft" . :left) ("ArrowRight" . :right)
                       ("Home" . :home) ("End" . :end))
                     :test #'string=))))
      (when key
        ((jscl/ffi:oget event "preventDefault"))
        (setf (web-app-tab-focus-p app) t)
        (queue-event app (make-event :kind :key :key key :id id))))))

(fn css-font-family ((widget widget))
  (if (eq (widget-font-family widget) :monospace)
      "Liberation Mono,Courier New,DejaVu Sans Mono,monospace"
      "DejaVu Sans,Arial,sans-serif"))

(fn css-font-weight ((widget widget))
  (if (eq (widget-font-weight widget) :bold) "700" "400"))

(fn measure-uncached ((app web-app) (widget widget) width)
  (let* ((node (web-app-measure-node app))
         (kind (widget-kind widget))
         (text (if (eq kind :text-field)
                   (widget-value widget)
                   (widget-text widget)))
         (extra (case kind (:label 0) (:checkbox 48) (otherwise 24))))
    (setf (jscl/ffi:oget node "textContent") (jscl/ffi:jsstring text))
    (style node "font-size" (px (widget-font-size widget)))
    (style node "font-family" (css-font-family widget))
    (style node "font-weight" (css-font-weight widget))
    (style node "width"
           (if width (px (max 0 (- width extra))) "max-content"))
    (style node "white-space" (if (eq kind :label) "pre-wrap" "pre"))
    (let ((rect ((jscl/ffi:oget node "getBoundingClientRect"))))
      (values
       (max (case kind (:slider 160) (:text-field 160) (otherwise 0))
            (ceiling (+ extra (jscl/ffi:oget rect "width"))))
       (max (+ (if (eq kind :label) 0 12) (widget-font-size widget))
            (ceiling (+ (if (eq kind :label) 0 12)
                        (jscl/ffi:oget rect "height"))))))))

(fn measure-widget ((app web-app) (widget widget) width)
  (let* ((kind (widget-kind widget))
         (text (if (eq kind :text-field)
                   (widget-value widget) (widget-text widget)))
         (key (list kind (widget-font-size widget)
                    (widget-font-family widget) (widget-font-weight widget)
                    text width))
         (cached (gethash key (web-app-measurements app))))
    (unless cached
      (setf cached (multiple-value-list (measure-uncached app widget width))
            (gethash (list kind (widget-font-size widget)
                           (widget-font-family widget)
                           (widget-font-weight widget) (copy-seq text) width)
                     (web-app-measurements app)) cached))
    (values (first cached) (second cached))))

(fn native-option-key ((app web-app) id event)
  (unless (or (native-application-key app id event)
              (jscl/ffi:clbool (jscl/ffi:oget event "isComposing"))
              (jscl/ffi:clbool (jscl/ffi:oget event "ctrlKey"))
              (jscl/ffi:clbool (jscl/ffi:oget event "metaKey"))
              (jscl/ffi:clbool (jscl/ffi:oget event "altKey")))
    (let ((key (cdr (assoc
                     (jscl/ffi:clstring (jscl/ffi:oget event "key"))
                     '(("ArrowUp" . :up) ("ArrowDown" . :down)
                       ("ArrowLeft" . :left) ("ArrowRight" . :right)
                       ("Home" . :home) ("End" . :end))
                     :test #'string=))))
      (when key
        ((jscl/ffi:oget event "preventDefault"))
        (setf (web-app-tab-focus-p app) t)
        (queue-event app (make-event :kind :key :key key :id id))))))

(fn native-button-key ((app web-app) id event)
  (native-option-key app id event)
  (let ((key (jscl/ffi:clstring (jscl/ffi:oget event "key"))))
    (when (and (= (length key) 1) (not (string= key " "))
               (not (some (lambda (name)
                            (jscl/ffi:clbool (jscl/ffi:oget event name)))
                          '("isComposing" "ctrlKey" "metaKey" "altKey"))))
      ((jscl/ffi:oget event "preventDefault"))
      (queue-event app (make-event :kind :text :id id :value key)))))

(fn widget-node ((app web-app) (node element) key)
  (let* ((widget (element-content node))
         (kind (widget-kind widget))
         (entry (gethash key (web-app-nodes app))))
    (when (and entry (not (eq kind (car entry))))
      (remove-node app (cdr entry))
      (setf entry nil))
    (unless entry
      (let* ((dom (if (eq kind :canvas)
                      (create-svg-node "svg")
                      (create-node
                       (case kind
                         ((:button :tab :list-item :cell) "button")
                         ((:slider :text-field) "input")
                         (:checkbox "label")
                         (otherwise "div")))))
             (control (if (eq kind :checkbox) (create-node "input") dom))
             (id (element-id node)))
        (setf (jscl/ffi:oget dom "luiId") id)
        (when (eq kind :checkbox)
          ((jscl/ffi:oget dom "appendChild") control)
          ((jscl/ffi:oget dom "appendChild") (create-node "span")))
        (when (eq kind :canvas)
          (attribute dom "role" "img")
          (attribute dom "tabindex" "0")
          (style dom "touch-action" "none")
          (listen app dom "keydown"
                  (lambda (event) (native-application-key app id event)))
          (listen app dom "contextmenu"
                  (lambda (event)
                    ((jscl/ffi:oget event "preventDefault"))))
          (listen app dom "pointerdown"
                  (lambda (event)
                    ((jscl/ffi:oget event "preventDefault"))
                    ((jscl/ffi:oget dom "setPointerCapture")
                     (jscl/ffi:oget event "pointerId"))
                    (queue-pointer app event :press)))
          (dolist (name '("pointerup" "pointercancel"))
            (listen app dom name
                    (lambda (event)
                      (queue-pointer app event :release)
                      (let ((id (jscl/ffi:oget event "pointerId")))
                        (when (jscl/ffi:clbool
                               ((jscl/ffi:oget dom "hasPointerCapture") id))
                          ((jscl/ffi:oget dom "releasePointerCapture")
                           id)))))))
        (case kind
          ((:button :tab :list-item :cell)
           (attribute dom "type" "button")
           (attribute dom "class" "lui-control")
           (listen app dom "mousedown"
                   (lambda (event)
                     ;; Buttons keep editing focus; list options take focus.
                     (unless (eq kind :list-item)
                       ((jscl/ffi:oget event "preventDefault")))))
           (when (member kind '(:button :cell))
             (when (eq kind :cell)
               (attribute dom "role" "gridcell")
               (attribute dom "class" "lui-cell"))
             (listen app dom "keydown"
                     (lambda (event) (native-button-key app id event))))
           (when (eq kind :list-item)
             (attribute dom "role" "option")
             (attribute dom "class" "lui-control lui-option")
             (listen app dom "keydown"
                     (lambda (event) (native-option-key app id event))))
           (when (eq kind :tab)
             (attribute dom "role" "tab")
             (listen app dom "keydown"
                     (lambda (event) (native-tab-key app id event))))
           (listen app dom "click"
                   (lambda (event)
                     (if (plusp (jscl/ffi:oget event "detail"))
                         (progn (queue-pointer app event :press)
                                (queue-pointer app event :release))
                         (queue-event
                          app (make-event :kind :activate :id id))))))
          ((:slider :text-field :checkbox)
           (when (eq kind :slider)
             (listen app control "keydown"
                     (lambda (event)
                       (native-application-key app id event))))
           (when (eq kind :checkbox)
             (listen app control "keydown"
                     (lambda (event)
                       (when (and (string= "Enter" (jscl/ffi:clstring
                                                    (jscl/ffi:oget
                                                     event "key")))
                                  (not (jscl/ffi:clbool
                                        (jscl/ffi:oget event "isComposing"))))
                         ((jscl/ffi:oget event "preventDefault"))
                         ((jscl/ffi:oget control "click"))))))
           (attribute control "type"
                      (ecase kind
                        (:slider "range")
                        (:text-field "text")
                        (:checkbox "checkbox")))
           (listen app control "input"
                   (lambda (event)
                     ;; Composition remains in the DOM until it is committed.
                     (unless
                         (jscl/ffi:clbool
                          (jscl/ffi:oget event "isComposing"))
                       (when (eq kind :text-field)
                         (reset-native-edit control))
                       (control-change app control kind id))))
           (when (eq kind :text-field)
             (setf (jscl/ffi:oget control "luiEditState") (make-edit-state))
             (listen app control "keydown"
                     (lambda (event) (native-text-key app control id event)))
             (listen app control "pointerdown"
                     (lambda (event)
                       (declare (ignore event))
                       (reset-native-edit control)))
             (listen app control "compositionstart"
                     (lambda (event)
                       (declare (ignore event))
                       (setf (jscl/ffi:oget control "luiComposing")
                             #j:true)))
             (listen app control "compositionend"
                     (lambda (event)
                       (declare (ignore event))
                       (setf (jscl/ffi:oget control "luiComposing")
                             #j:false)
                       (reset-native-edit control)
                       (control-change app control kind id)))))
          (otherwise nil))
        (listen app control "focus"
                (lambda (event)
                  (declare (ignore event))
                  (setf (context-focus (web-app-context app)) id)))
        ((jscl/ffi:oget (web-app-host app) "appendChild") dom)
        (setf (web-app-order-dirty-p app) t)
        (setf entry (cons kind dom) (gethash key (web-app-nodes app))
              entry)))
    (cdr entry)))

(fn render-signature ((widget widget) (bounds box) (clip box))
  (jscl/ffi:new #j:Array (widget-kind widget) (widget-style widget)
                (jscl/ffi:jsstring (widget-text widget))
                (if (stringp (widget-value widget))
                    (jscl/ffi:jsstring (widget-value widget))
                    (widget-value widget))
                (widget-minimum widget) (widget-maximum widget)
                (widget-step widget)
                (widget-font-family widget) (widget-font-weight widget)
                (widget-font-size widget) (widget-radius widget)
                (widget-frost widget)
                (widget-opacity widget) (widget-disabled-p widget)
                (jscl/ffi:jsstring (widget-foreground widget))
                (jscl/ffi:jsstring (widget-background widget))
                (jscl/ffi:jsstring (widget-accent widget))
                (box-x bounds) (box-y bounds)
                (box-width bounds) (box-height bounds)
                (box-x clip) (box-y clip) (box-width clip) (box-height clip)))

(fn same-signature-p (signature previous)
  (when (and (not (eq previous #j:undefined))
             (eq (jscl/ffi:oget signature "length")
                 (jscl/ffi:oget previous "length")))
    (let ((same t))
      (dotimes (index (jscl/ffi:oget signature "length") same)
        (unless (eq (jscl/ffi:oget signature index)
                    (jscl/ffi:oget previous index))
          (setf same nil))))))

(fn update-node ((app web-app) (node element) key)
  (let* ((widget (element-content node))
         (dom (widget-node app node key))
         (kind (widget-kind widget))
         (control (if (eq kind :checkbox)
                      (jscl/ffi:oget dom "firstElementChild")
                      dom))
         (box (element-box node))
         (clip (element-clip node))
         (glass (eq (widget-style widget) :glass)))
    (style dom "display"
           (if (and (plusp (box-width clip)) (plusp (box-height clip)))
               (if (eq kind :checkbox) "flex" "block") "none"))
    (unless (and (plusp (box-width clip)) (plusp (box-height clip)))
      (return-from update-node dom))
    (let ((signature (render-signature widget box clip)))
      ;; Canvas command lists may be edited in place by the application.
      (when (and (not (eq kind :canvas))
                 (same-signature-p signature
                                   (jscl/ffi:oget dom "luiSignature")))
        (return-from update-node dom))
      (setf (jscl/ffi:oget dom "luiSignature") signature))
    (when (and (eq kind :panel) (= 1 (widget-opacity widget))
               (= 0 (box-x box) (box-y box))
               (= (box-width box) (context-width (web-app-context app)))
               (= (box-height box) (context-height (web-app-context app))))
      (style (web-app-host app) "background" (widget-background widget)))
    (attribute dom "data-lui-interactive"
               (if (element-interactive-p node) "true" "false"))
    (attribute dom "data-lui-style"
               (case (widget-style widget)
                 (:garnet "garnet") (:motif "motif") (otherwise "glass")))
    (style dom "position" "absolute")
    (style dom "box-sizing" "border-box")
    (style dom "margin" "0")
    (style dom "font-family" (css-font-family widget))
    (style dom "font-weight" (css-font-weight widget))
    (style dom "left" (px (box-x box)))
    (style dom "top" (px (box-y box)))
    (style dom "width" (px (box-width box)))
    (style dom "height" (px (box-height box)))
    (style dom "font-size" (px (widget-font-size widget)))
    (style dom "color"
           (if (widget-disabled-p widget)
               "#777777" (widget-foreground widget)))
    (let ((accent (if (widget-disabled-p widget)
                      "#999999" (widget-accent widget))))
      (style dom "accent-color" accent)
      (style dom "--lui-accent" accent))
    (style dom "white-space" "pre-wrap")
    (style dom "text-align" "left")
    (style dom "line-height" "normal")
    (when (member kind '(:button :tab :text-field :checkbox))
      (style dom "padding" (if glass "5px 11px" "4px 10px")))
    (style dom "clip-path"
           (format nil "inset(~A ~A ~A ~A)" (px (- (box-y clip) (box-y box)))
                   (px
                    (max 0
                         (- (+ (box-x box) (box-width box))
                            (+ (box-x clip) (box-width clip)))))
                   (px
                    (max 0
                         (- (+ (box-y box) (box-height box))
                            (+ (box-y clip) (box-height clip)))))
                   (px (- (box-x clip) (box-x box)))))
    (unless (member kind '(:text-field :slider :checkbox :canvas :gauge))
      (node-text dom (widget-text widget)))
    (unless (eq kind :label)
      (property control "disabled"
                (jscl/ffi:jsbool (widget-disabled-p widget)))
      (attribute control "aria-label"
                 (if (plusp (length (widget-text widget)))
                     (widget-text widget)
                     (if (eq kind :cell) "Empty cell"
                         (princ-to-string key))))
      (style dom "border-radius" (px (if glass (widget-radius widget) 0)))
      (style dom "border"
             (if glass
                 (if (widget-disabled-p widget)
                     "1px solid #ffffff26" "1px solid #ffffff66")
                 "2px outset #dddddd"))
      (style dom "background"
             (if glass
                 (format nil "color-mix(in srgb, ~A ~D%, transparent)"
                         (widget-background widget)
                         (round (* 100 (widget-opacity widget))))
                 (widget-background widget)))
      (style dom "backdrop-filter"
             (if (and glass (< (widget-opacity widget) 1))
                 (format nil "blur(~A) saturate(150%)"
                         (px (widget-frost widget))) "none"))
      (style dom "box-shadow"
             (if glass "inset 0 1px 1px #ffffff88, 0 3px 12px #00000044"
                 "none")))
    (case kind
      (:tab
       (attribute dom "aria-selected"
                  (if (widget-value widget) "true" "false"))
       (attribute dom "tabindex"
                  (if (and (widget-value widget)
                           (not (widget-disabled-p widget))) "0" "-1"))
       (when (widget-value widget)
         (style dom "box-shadow"
                (format nil "inset 0 -3px 0 ~A" (widget-accent widget)))))
      (:checkbox
       (style dom "display" "flex")
       (style dom "align-items" "center")
       (style dom "gap" "8px")
       (attribute dom "class"
                  (if glass "lui-check" "lui-check lui-motif-check"))
       (attribute control "class" "lui-control")
       (unless glass
         (style dom "padding" "6px 12px")
         (style dom "border" "none")
         (style dom "background" "transparent")
         (style dom "box-shadow" "none")
         (style dom "backdrop-filter" "none"))
       (style control "margin" "0")
       (style control "width" "16px")
       (style control "height" "16px")
       (style control "flex-shrink" "0")
       (setf (jscl/ffi:oget control "checked")
             (jscl/ffi:jsbool (widget-value widget))
             (jscl/ffi:oget dom "lastElementChild" "textContent")
             (jscl/ffi:jsstring (widget-text widget))))
      (:slider
       (attribute dom "class" "lui-range")
       (style dom "appearance" "none")
       (style dom "padding" "0 7px")
       (style dom "--lui-thumb-radius" (if glass "7px" "0"))
       (style dom "--lui-fill"
              (concatenate 'string
                           (jscl/ffi:clstring
                            (#j:String
                             (* 100 (/ (- (widget-value widget)
                                          (widget-minimum widget))
                                       (- (widget-maximum widget)
                                          (widget-minimum widget))))))
                           "%"))
       (attribute dom "min" (princ-to-string (widget-minimum widget)))
       (attribute dom "max" (princ-to-string (widget-maximum widget)))
       (attribute dom "step" (princ-to-string (widget-step widget)))
       (setf (jscl/ffi:oget dom "valueAsNumber") (widget-value widget)))
      (:text-field
       (style dom "appearance" "none")
       (unless
           (or (jscl/ffi:clbool (jscl/ffi:oget dom "luiComposing"))
               (string= (widget-value widget)
                        (jscl/ffi:clstring (jscl/ffi:oget dom "value"))))
         (setf (jscl/ffi:oget dom "value")
               (jscl/ffi:jsstring (widget-value widget)))))
      (otherwise nil))
    (case kind
      (:canvas (update-canvas dom widget))
      (:gauge
       (attribute dom "role" "progressbar")
       (attribute dom "aria-valuemin" "0")
       (attribute dom "aria-valuemax" "1")
       (attribute dom "aria-valuenow"
                  (jscl/ffi:clstring (#j:String (widget-value widget))))
       (when (eq #j:null (jscl/ffi:oget dom "firstElementChild"))
         ((jscl/ffi:oget dom "appendChild") (create-node "div")))
       (let ((fill (jscl/ffi:oget dom "firstElementChild")))
         (style fill "height" "100%")
         (style fill "width"
                (jscl/ffi:clstring
                 ((jscl/ffi:oget (#j:String (* 100 (widget-value widget)))
                                "concat") #j"%")))
         (style fill "background" (widget-accent widget))
         (style fill "border-radius" "inherit"))))
    (when (eq (widget-style widget) :garnet)
      (style dom "border-radius" "0")
      (style dom "backdrop-filter" "none")
      (unless (eq kind :label)
        (style dom "background" (widget-background widget))
        (style dom "border" "1px solid #000")
        (style dom "box-shadow" "none"))
      (when (member kind '(:button :tab :panel))
        (let ((window-p (and (eq kind :panel)
                             (= (box-width box)
                                (context-width (web-app-context app)))
                             (= (box-height box)
                                (context-height (web-app-context app))))))
          (style dom "border" (if window-p "none" "1px solid #000"))
          (style dom "background"
                 (if (or window-p (eq kind :panel))
                     (widget-background widget)
                     "linear-gradient(#fff,#fff) 4px 4px / calc(100% - 8px) calc(100% - 8px) no-repeat,repeating-conic-gradient(#000 0% 25%,#fff 0% 50%) 0 0 / 2px 2px"))
          (style dom "box-shadow"
                 (if window-p "none"
                     "inset 0 0 0 1px #000,4px 4px 0 #000"))
          (unless window-p
            (when (member kind '(:button :tab))
              (style dom "padding" "3px 9px")
              (style dom "text-align" "center"))
            (style dom "width" (px (max 0 (- (box-width box) 4))))
            (style dom "height" (px (max 0 (- (box-height box) 4))))
            (style dom "clip-path"
                   (format nil "inset(~A ~A ~A ~A)"
                           (px (- (box-y clip) (box-y box)))
                           (px (- (+ (box-x box) (box-width box))
                                  (+ (box-x clip) (box-width clip)) 4))
                           (px (- (+ (box-y box) (box-height box))
                                  (+ (box-y clip) (box-height clip)) 4))
                           (px (- (box-x clip) (box-x box))))))))
      (when (and (eq kind :tab) (widget-value widget))
        (style dom "background" "#000")
        (style dom "color" "#fff"))
      (when (eq kind :text-field)
        (style dom "padding" "5px"))
      (when (eq kind :checkbox)
        (attribute dom "class" "lui-check lui-garnet-check")
        (style dom "padding" "3px 4px 3px 12px")
        (style dom "gap" "12px")
        (style dom "border" "none")
        (style dom "background" "transparent")
        (style dom "flex-direction" "row-reverse")
        (style dom "justify-content" "flex-end")
        (style control "width" "20px")
        (style control "height" "20px")))
    (when (eq kind :list-item)
      (attribute dom "aria-selected"
                 (if (widget-value widget) "true" "false"))
      (style dom "padding" "5px 11px")
      (style dom "text-align" "left")
      (style dom "border" "none")
      (style dom "border-radius" "0")
      (style dom "box-shadow" "none")
      (style dom "backdrop-filter" "none")
      (style dom "background"
             (if (widget-value widget) (widget-accent widget) "transparent"))
      (when (and (widget-value widget) (not (widget-disabled-p widget)))
        (style dom "color" "#ffffff")))
    (when (eq kind :cell)
      (attribute dom "aria-selected"
                 (if (widget-value widget) "true" "false"))
      (style dom "background"
             (if (widget-value widget) "#e7effa"
                 (widget-background widget)))
      (style dom "color" (widget-foreground widget))
      (style dom "outline"
             (if (widget-value widget)
                 (concatenate 'string "2px solid " (widget-accent widget))
                 "none"))
      (style dom "outline-offset" "-2px")
      (style dom "border" "1px solid #b8b8b8")
      (style dom "border-radius" "0")
      (style dom "padding" "2px 4px")
      (style dom "text-align" "left")
      (style dom "cursor" (if (widget-disabled-p widget) "default" "pointer"))
      (style dom "opacity" "1")
      (when (widget-disabled-p widget) (attribute dom "tabindex" "-1"))
      (style dom "box-shadow" "none")
      (style dom "backdrop-filter" "none"))
    (unless (eq (widget-style widget) :garnet)
      (style dom "flex-direction" "row")
      (style dom "justify-content" "normal"))
    (when (member kind '(:canvas :gauge))
      (style dom "padding" "0")
      (style dom "background" (widget-background widget))
      (style dom "backdrop-filter" "none")
      (style dom "box-shadow" "none")
      (style dom "border"
             (if (eq kind :canvas) "none"
                 (concatenate 'string "1px solid "
                              (widget-foreground widget)))))
    (when (eq kind :canvas) (style dom "border-radius" "0"))
    dom))

(fn update-canvas (dom (widget widget))
  (let ((index 0))
    (dolist (command (widget-value widget))
      (destructuring-bind (kind x y radius stroke fill) command
        (assert (eq kind :circle))
        (let ((circle ((jscl/ffi:oget dom "children" "item") index)))
          (when (eq circle #j:null)
            (setf circle (create-svg-node "circle"))
            ((jscl/ffi:oget dom "appendChild") circle))
          (attribute circle "cx" (px x))
          (attribute circle "cy" (px y))
          (attribute circle "r" (px radius))
          (attribute circle "stroke" (or stroke "none"))
          (attribute circle "fill" (or fill "none"))
          (incf index))))
    (loop :while (> (jscl/ffi:oget dom "children" "length") index)
          :do ((jscl/ffi:oget dom "lastElementChild" "remove")))))

(fn update-tablists ((app web-app))
  (let ((seen (make-hash-table :test 'equal)))
    (walk-elements
     (context-root (web-app-context app))
     (lambda (parent)
       (let ((tabs nil) (items nil))
         (do-children (node parent)
           (let ((widget (element-content node)))
             (when (widget-p widget)
               (case (widget-kind widget)
                 (:tab (push node tabs))
                 (:list-item (push node items))))))
         (dolist (nodes (list (nreverse tabs) (nreverse items)))
           (when nodes
             (let* ((kind (widget-kind (element-content (first nodes))))
                    (key (cons kind (mapcar #'element-id nodes)))
                    (group (gethash key (web-app-tablists app))))
               (unless group
                 (setf group (create-node "div")
                       (gethash key (web-app-tablists app)) group)
                 (attribute group "role"
                            (if (eq kind :tab) "tablist" "listbox"))
                 (style group "display" "contents")
                 (let* ((first (cdr (gethash (element-id (first nodes))
                                            (web-app-nodes app))))
                        (owner (jscl/ffi:oget first "parentNode")))
                   ((jscl/ffi:oget (web-app-host app) "insertBefore")
                    group (if (eq owner (web-app-host app)) first owner))))
               (setf (gethash key seen) t)
               (dolist (node nodes)
                 (let ((dom (cdr (gethash (element-id node)
                                         (web-app-nodes app)))))
                   (unless (eq group (jscl/ffi:oget dom "parentNode"))
                     ((jscl/ffi:oget group "appendChild") dom))))))))))
    (let ((removed nil))
      (maphash (lambda (key group)
                 (unless (gethash key seen)
                   ((jscl/ffi:oget group "remove"))
                   (push key removed)))
               (web-app-tablists app))
      (dolist (key removed) (remhash key (web-app-tablists app))))))

(fn reconcile-dom-order ((app web-app))
  (when (web-app-order-dirty-p app)
    (setf (web-app-order-dirty-p app) nil)
    (let ((nodes nil) (index 0) (seen (make-hash-table :test 'eq))
          (host (web-app-host app))
          (active #j:document:activeElement)
          (reference #j:null))
      (walk-elements
       (context-root (web-app-context app))
       (lambda (node)
         (when (widget-p (element-content node))
           (let* ((key (or (element-id node)
                           (list :anonymous (incf index))))
                  (dom (cdr (gethash key (web-app-nodes app)))))
             (incf index)
             (when dom (push dom nodes))))))
      (dolist (dom nodes)
        (let* ((owner (jscl/ffi:oget dom "parentNode"))
               (child (if (eq owner host) dom owner)))
          (unless (gethash child seen)
            (setf (gethash child seen) t)
            (unless (eq (jscl/ffi:oget child "nextSibling") reference)
              ((jscl/ffi:oget host "insertBefore") child reference))
            (setf reference child))))
      (unless (eq active #j:document:activeElement)
        ((jscl/ffi:oget active "focus"))))))

(fn cancel-deadline ((app web-app))
  (when (web-app-deadline-timer app)
    (#j:clearTimeout (web-app-deadline-timer app))
    (setf (web-app-deadline-timer app) nil)))

(fn schedule-deadline ((app web-app))
  (cancel-deadline app)
  (let ((deadline (context-next-frame (web-app-context app))))
    (when (and deadline (not (web-app-pending-p app)))
      (let ((delay (- deadline (/ (get-internal-real-time)
                                  internal-time-units-per-second))))
        (if (<= delay 0)
            (refresh app)
            (setf (web-app-deadline-timer app)
                  (#j:setTimeout
                   (lambda ()
                     (setf (web-app-deadline-timer app) nil)
                     (refresh app))
                   (ceiling (* 1000 delay)))))))))

(fn restore-application-focus ((app web-app))
  (when (web-app-tab-focus-p app)
    (let* ((context (web-app-context app))
           (id (context-focus context))
           (node (gethash id (lui.frame::context-ids context)))
           (target (gethash id (web-app-nodes app))))
      (cond ((null id) (setf (web-app-tab-focus-p app) nil))
            ((and target node (element-interactive-p node))
             (let ((control (if (eq (car target) :checkbox)
                                (jscl/ffi:oget (cdr target)
                                               "firstElementChild")
                                (cdr target))))
               ((jscl/ffi:oget control "focus"))
               (setf (web-app-tab-focus-p app) nil)))))))

(fn draw-frame ((app web-app))
  (let* ((host (web-app-host app))
         (context (web-app-context app))
         (previous-focus (context-focus context))
         (previous-active #j:document:activeElement)
         (desired-focus nil)
         (events (nreverse (web-app-events app)))
         (seen (make-hash-table :test 'equal))
         (index 0))
    (setf (web-app-events app) nil)
    (when (> (hash-table-count (web-app-measurements app)) 2048)
      (clrhash (web-app-measurements app)))
    (let ((*unit* 8))
      (with-frame
          (context (jscl/ffi:oget host "clientWidth")
                   (jscl/ffi:oget host "clientHeight") :events events)
        (funcall (web-app-callback app))))
    (setf desired-focus (context-focus context))
    (setf (web-app-hover-id app) (context-hover context))
    (when events (refresh app))
    (walk-elements
     (context-root context)
     (lambda (node)
       (when (widget-p (element-content node))
         (let* ((key
                 (or (element-id node)
                     (list :anonymous (incf index))))
                (dom (update-node app node key)))
           (style dom "z-index"
                  (jscl/ffi:clstring (#j:String (incf index))))
           (setf (gethash key seen) t)))))
    (update-tablists app)
    (let ((removed nil))
      (maphash
       (lambda (key entry)
         (unless (gethash key seen)
           (remove-node app (cdr entry))
           (setf (web-app-order-dirty-p app) t)
           (push key removed)))
       (web-app-nodes app))
      (dolist (key removed) (remhash key (web-app-nodes app))))
    (reconcile-dom-order app)
    ;; Reparenting can fire focus events for the old active DOM control.
    (setf (context-focus context) desired-focus)
    (when (or (not (equal previous-focus (context-focus context)))
              (and (not (eq previous-active #j:document:activeElement))
                   (equal (jscl/ffi:oget previous-active "luiId")
                          (context-focus context))))
      (setf (web-app-tab-focus-p app) t))
    (restore-application-focus app)
    (schedule-deadline app)))

(fn refresh ((app web-app))
  (cancel-deadline app)
  (when (and (web-app-alive-p app) (not (web-app-pending-p app)))
    (setf (web-app-pending-p app) t)
    (setf (web-app-animation-frame app)
          (#j:requestAnimationFrame
           (lambda (time)
             (declare (ignore time))
             (setf (web-app-pending-p app) nil
                   (web-app-animation-frame app) nil)
             (when (web-app-alive-p app)
               (draw-frame app)))))))

(fn mount (host (callback function))
  "Mount in an existing DOM element with explicit dimensions. Returns a handle."
  (let* ((app (make-web-app :host host :callback callback))
         (measure (create-node "span"))
         (sheet (create-node "style")))
    (style host "position" "relative")
    (style host "overflow" "hidden")
    (style host "font-family" "DejaVu Sans, Arial, sans-serif")
    (style measure "position" "absolute")
    (style measure "visibility" "hidden")
    (style measure "pointer-events" "none")
    (setf (jscl/ffi:oget sheet "textContent")
          #j".lui-control{cursor:pointer;transition:filter 100ms,transform 100ms}.lui-control:hover:enabled{filter:brightness(1.2)}.lui-control:active:enabled{filter:brightness(.85);transform:translateY(1px)}.lui-control:disabled{opacity:1;cursor:not-allowed}.lui-control:focus-visible{outline:2px solid var(--lui-accent);outline-offset:-3px}.lui-range{cursor:pointer}.lui-range:focus-visible{outline:2px solid var(--lui-accent);outline-offset:-3px}.lui-range:disabled{cursor:not-allowed;--lui-accent:#999}.lui-range::-webkit-slider-runnable-track{height:4px;border:0;border-radius:2px;background:linear-gradient(to right,var(--lui-accent) var(--lui-fill),#777 var(--lui-fill))}.lui-range::-webkit-slider-thumb{appearance:none;width:14px;height:14px;margin-top:-5px;border:0;border-radius:var(--lui-thumb-radius);background:#fff}.lui-range:disabled::-webkit-slider-thumb{background:#a0a0a0}.lui-range::-moz-range-track{height:4px;border:0;border-radius:2px;background:#777}.lui-range::-moz-range-progress{height:4px;background:var(--lui-accent)}.lui-range::-moz-range-thumb{width:14px;height:14px;border:0;border-radius:var(--lui-thumb-radius);background:#fff}.lui-range:disabled::-moz-range-thumb{background:#a0a0a0}.lui-check{cursor:pointer}.lui-check:has(:disabled){cursor:not-allowed;color:#777}.lui-check:hover input:enabled{filter:brightness(1.2)}.lui-motif-check input{appearance:none;background:#b8b8b8;border:2px outset #ddd;border-radius:0;display:grid;place-content:center}.lui-motif-check input:checked{border-style:inset}.lui-motif-check input:checked::after{content:\"\";width:8px;height:4px;border-left:2px solid currentColor;border-bottom:2px solid currentColor;transform:rotate(-45deg);margin-top:-3px}")
    (setf (jscl/ffi:oget sheet "textContent")
          (#j:String:prototype:concat:call
           (jscl/ffi:oget sheet "textContent")
           #j"[data-lui-style=garnet].lui-control:hover:enabled{filter:none;background:#eee!important}[data-lui-style=garnet].lui-control:active:enabled{filter:none;transform:translate(4px,4px);box-shadow:inset 0 0 0 1px #000!important}.lui-garnet-check input{appearance:none;background:linear-gradient(#fff,#fff) 3px 3px / calc(100% - 6px) calc(100% - 6px) no-repeat,repeating-conic-gradient(#000 0% 25%,#fff 0% 50%) 0 0 / 2px 2px;border:1px solid #000;border-radius:0;box-shadow:4px 4px 0 #000;display:grid;place-content:center}.lui-garnet-check input:checked::after{content:\"\";width:10px;height:10px;background:linear-gradient(45deg,transparent 44%,currentColor 44%,currentColor 56%,transparent 56%),linear-gradient(-45deg,transparent 44%,currentColor 44%,currentColor 56%,transparent 56%)}[data-lui-style=garnet].lui-range::-webkit-slider-runnable-track{height:12px;border:1px solid #000;border-radius:0;background:repeating-conic-gradient(#000 0% 25%,#fff 0% 50%) 0 0 / 2px 2px}[data-lui-style=garnet].lui-range::-webkit-slider-thumb{width:18px;height:18px;margin-top:-4px;border:1px solid #000;border-radius:0;background:#fff;box-shadow:3px 3px 0 #000}[data-lui-style=garnet].lui-range::-moz-range-track{height:12px;border:1px solid #000;border-radius:0;background:repeating-conic-gradient(#000 0% 25%,#fff 0% 50%) 0 0 / 2px 2px}[data-lui-style=garnet].lui-range::-moz-range-progress{background:transparent}[data-lui-style=garnet].lui-range::-moz-range-thumb{width:18px;height:18px;border:1px solid #000;border-radius:0;background:#fff;box-shadow:3px 3px 0 #000}"))
    (setf (jscl/ffi:oget sheet "textContent")
          (#j:String:prototype:concat:call
           (jscl/ffi:oget sheet "textContent")
           #j".lui-option:active:enabled{transform:none;filter:none}.lui-option[aria-selected=false]:hover:enabled{filter:none;background:color-mix(in srgb,var(--lui-accent) 14%,transparent)!important}.lui-option[aria-selected=true]:hover:enabled{filter:none;background:var(--lui-accent)!important}"))
    (setf (jscl/ffi:oget sheet "textContent")
          (#j:String:prototype:concat:call
           (jscl/ffi:oget sheet "textContent")
           #j".lui-cell:focus-visible{outline:2px solid var(--lui-accent);outline-offset:-2px}"))
    ((jscl/ffi:oget host "appendChild") sheet)
    ((jscl/ffi:oget host "appendChild") measure)
    (setf (web-app-style-node app) sheet
          (web-app-measure-node app) measure
          (web-app-context app)
          (make-context :measure
                        (lambda (widget width)
                          (measure-widget app widget width)))
          (web-app-resize-handler app)
          (lambda (event)
            (declare (ignore event))
            (refresh app)))
    (#j:window:addEventListener #j"resize" (web-app-resize-handler app))
    (setf (web-app-wheel-handler app)
          (lambda (event)
            (when (web-app-alive-p app)
              ((jscl/ffi:oget event "preventDefault"))
              (let ((rect ((jscl/ffi:oget host "getBoundingClientRect"))))
                (queue-event
                 app
                 (make-event
                  :kind :scroll
                  :x (- (jscl/ffi:oget event "clientX")
                        (jscl/ffi:oget rect "left"))
                  :y (- (jscl/ffi:oget event "clientY")
                        (jscl/ffi:oget rect "top"))
                  :value (jscl/ffi:oget event "deltaY")))))))
    (setf (web-app-resize-observer app)
          (jscl/ffi:new
           #j:ResizeObserver
           (lambda (entries observer)
             (declare (ignore entries observer))
             (refresh app))))
    ((jscl/ffi:oget (web-app-resize-observer app) "observe") host)
    (listen app host "wheel" (web-app-wheel-handler app) t)
    (listen app host "pointermove"
            (lambda (event)
              (let* ((target ((jscl/ffi:oget event "target" "closest")
                              #j"[data-lui-interactive='true']"))
                     (id (unless (eq target #j:null)
                           (jscl/ffi:oget target "luiId"))))
                (when (or (not (equal id (web-app-hover-id app)))
                          (and (not (eq target #j:null))
                               (string= "svg" (jscl/ffi:clstring
                                               (jscl/ffi:oget target
                                                              "localName")))))
                  (setf (web-app-hover-id app) id)
                  (let ((rect ((jscl/ffi:oget host "getBoundingClientRect"))))
                    (queue-event
                     app (make-event
                          :kind :move
                          :x (- (jscl/ffi:oget event "clientX")
                                (jscl/ffi:oget rect "left"))
                          :y (- (jscl/ffi:oget event "clientY")
                                (jscl/ffi:oget rect "top")))))))))
    (listen app host "pointerleave"
            (lambda (event)
              (declare (ignore event))
              (when (web-app-hover-id app)
                (setf (web-app-hover-id app) nil)
                (queue-event app (make-event :kind :move :x -1 :y -1)))))
    (refresh app)
    app))

(fn unmount ((app web-app))
  (cancel-deadline app)
  (setf (web-app-alive-p app) nil
        (web-app-events app) nil
        (web-app-pending-p app) nil)
  (when (web-app-animation-frame app)
    (#j:cancelAnimationFrame (web-app-animation-frame app))
    (setf (web-app-animation-frame app) nil))
  ((jscl/ffi:oget (web-app-resize-observer app) "disconnect"))
  (dolist (listener (web-app-listeners app))
    (destructuring-bind (node name function capture) listener
      ((jscl/ffi:oget node "removeEventListener")
       (jscl/ffi:jsstring name) function (jscl/ffi:jsbool capture))))
  (setf (web-app-listeners app) nil)
  (#j:window:removeEventListener #j"resize" (web-app-resize-handler app))
  (maphash
   (lambda (key entry)
     (declare (ignore key))
     (remove-node app (cdr entry))) (web-app-nodes app))
  ((jscl/ffi:oget (web-app-measure-node app) "remove"))
  ((jscl/ffi:oget (web-app-style-node app) "remove"))
  (clrhash (web-app-nodes app))
  (clrhash (web-app-measurements app))
  (maphash (lambda (key group)
             (declare (ignore key))
             ((jscl/ffi:oget group "remove")))
           (web-app-tablists app))
  (clrhash (web-app-tablists app)))

(fn run-web ((draw function) &key title width height (interactive t))
  (declare (ignore interactive))
  (setf (jscl/ffi:oget #j:document "title") (jscl/ffi:jsstring title))
  (let ((host (create-node "main")))
    (attribute host "aria-label" title)
    (style host "width" (if width (px width) "100%"))
    (style host "height" (if height (px height) "100vh"))
    (style host "background"
           "radial-gradient(at 10% 20%, #254f7b, transparent 65%), radial-gradient(at 90% 80%, #613f7a, #191d29 75%)")
    (#j:document:body:appendChild host)
    (mount host draw)))

(register-backend :web #'run-web)
