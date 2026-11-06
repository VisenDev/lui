(defpackage #:lui.web.style
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets)
  (:export #:style #:attribute #:px #:add-sheet #:style-sheets
           #:framed-p #:window-panel-p #:tab-underline
           #:finish-control-style))
(in-package #:lui.web.style)

(fn node-cache (node (name string))
  (let ((cache (jscl/ffi:oget node name)))
    (if (eq cache #j:undefined)
        (setf (jscl/ffi:oget node name) (jscl/ffi:new #j:Object))
        cache)))

(fn style (node (name string) (value string))
  "Set one inline CSS property, avoiding unchanged writes."
  (let ((cache (node-cache node "luiStyles"))
        (native (jscl/ffi:jsstring value)))
    (unless (eq native (jscl/ffi:oget cache name))
      ((jscl/ffi:oget node "style" "setProperty")
       (jscl/ffi:jsstring name) native)
      (setf (jscl/ffi:oget cache name) native))))

(fn px ((value real))
  "Return VALUE as a CSS pixel length without rounding away fractions."
  (jscl/ffi:clstring
   ((jscl/ffi:oget (#j:String value) "concat") #j"px")))

(fn attribute (node (name string) (value string))
  "Set one DOM attribute, avoiding unchanged writes."
  (let ((cache (node-cache node "luiAttributes"))
        (native (jscl/ffi:jsstring value)))
    (unless (eq native (jscl/ffi:oget cache name))
      ((jscl/ffi:oget node "setAttribute") (jscl/ffi:jsstring name) native)
      (setf (jscl/ffi:oget cache name) native))))

(defvar *sheets* nil)

(fn add-sheet ((name symbol) css)
  "Register or replace a named native JavaScript CSS string for new mounts."
  (let ((entry (assoc name *sheets*)))
    (if entry (setf (cdr entry) css) (push (cons name css) *sheets*))))

(fn style-sheets ()
  "Combine registered stylesheets in registration order."
  (let ((result #j""))
    (dolist (entry (reverse *sheets*) result)
      (setf result ((jscl/ffi:oget result "concat") (cdr entry))))))

(fn (framed-p boolean) ((widget widget))
  "Return whether WIDGET uses its collection's normal control frame."
  (not (member (widget-kind widget)
               '(:label :highlight :splitter :list-item :cell :canvas :gauge
                 :scrollbar))))

(fn window-panel-p ((widget widget) (node element))
  "Test whether NODE is a panel covering the active window."
  (let ((box (element-box node)))
    (and (eq (widget-kind widget) :panel)
         (= 0 (box-x box) (box-y box))
         (= (box-width box) (context-width *context*))
         (= (box-height box) (context-height *context*)))))

(fn tab-underline (dom (widget widget))
  "Apply the selected-tab accent underline to DOM."
  (when (and (eq (widget-kind widget) :tab) (widget-value widget))
    (style dom "box-shadow"
           (format nil "inset 0 -3px 0 ~A" (widget-accent widget)))))

(fn finish-control-style (dom (widget widget) (node element))
  "Apply shared flat-cell, list-row, canvas, and gauge defaults."
  (let ((kind (widget-kind widget)) (box (element-box node)))
    (when (eq kind :list-item)
      (let ((inset (min 11 (max 0 (/ (- (box-width box)
                                        (widget-font-size widget)) 2)))))
        (style dom "padding" (concatenate 'string "5px " (px inset)))
        (style dom "text-align" (if (< inset 11) "center" "left")))
      (style dom "border" "none")
      (style dom "border-radius" "0")
      (style dom "box-shadow" "none")
      (style dom "backdrop-filter" "none")
      (style dom "background"
             (if (widget-value widget) (widget-accent widget) "transparent"))
      (when (and (widget-value widget) (not (widget-disabled-p widget)))
        (style dom "color" "#ffffff")))
    (when (eq kind :cell)
      (style dom "background"
             (if (widget-value widget) "#e7effa" (widget-background widget)))
      (style dom "color" (widget-foreground widget))
      (style dom "outline"
             (if (widget-value widget)
                 (concatenate 'string "2px solid " (widget-accent widget))
                 "none"))
      (style dom "outline-offset" "-2px")
      (style dom "border" "1px solid #b8b8b8")
      (style dom "border-radius" "0")
      (style dom "padding" "2px 4px")
      (style dom "cursor" (if (widget-disabled-p widget) "default" "pointer"))
      (style dom "opacity" "1")
      (when (widget-disabled-p widget) (attribute dom "tabindex" "-1"))
      (style dom "text-align" "left")
      (style dom "box-shadow" "none")
      (style dom "backdrop-filter" "none"))
    (when (member kind '(:canvas :gauge))
      (style dom "padding" "0")
      (style dom "background" (widget-background widget))
      (style dom "backdrop-filter" "none")
      (style dom "box-shadow" "none")
      (style dom "border"
             (if (eq kind :canvas) "none"
                 (concatenate 'string "1px solid "
                              (widget-foreground widget)))))
    (when (eq kind :canvas) (style dom "border-radius" "0"))))

(add-sheet :common
 #j".lui-control{cursor:pointer;transition:filter 100ms,transform 100ms}.lui-control:hover:enabled{filter:brightness(1.2)}.lui-control:active:enabled{filter:brightness(.85);transform:translateY(1px)}.lui-control:disabled{opacity:1;cursor:not-allowed}.lui-control:focus-visible{outline:2px solid var(--lui-accent);outline-offset:-3px}.lui-range{cursor:pointer}.lui-range:focus-visible{outline:2px solid var(--lui-accent);outline-offset:-3px}.lui-range:disabled{cursor:not-allowed;--lui-accent:#999}.lui-range::-webkit-slider-runnable-track{height:4px;border:0;border-radius:2px;background:linear-gradient(to right,var(--lui-accent) var(--lui-fill),#777 var(--lui-fill))}.lui-range::-webkit-slider-thumb{appearance:none;width:14px;height:14px;margin-top:-5px;border:0;border-radius:var(--lui-thumb-radius);background:#fff}.lui-range:disabled::-webkit-slider-thumb{background:#a0a0a0}.lui-range::-moz-range-track{height:4px;border:0;border-radius:2px;background:#777}.lui-range::-moz-range-progress{height:4px;background:var(--lui-accent)}.lui-range::-moz-range-thumb{width:14px;height:14px;border:0;border-radius:var(--lui-thumb-radius);background:#fff}.lui-range:disabled::-moz-range-thumb{background:#a0a0a0}.lui-check{cursor:pointer}.lui-check:has(:disabled){cursor:not-allowed;color:#777}.lui-check:hover input:enabled{filter:brightness(1.2)}")
(add-sheet :options
 #j".lui-option.lui-control:active:enabled{transform:none;filter:none}.lui-option.lui-control[aria-selected=false]:hover:enabled{filter:none;background:color-mix(in srgb,var(--lui-accent) 14%,transparent)!important}.lui-option.lui-control[aria-selected=true]:hover:enabled{filter:none;background:var(--lui-accent)!important}")
(add-sheet :cells
 #j".lui-cell:focus-visible{outline:2px solid var(--lui-accent);outline-offset:-2px}")
(add-sheet :splitter
 #j".lui-splitter{opacity:.5}.lui-splitter:hover,.lui-splitter:active,.lui-splitter:focus-visible{opacity:1}.lui-splitter:focus-visible{outline:1px solid var(--lui-accent);outline-offset:-2px}")

(add-sheet :scrollbars
 #j".lui-scrollbar:focus-visible{outline:2px solid var(--lui-accent);outline-offset:-2px}")
