(defpackage #:lui.web
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui
        #:lui.web.style)
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

(defvar *dom-id-counter* 0)

(fn fresh-dom-id ()
  (loop :for id := (format nil "lui-scroll-~D" (incf *dom-id-counter*))
        :when (eq #j:null (#j:document:getElementById
                          (jscl/ffi:jsstring id)))
          :return id))

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
  (unless (or (jscl/ffi:clbool (jscl/ffi:oget event "isComposing"))
              (jscl/ffi:clbool (jscl/ffi:oget event "ctrlKey"))
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

(fn native-scrollbar-key ((app web-app) id event)
  (let ((key (cdr (assoc
                   (jscl/ffi:clstring (jscl/ffi:oget event "key"))
                   '(("ArrowUp" . :up) ("ArrowDown" . :down)
                     ("ArrowLeft" . :left) ("ArrowRight" . :right)
                     ("PageUp" . :page-up) ("PageDown" . :page-down)
                     ("Home" . :home) ("End" . :end)) :test #'string=))))
    (when key
      ((jscl/ffi:oget event "preventDefault"))
      (setf (web-app-tab-focus-p app) t)
      (queue-event app (make-event :kind :key :key key :id id)))))

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
        (when (member kind '(:canvas :splitter :scrollbar))
          (setf (jscl/ffi:oget dom "luiContinuousMove") #j:true)
          (attribute dom "role" (case kind (:canvas "img")
                                 (:scrollbar "scrollbar")
                                 (otherwise "separator")))
          (attribute dom "tabindex" "0")
          (style dom "touch-action" "none")
          (listen app dom "keydown"
                  (lambda (event)
                    (case kind
                      (:canvas (native-application-key app id event))
                      (:scrollbar (native-scrollbar-key app id event))
                      (otherwise (native-tab-key app id event)))))
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
        (unless (eq kind :highlight)
          (listen app control "focus"
                  (lambda (event)
                    (declare (ignore event))
                    (setf (context-focus (web-app-context app)) id))))
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
                (widget-web-style widget) (toolkit-revision)
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
                      (jscl/ffi:oget dom "firstElementChild") dom))
         (box (element-box node)) (clip (element-clip node)))
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
      ;; Hooks may write raw DOM styles. Replacing/removing one must restore
      ;; defaults rather than trusting the previous inline-style cache.
      (unless (and (eql (toolkit-revision)
                        (jscl/ffi:oget dom "luiStyleRevision"))
                   (eq (widget-web-style widget)
                       (jscl/ffi:oget dom "luiWidgetStyle"))
                   (eq (widget-style widget)
                       (jscl/ffi:oget dom "luiToolkit")))
        (setf (jscl/ffi:oget dom "style" "cssText") #j""
              (jscl/ffi:oget dom "luiStyles") #j:undefined
              (jscl/ffi:oget dom "luiAttributes") #j:undefined
              (jscl/ffi:oget dom "luiStyleRevision") (toolkit-revision)
              (jscl/ffi:oget dom "luiWidgetStyle") (widget-web-style widget)
              (jscl/ffi:oget dom "luiToolkit") (widget-style widget)))
      (setf (jscl/ffi:oget dom "luiSignature") signature))
    (when (and (eq kind :panel) (= 1 (widget-opacity widget))
               (= 0 (box-x box) (box-y box))
               (= (box-width box) (context-width (web-app-context app)))
               (= (box-height box) (context-height (web-app-context app))))
      (style (web-app-host app) "background" (widget-background widget)))
    (attribute dom "data-lui-interactive"
               (if (element-interactive-p node) "true" "false"))
    (attribute dom "data-lui-style"
               (string-downcase (symbol-name (widget-style widget))))
    (attribute dom "data-lui-surface"
               (string-downcase (symbol-name
                                 (toolkit-surface (widget-style widget)))))
    (attribute dom "class"
               (case kind
                 ((:button :tab) "lui-control")
                 (:cell "lui-cell") (:list-item "lui-control lui-option")
                 (:checkbox "lui-check") (:slider "lui-range")
                 (:highlight "lui-highlight") (:splitter "lui-splitter")
                 (:scrollbar "lui-scrollbar")
                 (otherwise "")))
    (style dom "display" (if (eq kind :checkbox) "flex" "block"))
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
    (style dom "color" (if (widget-disabled-p widget)
                           "#777777" (widget-foreground widget)))
    (let ((accent (if (widget-disabled-p widget)
                      "#999999" (widget-accent widget))))
      (style dom "accent-color" accent)
      (style dom "--lui-accent" accent))
    (style dom "white-space" "pre-wrap")
    (style dom "text-align" "left")
    (style dom "line-height" "normal")
    (style dom "clip-path"
           (format nil "inset(~A ~A ~A ~A)"
                   (px (- (box-y clip) (box-y box)))
                   (px (max 0 (- (+ (box-x box) (box-width box))
                                 (+ (box-x clip) (box-width clip)))))
                   (px (max 0 (- (+ (box-y box) (box-height box))
                                 (+ (box-y clip) (box-height clip)))))
                   (px (- (box-x clip) (box-x box)))))
    (unless (member kind '(:text-field :slider :checkbox :canvas :gauge
                          :highlight :splitter :scrollbar))
      (node-text dom (widget-text widget)))
    (unless (member kind '(:label :highlight :splitter))
      (property control "disabled"
                (jscl/ffi:jsbool (widget-disabled-p widget)))
      (attribute control "aria-label"
                 (if (plusp (length (widget-text widget)))
                     (widget-text widget)
                     (if (eq kind :cell) "Empty cell"
                         (princ-to-string key)))))
    (case kind
      (:scrollbar
       (let ((owner (cdr (gethash (second (element-id node))
                                  (web-app-nodes app)))))
         (when owner
           (when (string= "" (jscl/ffi:clstring (jscl/ffi:oget owner "id")))
             (attribute owner "id" (fresh-dom-id)))
           (attribute dom "aria-controls"
                      (jscl/ffi:clstring (jscl/ffi:oget owner "id")))))
       (destructuring-bind (offset viewport extent) (widget-value widget)
         (attribute dom "aria-orientation" "vertical")
         (attribute dom "aria-valuemin" "0")
         (attribute dom "aria-valuemax"
                    (jscl/ffi:clstring (#j:String (- extent viewport))))
         (attribute dom "aria-valuenow"
                    (jscl/ffi:clstring (#j:String offset))))
       (style dom "padding" "0")
       (style dom "border" "none")
       (style dom "background" (widget-background widget))
       (style dom "cursor" "default")
       (style dom "touch-action" "none")
       (style dom "user-select" "none")
       (when (eq #j:null (jscl/ffi:oget dom "firstElementChild"))
         ((jscl/ffi:oget dom "appendChild") (create-node "div")))
       (let ((thumb (jscl/ffi:oget dom "firstElementChild"))
             (bounds (scrollbar-thumb node)))
         (style thumb "pointer-events" "none")
         (style thumb "position" "absolute")
         (style thumb "top" (px (- (box-y bounds) (box-y box))))
         (style thumb "width" "100%")
         (style thumb "height" (px (box-height bounds)))
         (style thumb "background" (widget-accent widget))))
      (:splitter
       (attribute dom "aria-orientation" "vertical")
       (attribute dom "aria-label" (if (plusp (length (widget-text widget)))
                                       (widget-text widget) "Panel width"))
       (attribute dom "aria-valuemin" "0")
       (attribute dom "aria-valuemax" "1")
       (attribute dom "aria-valuenow"
                  (jscl/ffi:clstring (#j:String (widget-value widget))))
       (style dom "cursor" "ew-resize")
       (style dom "user-select" "none")
       (style dom "background"
              (format nil "linear-gradient(90deg, transparent calc(50% - 1px), ~A calc(50% - 1px), ~A calc(50% + 1px), transparent calc(50% + 1px))"
                      (widget-accent widget) (widget-accent widget))))
      (:highlight
       (attribute dom "aria-hidden" "true")
       (style dom "pointer-events" "none")
       (style dom "user-select" "none")
       (style dom "padding" "0")
       (style dom "border-radius" "0")
       (style dom "border"
              (concatenate 'string "1px solid " (widget-accent widget)))
       (style dom "background"
              (format nil "color-mix(in srgb, ~A ~D%, transparent)"
                      (widget-background widget)
                      (round (* 100 (widget-opacity widget))))))
      (:tab
       (attribute dom "aria-selected"
                  (if (widget-value widget) "true" "false"))
       (attribute dom "tabindex"
                  (if (and (widget-value widget)
                           (not (widget-disabled-p widget))) "0" "-1")))
      ((:list-item :cell)
       (attribute dom "aria-selected"
                  (if (widget-value widget) "true" "false")))
      (:checkbox
       (attribute control "class" "lui-control")
       (style dom "align-items" "center")
       (style dom "gap" "8px")
       (style control "margin" "0")
       (style control "width" "16px")
       (style control "height" "16px")
       (style control "flex-shrink" "0")
       (property control "checked" (jscl/ffi:jsbool (widget-value widget)))
       (node-text (jscl/ffi:oget dom "lastElementChild")
                  (widget-text widget)))
      (:slider
       (style dom "appearance" "none")
       (style dom "padding" "0 7px")
       (style dom "--lui-fill"
              (jscl/ffi:clstring
               ((jscl/ffi:oget
                 (#j:String (* 100 (/ (- (widget-value widget)
                                        (widget-minimum widget))
                                     (- (widget-maximum widget)
                                        (widget-minimum widget)))))
                 "concat") #j"%")))
       (attribute dom "min" (princ-to-string (widget-minimum widget)))
       (attribute dom "max" (princ-to-string (widget-maximum widget)))
       (attribute dom "step" (princ-to-string (widget-step widget)))
       (property dom "valueAsNumber" (widget-value widget)))
      (:text-field
       (style dom "appearance" "none")
       (unless (jscl/ffi:clbool (jscl/ffi:oget dom "luiComposing"))
         (property dom "value" (jscl/ffi:jsstring (widget-value widget)))))
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
    (finish-control-style dom widget node)
    (let ((*context* (web-app-context app)))
      (map-toolkit-web-styles
       (widget-style widget)
       (lambda (callback) (funcall callback dom widget node)))
      (when (widget-web-style widget)
        (funcall (widget-web-style widget) dom widget node)))
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
  "Request one redraw of a mounted application, coalescing pending requests."
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
    (setf (jscl/ffi:oget sheet "textContent") (style-sheets))
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
                  ;; No standardized browser flag distinguishes OS inertia.
                  ;; Preserve fine/fractional pixel motion; ease coarse notches.
                  :scroll-mode
                  (let ((delta (jscl/ffi:oget event "deltaY")))
                    (if (and (zerop (jscl/ffi:oget event "deltaMode"))
                             (or (< (abs delta) 20)
                                 (/= delta (truncate delta))))
                        :immediate :smooth))
                  :value (* (jscl/ffi:oget event "deltaY")
                            (case (jscl/ffi:oget event "deltaMode")
                              (1 16)
                              (2 (jscl/ffi:oget host "clientHeight"))
                              (otherwise 1)))))))))
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
                               (jscl/ffi:clbool
                                (jscl/ffi:oget target "luiContinuousMove"))))
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
  "Dispose an application, cancelling scheduled frames and DOM listeners."
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
