(defpackage #:lui.cocoa
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font #:lui.draw)
  (:export #:run-cocoa))
(in-package #:lui.cocoa)

(sb-alien:define-alien-type object sb-alien:system-area-pointer)
;; Objective-C BOOL is signed char on x86-64 and bool on arm64. Both occupy
;; one byte; use numeric 0/1 rather than SBCL's word-sized BOOLEAN alien type.
(sb-alien:define-alien-type utf8-string
    (sb-alien:c-string :external-format :utf-8))
(sb-alien:define-alien-type objc-bool
    #+arm64 sb-alien:unsigned-char #-arm64 sb-alien:char)
(sb-alien:define-alien-type point
    (sb-alien:struct point (x sb-alien:double) (y sb-alien:double)))
(sb-alien:define-alien-type size
    (sb-alien:struct size (width sb-alien:double) (height sb-alien:double)))
(sb-alien:define-alien-type rect
    (sb-alien:struct rect (origin point) (size size)))

(defvar *selectors* nil)

(fn (selector sb-sys:system-area-pointer) ((name string))
  "Resolve and cache an Objective-C selector by name."
  (or (and *selectors* (gethash name *selectors*))
      (let ((value
             (sb-alien:alien-funcall
              (sb-alien:extern-alien "sel_registerName"
                                     (function object sb-alien:c-string))
              name)))
        (when *selectors* (setf (gethash name *selectors*) value))
        value)))

(fn (objc-class sb-sys:system-area-pointer) ((name string))
  "Resolve an Objective-C class by name."
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "objc_getClass" (function object sb-alien:c-string))
   name))

(defmacro with-cocoa-float-mode (&body body)
  "Run Cocoa operations with floating-point traps masked and restore all caller modes."
  (let ((modes (gensym "FLOAT-MODES")))
    `(let ((,modes (sb-int:get-floating-point-modes)))
       (unwind-protect
            (sb-int:with-float-traps-masked
                (:invalid :divide-by-zero :overflow :underflow :inexact)
              ,@body)
         ;; Native code may also alter rounding or exception flags. Restore
         ;; the caller's complete mode on errors and nonlocal exits as well.
         (apply #'sb-int:set-floating-point-modes ,modes)))))

(defmacro message (result receiver selector &rest arguments)
  "Send an Objective-C message using the declared return and argument ABI types."
  (assert (evenp (length arguments)) ()
          "MESSAGE requires alternating foreign types and values.")
  (let ((function
         (if (and (eq result 'rect) (member :x86-64 *features*))
             "objc_msgSend_stret"
             "objc_msgSend"))
        (types (loop :for type :in arguments :by #'cddr :collect type))
        (values (loop :for value :in (cdr arguments) :by #'cddr
                      :collect value)))
    ;; SBCL supplies the hidden result pointer for a 32-byte return value.
    ;; Only x86-64's Objective-C dispatch needs the separate stret entry point.
    `(sb-alien:alien-funcall
      (sb-alien:extern-alien ,function
                             (function ,result object object ,@types))
      ,receiver (selector ,selector) ,@values)))

(defmacro with-rect ((name x y width height) &body body)
  "Allocate a temporary native rectangle for the dynamic extent of BODY."
  `(sb-alien:with-alien ((,name rect))
     (setf (sb-alien:slot (sb-alien:slot ,name 'origin) 'x)
           (float ,x 1.0d0) (sb-alien:slot (sb-alien:slot ,name 'origin) 'y)
           (float ,y 1.0d0) (sb-alien:slot (sb-alien:slot ,name 'size) 'width)
           (float ,width 1.0d0)
           (sb-alien:slot (sb-alien:slot ,name 'size) 'height)
           (float ,height 1.0d0))
     ,@body))

(defstruct cocoa-app
  window view renderer context error
  (text-paths (make-hash-table :test 'equal) :type hash-table)
  (shape-paths (make-hash-table :test 'equalp) :type hash-table)
  (pointer-x -1 :type real) (pointer-y -1 :type real)
  (focused-p nil :type boolean)
  (buttons 0 :type integer))
(defvar *app* nil)

(fn (null-object-p boolean) (object)
  "Test whether an Objective-C object pointer is null."
  (zerop (sb-sys:sap-int object)))

(fn (same-object-p boolean) (left right)
  "Compare Objective-C object pointer identities."
  (= (sb-sys:sap-int left) (sb-sys:sap-int right)))

(fn (require-object sb-sys:system-area-pointer) (object (description string))
  "Return a non-null object or signal BACKEND-ERROR describing the failed operation."
  (when (null-object-p object)
    (error 'lui.conditions:backend-error
           :backend :cocoa :operation :require-object
           :format-control "Cannot create Cocoa ~A."
           :format-arguments (list description)))
  object)

(fn (ns-string sb-sys:system-area-pointer) ((text string))
  "Create an autoreleased NSString containing the UTF-8 encoding of TEXT."
  (message object (objc-class "NSString") "stringWithUTF8String:"
           utf8-string text))

(fn (make-path sb-sys:system-area-pointer) ((contours contours))
  "Build an NSBezierPath from filled polygon contours."
  (let ((path (message object (objc-class "NSBezierPath") "bezierPath")))
    (loop :for contour :across contours :do
          (loop :for (x . y) :across contour :for first := t :then nil
                :do
                (sb-alien:with-alien ((p point))
                  (setf (sb-alien:slot p 'x) (float x 1.0d0)
                        (sb-alien:slot p 'y) (float y 1.0d0))
                  (message sb-alien:void path
                           (if first "moveToPoint:" "lineToPoint:") point p)))
          (message sb-alien:void path "closePath"))
    path))

(fn (cocoa-color (values)) ((color string) (alpha real))
  "Set the current AppKit drawing color and alpha."
  (let ((rgba (color-components color alpha)))
    (let ((native-color
           (message object (objc-class "NSColor")
                    "colorWithCalibratedRed:green:blue:alpha:"
                    sb-alien:double (float (aref rgba 0) 1.0d0)
                    sb-alien:double (float (aref rgba 1) 1.0d0)
                    sb-alien:double (float (aref rgba 2) 1.0d0)
                    sb-alien:double (float (aref rgba 3) 1.0d0))))
      (message sb-alien:void native-color "setFill")))
  (values))

(fn (cached-shape sb-sys:system-area-pointer) ((contours contours))
  "Reuse or create a retained native path for CONTOURS."
  (let* ((cache (cocoa-app-shape-paths *app*))
         (cached (gethash contours cache)))
    (or cached
        (let ((path (make-path contours)))
          ;; Keep stable geometry when animation introduces additional shapes.
          (when (< (hash-table-count cache) 2048)
            (setf (gethash contours cache) (message object path "retain" )))
          path))))

(fn (clear-paths hash-table) ((cache hash-table))
  "Release every retained path in CACHE and clear the table."
  (loop :for path :being :the :hash-values :of cache
        :do (message sb-alien:void path "release"))
  (clrhash cache))

(fn (cocoa-polygons (values))
    ((contours contours) (color string) (alpha real))
  "Fill cached polygon contours with the specified color and alpha."
  (cocoa-color color alpha)
  (message sb-alien:void (cached-shape contours) "fill")
  (values))

(fn (cocoa-text (values))
    ((font font) (text string) (x real) (y real) (color string))
  "Paint glyph outlines at a baseline using AppKit paths."
  (let* ((cache (cocoa-app-text-paths *app*))
         (key (list font (font-size font) text)) (path (gethash key cache))
         (graphics (objc-class "NSGraphicsContext")))
    (unless path
      (when (>= (hash-table-count cache) 256) (clear-paths cache))
      (let ((contours (make-array 0 :element-type 'contour :adjustable t
                                  :fill-pointer 0)))
        ;; Reuse the font parser, kerning and geometry of the common renderer.
        (paint-text
         (make-renderer :font font :polygons
                        (lambda (paths ink alpha)
                          (declare (ignore ink alpha))
                          (loop :for path :across paths :do
                                (vector-push-extend path
                                                    contours))))
         text 0 0 color)
        (setf path (message object (make-path contours) "retain")
              (gethash (list font (font-size font) (copy-seq text)) cache)
              path)))
    (message sb-alien:void graphics "saveGraphicsState")
    (unwind-protect
         (let ((transform
                (message object (objc-class "NSAffineTransform")
                         "transform")))
           (message sb-alien:void transform "translateXBy:yBy:"
                    sb-alien:double (float x 1d0)
                    sb-alien:double (float y 1d0))
           (message sb-alien:void transform "concat")
           (cocoa-color color 1)
           (message sb-alien:void path "fill"))
      (message sb-alien:void graphics "restoreGraphicsState")))
  (values))

(fn (cocoa-clip (values)) ((box box))
  "Replace the current AppKit clip with BOX."
  (let ((graphics (objc-class "NSGraphicsContext")))
    (message sb-alien:void graphics "restoreGraphicsState")
    (message sb-alien:void graphics "saveGraphicsState")
    (message sb-alien:void
             (cached-shape (make-array 1 :element-type 'contour
                                       :initial-element (rounded-polygon box
                                                                         0)))
             "addClip"))
  (values))

(fn (callback-true (eql 1)) (view selector)
  "Return Objective-C true for view capability callbacks."
  (declare (ignore view selector))
  1)

(sb-alien:define-alien-callable flipped objc-bool
  ((view object) (selector object))
  (with-cocoa-float-mode (callback-true view selector)))

(fn (draw-cocoa-view t) (view selector dirty)
  "Paint the active LUI frame from the native view's draw callback."
  (declare (ignore selector dirty))
  ;; AppKit may draw before a Lisp frame exists or after the app is disposed.
  ;; Both errors and nonlocal exits must stop inside the native callback.
  (let ((completed nil))
    (unwind-protect
         (prog1
             (handler-case
                 (when (and *app* (cocoa-app-view *app*)
                            (same-object-p view (cocoa-app-view *app*))
                            (context-root (cocoa-app-context *app*)))
                   (let ((graphics (objc-class "NSGraphicsContext")))
                     (message sb-alien:void graphics "saveGraphicsState")
                     (unwind-protect
                          (paint-frame (cocoa-app-renderer *app*)
                                       (cocoa-app-context *app*))
                       (message sb-alien:void graphics
                                "restoreGraphicsState"))))
               (error (condition)
                 (when *app* (setf (cocoa-app-error *app*) condition))))
           (setf completed t))
      (unless completed
        (when *app*
          (setf (cocoa-app-error *app*)
                (make-condition 'simple-error :format-control
                                "Nonlocal exit from a Cocoa draw callback.")))
        (return-from draw-cocoa-view nil)))))

(sb-alien:define-alien-callable draw-view sb-alien:void
  ((view object) (selector object) (dirty rect))
  (with-cocoa-float-mode (draw-cocoa-view view selector dirty)))

(fn (install-method (values))
    (class (name string) (function symbol) (signature string))
  "Add a Lisp callback implementation to an Objective-C class with its ABI signature."
  (when (zerop
         (sb-alien:alien-funcall
          (sb-alien:extern-alien "class_addMethod"
                                 (function objc-bool object object object
                                           sb-alien:c-string))
          class (selector name)
          (sb-alien:alien-sap (sb-alien:alien-callable-function function))
          signature))
    (error 'lui.conditions:backend-error
           :backend :cocoa :operation :install-method
           :format-control "Cannot install Cocoa method ~A."
           :format-arguments (list name)))
  (values))

(fn (view-class sb-sys:system-area-pointer) (&optional accelerated)
  "Find or create the LUI view class for AppKit or accelerated OpenGL drawing."
  (let* ((name (if accelerated "LuiOpenGLView" "LuiDrawingView"))
         (class (objc-class name)))
    (when (null-object-p class)
      (setf class
            (require-object
             (sb-alien:alien-funcall
              (sb-alien:extern-alien "objc_allocateClassPair"
                                     (function object object sb-alien:c-string
                                               sb-alien:unsigned-long))
              (objc-class (if accelerated "NSOpenGLView" "NSView")) name 0)
             "view class"))
      (let ((registered nil)
            (bool-signature (if (member :arm64 *features*) "B@:" "c@:")))
        (unwind-protect
             (progn
               (install-method class "isFlipped" 'flipped bool-signature)
               (install-method class "acceptsFirstResponder" 'flipped
                               bool-signature)
               (unless accelerated
                 (install-method class "drawRect:" 'draw-view
                                 "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"))
               (sb-alien:alien-funcall
                (sb-alien:extern-alien "objc_registerClassPair"
                                       (function sb-alien:void object))
                class)
               (setf registered t))
          (unless registered
            (sb-alien:alien-funcall
             (sb-alien:extern-alien "objc_disposeClassPair"
                                    (function sb-alien:void object))
             class)))))
    class))

(fn (copy-text integer) ((text string))
  "Publish TEXT to the general macOS pasteboard."
  (let ((pasteboard (message object (objc-class "NSPasteboard")
                             "generalPasteboard")))
    (message sb-alien:long pasteboard "clearContents")
    (message objc-bool pasteboard "setString:forType:" object (ns-string text)
             object (ns-string "public.utf8-plain-text"))))

(fn (cocoa-key-input (or null event))
    ((code integer) (flags integer) (characters string) &optional text-p
     (key-name characters) activation-p)
  "Translate a macOS key code and modifiers to LUI keyboard or text input."
  (let* ((command (logtest flags #x100000)) (shift (logtest flags #x20000))
         (command-key
          (when (and text-p (not command))
            (lui.widgets:readline-key
             (case code
               (123 "ArrowLeft") (124 "ArrowRight")
               (51 "Backspace") (otherwise key-name))
             :control (logtest flags #x40000)
             :alt (logtest flags #x80000) :shift shift)))
         (key (cdr (assoc code
                          '((123 . :left) (124 . :right)
                            (125 . :down) (126 . :up)
                            (115 . :home) (119 . :end)
                            (51 . :backspace) (117 . :delete)
                            (53 . :escape))))))
    (cond ((and command (= code 8)) (make-event :kind :key :key :copy))
          (command-key (make-event :kind :key :key command-key))
          ((and text-p command (= code 0))
           (make-event :kind :key :key :select-all))
          (command nil)
          ((= code 48) (make-event :kind :tab :key (when shift :backward)))
          ((and (= code 49) activation-p (not (logtest flags #xc0000)))
           (make-event :kind :activate))
          ((member code '(36 76)) (make-event :kind :activate))
          (key (make-event :kind :key
                           :key (lui.widgets:horizontal-selection-key key
                                                                      shift)))
          ((and (plusp (length characters))
                (every (lambda (char) (>= (char-code char) 32)) characters))
           (make-event :kind :text :value characters)))))

(fn (cursor-selector string) ((kind symbol))
  "Map a LUI cursor kind to an NSCursor class selector."
  (case kind (:not-allowed "operationNotAllowedCursor")
        (:pointer "pointingHandCursor") (:text "IBeamCursor")
        (:resize-horizontal "resizeLeftRightCursor")
        (:resize-vertical "resizeUpDownCursor")
        (otherwise "arrowCursor")))

(fn (update-cursor (values)) ((x real) (y real))
  "Apply the cursor for the widget under X/Y in the active context."
  (when *app*
    (setf (cocoa-app-pointer-x *app*) x (cocoa-app-pointer-y *app*) y))
  (when (and *app* (cocoa-app-context *app*)
             (<= 0 x) (< x (context-width (cocoa-app-context *app*)))
             (<= 0 y) (< y (context-height (cocoa-app-context *app*))))
    (let ((cursor
           (message object (objc-class "NSCursor")
                    (cursor-selector
                     (lui.widgets:cursor-at (cocoa-app-context *app*) x y)))))
      (message sb-alien:void cursor "set")))
  (values))

(fn (input-for-window-p boolean) ((type integer) window target)
  "Test whether a native event is applicable to the LUI window."
  (and (member type '(1 2 3 4 5 6 7 8 9 10 22))
       (not (null-object-p target)) (same-object-p window target)))

(fn (cocoa-pointer-buttons integer) ((type integer) (previous integer))
  "Update the primary button mask from a native mouse event type."
  ;; Dragged/down events retain their historical state even if the current
  ;; physical button was released before AppKit's queue was drained.
  (case type
    ((1 6) (logior previous 1)) (2 (logand previous (lognot 1)))
    ((3 7) (logior previous 2)) (4 (logand previous (lognot 2)))
    (5 0) (otherwise previous)))

(fn (cocoa-focus-event (or null event)) ((focused boolean))
  "Return cancellation input when focus is lost and reset pointer state."
  (let ((lost (and (cocoa-app-focused-p *app*) (not focused))))
    (setf (cocoa-app-focused-p *app*) focused)
    (when lost
      (setf (cocoa-app-buttons *app*) 0)
      (make-event :kind :cancel :buttons 0))))

(fn (cocoa-key-event (or null event)) (event)
  "Read native key strings and translate them using the active input context."
  (let ((characters (message object event "characters")))
    (return-from cocoa-key-event
      (cocoa-key-input (message sb-alien:unsigned-short event "keyCode")
                       (message sb-alien:unsigned-long event "modifierFlags")
                       (if (null-object-p characters) ""
                           (or (message utf8-string characters "UTF8String") ""))
                       (and *app* (lui.widgets:text-field-focused-p
                                   (cocoa-app-context *app*)))
                       (let ((name (message object event "charactersIgnoringModifiers")))
                         (if (null-object-p name) ""
                             (or (message utf8-string name "UTF8String") "")))
                       (and *app* (lui.widgets:activation-focused-p
                                   (cocoa-app-context *app*)))))))

(fn (cocoa-event (or null event)) (event view)
  "Translate a native event into LUI coordinates and input semantics."
  (let ((type (message sb-alien:unsigned-long event "type"))
        (window (message object view "window")))
    ;; NSApplication's queue also contains menu, application, and other-window
    ;; events. Query location/characters only for events belonging to this view.
    (unless (input-for-window-p type (message object event "window") window)
      (return-from cocoa-event nil))
    (when (= type 9)
      (setf (cocoa-app-pointer-x *app*) -1 (cocoa-app-pointer-y *app*) -1)
      (return-from cocoa-event
        (when (zerop (cocoa-app-buttons *app*))
          (make-event :kind :move :x -1 :y -1 :buttons 0))))
    (when (= type 10)
      (return-from cocoa-event (cocoa-key-event event)))
    (let* ((location (message point event "locationInWindow"))
           (local (message point view "convertPoint:fromView:"
                           point location object (sb-sys:int-sap 0)))
           (x (sb-alien:slot local 'x)) (y (sb-alien:slot local 'y)))
      (update-cursor x y)
      (if (= type 22)
          (let ((lines-p (zerop (message objc-bool event
                                         "hasPreciseScrollingDeltas")))
                (delta (message sb-alien:double event "scrollingDeltaY")))
            (make-event :kind :scroll :x x :y y
                        :scroll-mode (if lines-p :smooth :immediate)
                        :value (* (- delta) (if lines-p (units 2) 1))))
          (make-event :kind (case type ((1 3) :press) ((2 4) :release)
                                  (otherwise :move))
                      :button (if (member type '(3 4 7))
                                  :secondary :primary)
                      :buttons
                      (setf (cocoa-app-buttons *app*)
                            (cocoa-pointer-buttons
                             type (cocoa-app-buttons *app*)))
                      :x x :y y)))))

(fn (poll-cocoa-events (vector event)) (application view)
  "Drain native events, dispatch AppKit messages, and collect translated LUI input."
  (let ((events nil))
    (loop :for event :=
          (message object application
                   "nextEventMatchingMask:untilDate:inMode:dequeue:"
                   sb-alien:unsigned-long #xffffffffffffffff
                   object (message object (objc-class "NSDate") "distantPast")
                   object
                   (sb-alien:extern-alien "NSDefaultRunLoopMode" object)
                   objc-bool 1)
          :until (null-object-p event)
          :do (let ((input (cocoa-event event view)))
                (when input (push input events))
                ;; Preserve unhandled application shortcuts and native chrome.
                (unless (and input
                             (= 10 (message sb-alien:unsigned-long
                                            event "type")))
                  (message sb-alien:void application "sendEvent:"
                           object event))))
    ;; Sample physical state only after draining historical drag events.
    (when (and (logbitp 0 (cocoa-app-buttons *app*))
               (not (logbitp 0 (message sb-alien:unsigned-long
                                        (objc-class "NSEvent")
                                        "pressedMouseButtons"))))
      (setf (cocoa-app-buttons *app*) 0)
      (push (make-event :kind :cancel :buttons 0) events))
    (let ((cancel
           (cocoa-focus-event
            (and (not (zerop (message objc-bool application "isActive")))
                 (not (zerop (message objc-bool (cocoa-app-window *app*)
                                      "isKeyWindow")))))))
      (when cancel (push cancel events)))
    (coerce (nreverse events) '(vector event))))

(fn (install-pointer-tracking (values)) (view frame)
  "Install native tracking so the view receives pointer movement and exit events."
  (let ((tracking
         (require-object
          (message object
                   (message object (objc-class "NSTrackingArea") "alloc")
                   "initWithRect:options:owner:userInfo:"
                   rect frame sb-alien:unsigned-long #x221
                   object view object (sb-sys:int-sap 0))
          "pointer tracking area")))
    ;; Enter/exit + active-in-key-window + visible-rect tracks resizes natively.
    (unwind-protect
         (message sb-alien:void view "addTrackingArea:" object tracking)
      (message sb-alien:void tracking "release")))
  (values))

(defvar *stacktrace-method* nil)
(defvar *stacktrace-placeholder* nil)
(defvar *stacktrace-reported-p* nil)

(sb-alien:define-alien-callable nonempty-stacktrace object
  ((receiver object) (command object))
  (with-cocoa-float-mode
      (let ((trace
             (sb-alien:alien-funcall
              (sb-alien:sap-alien *stacktrace-method*
                                  (function object object object))
              receiver command)))
        (cond ((and (not (null-object-p trace))
                    (plusp (message sb-alien:unsigned-long trace "count")))
               trace)
              (t
               (unless *stacktrace-reported-p*
                 (setf *stacktrace-reported-p* t)
                 (handler-case
                     (format *error-output*
                             "~&Cocoa: supplied an empty-stack diagnostic placeholder.~%")
                   (stream-error () nil)))
               *stacktrace-placeholder*)))))

(fn (replace-stacktrace-method sb-sys:system-area-pointer)
    (method implementation)
  "Replace an Objective-C method implementation and return the old pointer."
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "method_setImplementation"
                          (function object object object))
   method implementation))

(fn (call-with-stacktrace-guard t) ((function function))
  "Temporarily guard empty native stack traces during FUNCTION, restoring the method on exit."
  ;; Prevent the AppKit startup crash with menu-bar autohide and empty traces.
  ;; Ported from cc/tools/macos/cocoa-stacktrace.lisp. Keep real traces intact.
  (assert (null *stacktrace-method*))
  (let ((method
         (sb-alien:alien-funcall
          (sb-alien:extern-alien "class_getClassMethod"
                                 (function object object object))
          (objc-class "NSThread") (selector "callStackSymbols")))
        (pool (message object
                       (message object (objc-class "NSAutoreleasePool")
                                "alloc") "init")))
    (unwind-protect
         (let ((placeholder
                (message object (objc-class "NSArray") "arrayWithObject:"
                         object
                         (ns-string "Native trace unavailable across Lisp")))
               (original
                (sb-alien:alien-funcall
                 (sb-alien:extern-alien "method_getImplementation"
                                        (function object object))
                 (require-object method "stacktrace method"))))
           (setf *stacktrace-placeholder*
                 (message object placeholder "retain")
                 *stacktrace-method* original *stacktrace-reported-p* nil)
           (unwind-protect
                (progn
                  (replace-stacktrace-method method
                                             (sb-alien:alien-sap
                                              (sb-alien:alien-callable-function 'nonempty-stacktrace)))
                  (funcall function))
             (replace-stacktrace-method method original)
             (setf *stacktrace-method* nil *stacktrace-placeholder* nil)
             (message sb-alien:void placeholder "release")))
      (message sb-alien:void pool "drain"))))

(fn (pixel-format sb-sys:system-area-pointer) ()
  "Request an accelerated double-buffered OpenGL pixel format."
  ;; Accelerated, double-buffered RGBA with a legacy compatibility profile.
  (cffi:with-foreign-object (attrs :uint 7)
    (loop :for value :in '(73 5 8 24 11 8 0) :for i :from 0
          :do (setf (cffi:mem-aref attrs :uint i) value))
    (message object
             (message object (objc-class "NSOpenGLPixelFormat") "alloc")
             "initWithAttributes:" object attrs)))

(fn (paint-gl-view (values)) (view gl gpu context)
  "Paint and present the active frame through the view's OpenGL context."
  (let* ((bounds (message rect view "bounds"))
         (points (sb-alien:slot bounds 'size))
         (backing (message rect view "convertRectToBacking:" rect bounds))
         (pixels (sb-alien:slot backing 'size)))
    (setf (lui.gl:gpu-logical-width gpu) (sb-alien:slot points 'width)
          (lui.gl:gpu-logical-height gpu) (sb-alien:slot points 'height)
          (lui.gl:gpu-width gpu) (round (sb-alien:slot pixels 'width))
          (lui.gl:gpu-height gpu) (round (sb-alien:slot pixels 'height)))
    (when (and (plusp (lui.gl:gpu-width gpu)) (plusp (lui.gl:gpu-height gpu)))
      (message sb-alien:void gl "makeCurrentContext")
      (lui.gl:begin-gpu-frame gpu)
      (paint-frame (lui.gl:gpu-renderer gpu) context)
      (message sb-alien:void gl "flushBuffer")))
  (values))

(fn (wait-cocoa (values)) (application (context context) events)
  "Wait for native input or the context's next frame deadline."
  (let ((delay (lui.frame::frame-wait context (plusp (length events)))))
    (when (plusp delay)
      ;; Peek so the ordinary event loop still translates and dispatches input.
      (message object application
               "nextEventMatchingMask:untilDate:inMode:dequeue:"
               sb-alien:unsigned-long #xffffffffffffffff
               object (message object (objc-class "NSDate")
                               "dateWithTimeIntervalSinceNow:"
                               sb-alien:double (float delay 1d0))
               object (sb-alien:extern-alien "NSDefaultRunLoopMode" object)
               objc-bool 0)))
  (lui.frame::limit-frame-rate context)
  (values))

(fn (create-cocoa-window-view (values)) (format width height)
  "Create the owned native window and drawing view, attaching pointer tracking."
  (with-rect (frame 0 0 (or width 720) (or height 520))
    (setf (cocoa-app-window *app*)
          (require-object
           (message object (message object (objc-class "NSWindow" ) "alloc" )
                    "initWithContentRect:styleMask:backing:defer:"
                    rect frame sb-alien:unsigned-long 15
                    sb-alien:unsigned-long 2 objc-bool 0)
           "window"))
    ;; CLOSE must never release our owning reference, including when
    ;; later view initialization fails and cleanup closes the window.
    (message sb-alien:void (cocoa-app-window *app*)
             "setReleasedWhenClosed:" objc-bool 0)
    (when (null-object-p format)
      (warn "No accelerated Cocoa pixel format; using AppKit."))
    (let* ((fast (not (null-object-p format)))
           (view (message object (view-class fast) "alloc")))
      (setf (cocoa-app-view *app*)
            (require-object
             (if fast
                 (message object view "initWithFrame:pixelFormat:"
                          rect frame object format)
                 (message object view "initWithFrame:" rect frame))
             "drawing view"))
      (when fast
        (message sb-alien:void (cocoa-app-view *app*)
                 "setWantsBestResolutionOpenGLSurface:" objc-bool 1)))
    (install-pointer-tracking (cocoa-app-view *app*) frame)
    (message sb-alien:void (cocoa-app-window *app*)
             "setContentView:" object (cocoa-app-view *app*)))
  (values))

(fn (run-cocoa-frames context)
    ((draw function) application (context context) gl gpu interactive)
  "Run the Cocoa frame loop with a per-frame autorelease pool and callback error checks."
  (loop :while (not (zerop
                     (message objc-bool (cocoa-app-window *app*)
                              "isVisible")))
        :do
        (let ((view (cocoa-app-view *app*))
              (frame-pool
               (message object
                        (message object
                                 (objc-class "NSAutoreleasePool") "alloc")
                        "init")))
          (unwind-protect
               (let ((events (poll-cocoa-events application view)))
                 (when (zerop (message objc-bool
                                       (cocoa-app-window *app*) "isVisible"))
                   (return context))
                 (let* ((bounds (message rect view "bounds"))
                        (size (sb-alien:slot bounds 'size)))
                   (with-frame
                       (context (sb-alien:slot size 'width)
                                (sb-alien:slot size 'height) :events events)
                     (funcall draw)))
                 (update-cursor (cocoa-app-pointer-x *app*)
                                (cocoa-app-pointer-y *app*))
                 (message sb-alien:void application "updateWindows" )
                 (cond (gpu (paint-gl-view view gl gpu context))
                       (t
                        (message sb-alien:void view
                                 "setNeedsDisplay:" objc-bool 1)
                        (message sb-alien:void view "displayIfNeeded" )))
                 (when (cocoa-app-error *app*)
                   (error (cocoa-app-error *app*)))
                 (when interactive
                   (wait-cocoa application context events)))
            (message sb-alien:void frame-pool "drain")))
        :unless interactive :do (return context)))

(fn (show-cocoa-window (values)) ((title string))
  "Set the window title and focus, then show it at the screen center."
  (let ((window (cocoa-app-window *app*)))
    (message sb-alien:void window "setTitle:" object (ns-string title))
    (message sb-alien:void window "setAcceptsMouseMovedEvents:" objc-bool 1)
    (message sb-alien:void window "center")
    (message sb-alien:void window "makeKeyAndOrderFront:"
             object (sb-sys:int-sap 0))
    (message objc-bool window "makeFirstResponder:"
             object (cocoa-app-view *app*)))
  (values))

(fn (close-cocoa-window (values)) (pool format gl gpu font)
  "Release owned Cocoa and GL resources and drain the outer autorelease pool."
  (when gpu
    (message sb-alien:void gl "makeCurrentContext")
    (lui.gl:close-gpu gpu)
    (message sb-alien:void (objc-class "NSOpenGLContext")
             "clearCurrentContext"))
  (when format (message sb-alien:void format "release"))
  (when (cocoa-app-window *app*)
    (message sb-alien:void (cocoa-app-window *app*) "close")
    (message sb-alien:void (cocoa-app-window *app*) "release"))
  (when (cocoa-app-view *app*)
    (message sb-alien:void (cocoa-app-view *app*) "release"))
  (clear-paths (cocoa-app-text-paths *app*))
  (clear-paths (cocoa-app-shape-paths *app*))
  (when font (close-font font))
  (message sb-alien:void pool "drain")
  (values))

(fn (disable-cocoa-vsync (values)) (gl)
  "Request immediate OpenGL presentation for the Cocoa context."
  (cffi:with-foreign-object (interval :int)
    (setf (cffi:mem-ref interval :int) 0)
    (message sb-alien:void gl "setValues:forParameter:"
             object interval sb-alien:int 222))
  (values))

(fn (run-cocoa-window context)
    ((draw function) &key title width height (interactive t))
  "Run a Cocoa application window and restore native resources on normal or error exit."
  (with-cocoa-float-mode
      (let ((pool (message object
                           (message object (objc-class "NSAutoreleasePool")
                                    "alloc")
                           "init"))
            (application nil) (format nil) (gl nil) (gpu nil) (font nil)
            (renderer nil) (context nil) (*app* (make-cocoa-app)) (*unit* 8))
        (unwind-protect
             (progn
               (setf application (message object (objc-class "NSApplication")
                                          "sharedApplication")
                     font (open-font) renderer
                     (make-renderer :font font
                                    :polygons #'cocoa-polygons
                                    :text #'cocoa-text
                                    :clip #'cocoa-clip)
                     context (make-context :copy #'copy-text :measure
                                           (lambda (widget width)
                                             (measure-widget renderer widget
                                                             width)))
                     (cocoa-app-renderer *app*) renderer
                     (cocoa-app-context *app*) context)
               (message objc-bool application "setActivationPolicy:"
                        sb-alien:long 0)
               (setf format (pixel-format))
               (create-cocoa-window-view format width height)
               (show-cocoa-window title)
               (message sb-alien:void application "finishLaunching")
               (message sb-alien:void application "activateIgnoringOtherApps:"
                        objc-bool 1)
               (unless (null-object-p format)
                 (setf gl (require-object
                           (message object (cocoa-app-view *app*)
                                    "openGLContext")
                           "OpenGL context"))
                 (message sb-alien:void gl "makeCurrentContext")
                 (disable-cocoa-vsync gl)
                 (setf gpu (lui.gl:attach-gpu font 1 1)
                       renderer (lui.gl:gpu-renderer gpu)))
               (run-cocoa-frames draw application context gl gpu interactive))
          (close-cocoa-window pool format gl gpu font)))))

(fn (run-cocoa context) ((draw function) &rest options)
  "Run DRAW in an AppKit window on the SBCL main thread. OPTIONS are the LUI:RUN window keywords."
  (unless (member :darwin *features*)
    (error 'lui.conditions:backend-error :backend :cocoa :operation :run-cocoa
           :format-control "The Cocoa backend requires macOS and SBCL."))
  (unless (sb-thread:main-thread-p)
    (error 'lui.conditions:backend-error :backend :cocoa :operation :run-cocoa
           :format-control "Run Cocoa on the main thread."))
  (with-cocoa-float-mode
      (sb-alien:load-shared-object
       "/System/Library/Frameworks/AppKit.framework/AppKit")
    (let ((*selectors* (make-hash-table :test 'equal)))
      (call-with-stacktrace-guard
       (lambda () (apply #'run-cocoa-window draw options))))))

#+darwin
(register-backend :cocoa #'run-cocoa)
