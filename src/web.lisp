(defpackage #:lui.web
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui)
  (:export #:mount #:unmount #:refresh))

(in-package #:lui.web)

(defstruct web-app
  host
  measure-node
  callback
  context
  (nodes (make-hash-table :test 'equal) :type hash-table)
  (events nil :type list)
  (pending-p nil :type boolean)
  (alive-p t :type boolean)
  resize-handler
  resize-observer
  animation-frame
  wheel-handler
  (listeners nil :type list))

(fn create-node ((tag string))
  (#j:document:createElement (jscl/ffi:jsstring tag)))

(fn style (node (name string) (value string))
  ((jscl/ffi:oget node "style" "setProperty") (jscl/ffi:jsstring name)
   (jscl/ffi:jsstring value)))

(fn px ((value real)) (format nil "~Dpx" (round value)))

(fn attribute (node (name string) (value string))
  ((jscl/ffi:oget node "setAttribute") (jscl/ffi:jsstring name)
   (jscl/ffi:jsstring value)))

(fn listen ((app web-app) node (name string) (function function))
  ((jscl/ffi:oget node "addEventListener")
   (jscl/ffi:jsstring name) function)
  (push (list node name function) (web-app-listeners app)))

(fn remove-node ((app web-app) node)
  (setf (web-app-listeners app)
        (delete-if
         (lambda (listener)
           (destructuring-bind (target name function) listener
             (when (or (eq target node)
                       (jscl/ffi:clbool
                        ((jscl/ffi:oget node "contains") target)))
               ((jscl/ffi:oget target "removeEventListener")
                (jscl/ffi:jsstring name) function)
               t)))
         (web-app-listeners app)))
  ((jscl/ffi:oget node "remove")))

(fn queue-event ((app web-app) (event event))
  (when (web-app-alive-p app)
    (push event (web-app-events app))
    (refresh app)))

(fn control-change ((app web-app) control kind id)
  (queue-event
   app
   (make-event :kind :change :id id :value
               (case kind
                 (:checkbox
                  (jscl/ffi:clbool (jscl/ffi:oget control "checked")))
                 (:slider (jscl/ffi:oget control "valueAsNumber"))
                 (otherwise
                  (jscl/ffi:clstring (jscl/ffi:oget control "value")))))))

(fn measure-widget ((app web-app) (widget widget) width)
  (let* ((node (web-app-measure-node app))
         (kind (widget-kind widget))
         (text (if (eq kind :text-field)
                   (widget-value widget)
                   (widget-text widget)))
         (extra (if (eq kind :label) 0 24)))
    (setf (jscl/ffi:oget node "textContent") (jscl/ffi:jsstring text))
    (style node "font-size" (px (widget-font-size widget)))
    (style node "width"
           (if width (px (max 0 (- width extra))) "max-content"))
    (style node "white-space" (if (eq kind :label) "pre-wrap" "pre"))
    (let ((rect ((jscl/ffi:oget node "getBoundingClientRect"))))
      (values
       (max (case kind (:slider 160) (:text-field 160) (otherwise 0))
            (+ extra (jscl/ffi:oget rect "width")))
       (max (+ (if (eq kind :label) 0 12) (widget-font-size widget))
            (+ (if (eq kind :label) 0 12) (jscl/ffi:oget rect "height")))))))

(fn widget-node ((app web-app) (node element) key)
  (let* ((widget (element-content node))
         (kind (widget-kind widget))
         (entry (gethash key (web-app-nodes app))))
    (when (and entry (not (eq kind (car entry))))
      (remove-node app (cdr entry))
      (setf entry nil))
    (unless entry
      (let* ((dom (create-node
                   (case kind
                     (:button "button")
                     ((:slider :text-field) "input")
                     (:checkbox "label")
                     (otherwise "div"))))
             (control (if (eq kind :checkbox) (create-node "input") dom))
             (id (element-id node)))
        (when (eq kind :checkbox)
          ((jscl/ffi:oget dom "appendChild") control)
          ((jscl/ffi:oget dom "appendChild") (create-node "span")))
        (case kind
          (:button
           (attribute dom "type" "button")
           (listen app dom "click"
                   (lambda (event)
                     (declare (ignore event))
                     (queue-event
                      app (make-event :kind :activate :id id)))))
          ((:slider :text-field :checkbox)
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
                       (control-change app control kind id))))
           (when (eq kind :text-field)
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
                       (control-change app control kind id)))))
          (otherwise nil))
        (listen app control "focus"
                (lambda (event)
                  (declare (ignore event))
                  (setf (context-focus (web-app-context app)) id)))
        ((jscl/ffi:oget (web-app-host app) "appendChild") dom)
        (setf entry (cons kind dom) (gethash key (web-app-nodes app))
              entry)))
    (cdr entry)))

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
    (style dom "position" "absolute")
    (style dom "box-sizing" "border-box")
    (style dom "margin" "0")
    (style dom "font-family" "inherit")
    (style dom "left" (px (box-x box)))
    (style dom "top" (px (box-y box)))
    (style dom "width" (px (box-width box)))
    (style dom "height" (px (box-height box)))
    (style dom "font-size" (px (widget-font-size widget)))
    (style dom "color" (widget-foreground widget))
    (style dom "accent-color" (widget-accent widget))
    (style dom "white-space" "pre-wrap")
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
    (unless (member kind '(:text-field :slider :checkbox))
      (setf (jscl/ffi:oget dom "textContent")
            (jscl/ffi:jsstring (widget-text widget))))
    (unless (eq kind :label)
      (setf (jscl/ffi:oget control "disabled")
            (jscl/ffi:jsbool (widget-disabled-p widget)))
      (attribute control "aria-label"
                 (if (plusp (length (widget-text widget)))
                     (widget-text widget)
                     (princ-to-string key)))
      (style dom "border-radius" (px (if glass (widget-radius widget) 0)))
      (style dom "border"
             (if glass "1px solid #ffffff66" "2px outset #dddddd"))
      (style dom "background"
             (if glass
                 (format nil "color-mix(in srgb, ~A ~D%, transparent)"
                         (widget-background widget)
                         (round (* 100 (widget-opacity widget))))
                 (widget-background widget)))
      (style dom "backdrop-filter"
             (if glass
                 (format nil "blur(~A) saturate(150%)"
                         (px (widget-frost widget))) "none"))
      (style dom "box-shadow"
             (if glass "inset 0 1px 1px #ffffff88, 0 3px 12px #00000044"
                 "none")))
    (case kind
      (:checkbox
       (style dom "display" "flex")
       (style dom "align-items" "center")
       (style dom "gap" "8px")
       (setf (jscl/ffi:oget control "checked")
             (jscl/ffi:jsbool (widget-value widget))
             (jscl/ffi:oget dom "lastElementChild" "textContent")
             (jscl/ffi:jsstring (widget-text widget))))
      (:slider
       (attribute dom "min" (princ-to-string (widget-minimum widget)))
       (attribute dom "max" (princ-to-string (widget-maximum widget)))
       (attribute dom "step" (princ-to-string (widget-step widget)))
       (setf (jscl/ffi:oget dom "valueAsNumber") (widget-value widget)))
      (:text-field
       (unless
           (or (jscl/ffi:clbool (jscl/ffi:oget dom "luiComposing"))
               (string= (widget-value widget)
                        (jscl/ffi:clstring (jscl/ffi:oget dom "value"))))
         (setf (jscl/ffi:oget dom "value")
               (jscl/ffi:jsstring (widget-value widget)))))
      (otherwise nil))
    dom))

(fn draw-frame ((app web-app))
  (let* ((host (web-app-host app))
         (context (web-app-context app))
         (events (nreverse (web-app-events app)))
         (seen (make-hash-table :test 'equal))
         (index 0))
    (setf (web-app-events app) nil)
    (let ((*unit* 8))
      (with-frame
          (context (jscl/ffi:oget host "clientWidth")
                   (jscl/ffi:oget host "clientHeight") :events events)
        (funcall (web-app-callback app))))
    (when events (refresh app))
    (walk-elements
     (context-root context)
     (lambda (node)
       (when (widget-p (element-content node))
         (let* ((key
                 (or (element-id node)
                     (list :anonymous (incf index))))
                (dom (update-node app node key)))
           (style dom "z-index" (princ-to-string (incf index)))
           (setf (gethash key seen) t)))))
    (let ((removed nil))
      (maphash
       (lambda (key entry)
         (unless (gethash key seen)
           (remove-node app (cdr entry))
           (push key removed)))
       (web-app-nodes app))
      (dolist (key removed) (remhash key (web-app-nodes app))))))

(fn refresh ((app web-app))
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
         (measure (create-node "span")))
    (style host "position" "relative")
    (style host "overflow" "hidden")
    (style host "font-family" "sans-serif")
    (style measure "position" "absolute")
    (style measure "visibility" "hidden")
    (style measure "pointer-events" "none")
    ((jscl/ffi:oget host "appendChild") measure)
    (setf (web-app-measure-node app) measure
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
    (listen app host "wheel" (web-app-wheel-handler app))
    (refresh app)
    app))

(fn unmount ((app web-app))
  (setf (web-app-alive-p app) nil
        (web-app-events app) nil
        (web-app-pending-p app) nil)
  (when (web-app-animation-frame app)
    (#j:cancelAnimationFrame (web-app-animation-frame app))
    (setf (web-app-animation-frame app) nil))
  ((jscl/ffi:oget (web-app-resize-observer app) "disconnect"))
  (dolist (listener (web-app-listeners app))
    (destructuring-bind (node name function) listener
      ((jscl/ffi:oget node "removeEventListener")
       (jscl/ffi:jsstring name) function)))
  (setf (web-app-listeners app) nil)
  (#j:window:removeEventListener #j"resize" (web-app-resize-handler app))
  (maphash
   (lambda (key entry)
     (declare (ignore key))
     (remove-node app (cdr entry))) (web-app-nodes app))
  ((jscl/ffi:oget (web-app-measure-node app) "remove"))
  (clrhash (web-app-nodes app)))

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
