(defpackage #:lui.cocoa
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font
        #:lui.draw)
  (:export #:run-cocoa))
(in-package #:lui.cocoa)

(sb-alien:define-alien-type object sb-alien:system-area-pointer)
;; Objective-C BOOL is signed char on x86-64 and bool on arm64. Both occupy
;; one byte; use numeric 0/1 rather than SBCL's word-sized BOOLEAN alien type.
(sb-alien:define-alien-type utf8-string
  (sb-alien:c-string :external-format :utf-8))
(sb-alien:define-alien-type objc-bool
  #+arm64 sb-alien:unsigned-char
  #-arm64 sb-alien:char)
(sb-alien:define-alien-type point
  (sb-alien:struct point
    (x sb-alien:double)
    (y sb-alien:double)))
(sb-alien:define-alien-type size
  (sb-alien:struct size
    (width sb-alien:double)
    (height sb-alien:double)))
(sb-alien:define-alien-type rect
  (sb-alien:struct rect
    (origin point)
    (size size)))

(fn selector ((name string))
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "sel_registerName"
     (function object sb-alien:c-string))
   name))

(fn objc-class ((name string))
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "objc_getClass"
     (function object sb-alien:c-string))
   name))

(defmacro with-cocoa-float-mode (&body body)
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
  (assert (evenp (length arguments)) ()
          "MESSAGE requires alternating foreign types and values.")
  (let ((function
         (if (and (eq result 'rect) (member :x86-64 *features*))
             "objc_msgSend_stret"
             "objc_msgSend"))
        (types (loop :for (type value) :on arguments :by #'cddr
                     :collect type))
        (values (loop :for (type value) :on arguments :by #'cddr
                      :collect value)))
    ;; SBCL supplies the hidden result pointer for a 32-byte return value.
    ;; Only x86-64's Objective-C dispatch needs the separate stret entry point.
    `(sb-alien:alien-funcall
      (sb-alien:extern-alien ,function
        (function ,result object object ,@types))
      ,receiver (selector ,selector) ,@values)))

(defmacro with-rect ((name x y width height) &body body)
  `(sb-alien:with-alien ((,name rect))
     (setf (sb-alien:slot (sb-alien:slot ,name 'origin) 'x)
           (float ,x 1.0d0)
           (sb-alien:slot (sb-alien:slot ,name 'origin) 'y)
           (float ,y 1.0d0)
           (sb-alien:slot (sb-alien:slot ,name 'size) 'width)
           (float ,width 1.0d0)
           (sb-alien:slot (sb-alien:slot ,name 'size) 'height)
           (float ,height 1.0d0))
     ,@body))

(defstruct cocoa-app
  window view renderer context error
  (pointer-x -1 :type real) (pointer-y -1 :type real))
(defvar *app* nil)

(fn null-object-p (object)
  (zerop (sb-sys:sap-int object)))

(fn same-object-p (left right)
  (= (sb-sys:sap-int left) (sb-sys:sap-int right)))

(fn require-object (object (description string))
  (when (null-object-p object)
    (error "Cannot create Cocoa ~A." description))
  object)

(fn ns-string ((text string))
  (message object (objc-class "NSString") "stringWithUTF8String:"
           utf8-string text))

(fn make-path ((contours list))
  (let ((path (message object (objc-class "NSBezierPath") "bezierPath")))
    (dolist (contour contours)
      (loop :for (x . y) :in contour :for first := t :then nil
            :do
            (sb-alien:with-alien ((p point))
              (setf (sb-alien:slot p 'x) (float x 1.0d0)
                    (sb-alien:slot p 'y) (float y 1.0d0))
              (message sb-alien:void path
                       (if first "moveToPoint:" "lineToPoint:")
                       point p)))
      (message sb-alien:void path "closePath"))
    path))

(fn cocoa-polygons ((contours list) (color string) (alpha real))
  (destructuring-bind (red green blue opacity)
      (color-components color alpha)
    (let ((native-color
           (message object (objc-class "NSColor")
                    "colorWithCalibratedRed:green:blue:alpha:"
                    sb-alien:double (float red 1.0d0)
                    sb-alien:double (float green 1.0d0)
                    sb-alien:double (float blue 1.0d0)
                    sb-alien:double (float opacity 1.0d0))))
      (message sb-alien:void native-color "setFill")
      (message sb-alien:void (make-path contours) "fill"))))

(fn cocoa-clip ((box box))
  (let ((graphics (objc-class "NSGraphicsContext")))
    (message sb-alien:void graphics "restoreGraphicsState")
    (message sb-alien:void graphics "saveGraphicsState")
    (message sb-alien:void
             (make-path (list (rounded-polygon box 0))) "addClip")))

(fn callback-true (view selector)
  (declare (ignore view selector))
  1)

(sb-alien:define-alien-callable flipped objc-bool
  ((view object) (selector object))
  (with-cocoa-float-mode
    (callback-true view selector)))

(fn draw-cocoa-view (view selector dirty)
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
                (make-condition 'simple-error
                                :format-control
                                "Nonlocal exit from a Cocoa draw callback.")))
        (return-from draw-cocoa-view nil)))))

(sb-alien:define-alien-callable draw-view sb-alien:void
  ((view object) (selector object) (dirty rect))
  (with-cocoa-float-mode
    (draw-cocoa-view view selector dirty)))

(fn install-method (class (name string) (function symbol) (signature string))
  (when (zerop
         (sb-alien:alien-funcall
          (sb-alien:extern-alien "class_addMethod"
            (function objc-bool object object object sb-alien:c-string))
          class (selector name)
          (sb-alien:alien-sap (sb-alien:alien-callable-function function))
          signature))
    (error "Cannot install Cocoa method ~A." name)))

(fn view-class ()
  (let ((class (objc-class "LuiDrawingView")))
    (when (null-object-p class)
      (setf class
            (require-object
             (sb-alien:alien-funcall
              (sb-alien:extern-alien "objc_allocateClassPair"
                (function object object sb-alien:c-string
                          sb-alien:unsigned-long))
              (objc-class "NSView") "LuiDrawingView" 0)
             "view class"))
      (let ((registered nil)
            (bool-signature (if (member :arm64 *features*) "B@:" "c@:")))
        (unwind-protect
             (progn
               (install-method class "isFlipped" 'flipped bool-signature)
               (install-method class "acceptsFirstResponder" 'flipped
                               bool-signature)
               (install-method class "drawRect:" 'draw-view
                               "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
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

(fn cocoa-key-input ((code integer) (flags integer) (characters string)
                     &optional text-p (key-name characters) activation-p)
  (let* ((command (logtest flags #x100000))
         (shift (logtest flags #x20000))
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
                            (51 . :backspace) (117 . :delete))))))
    (cond (command-key (make-event :kind :key :key command-key))
          ((and text-p command (= code 0))
           (make-event :kind :key :key :select-all))
          (command nil)
          ((= code 48)
           (make-event :kind :tab :key (when shift :backward)))
          ((and (= code 49) activation-p
                (not (logtest flags #xc0000)))
           (make-event :kind :activate))
          ((member code '(36 76)) (make-event :kind :activate))
          (key (make-event :kind :key
                           :key (if shift
                                    (case key
                                      (:left :shift-left)
                                      (:right :shift-right)
                                      (otherwise key))
                                    key)))
          ((and (plusp (length characters))
                (every (lambda (char) (>= (char-code char) 32)) characters))
           (make-event :kind :text :value characters)))))

(fn cursor-selector ((kind symbol))
  (case kind (:not-allowed "operationNotAllowedCursor")
        (:pointer "pointingHandCursor") (:text "IBeamCursor")
        (otherwise "arrowCursor")))

(fn update-cursor ((x real) (y real))
  (when *app*
    (setf (cocoa-app-pointer-x *app*) x (cocoa-app-pointer-y *app*) y))
  (when (and *app* (cocoa-app-context *app*)
             (<= 0 x) (< x (context-width (cocoa-app-context *app*)))
             (<= 0 y) (< y (context-height (cocoa-app-context *app*))))
    (let ((cursor
            (message object (objc-class "NSCursor")
                     (cursor-selector
                      (lui.widgets:cursor-at
                       (cocoa-app-context *app*) x y)))))
      (message sb-alien:void cursor "set"))))

(fn input-for-window-p ((type integer) window target)
  (and (member type '(1 2 5 6 8 9 10 22))
       (not (null-object-p target))
       (same-object-p window target)))

(fn cocoa-event (event view)
  (let ((type (message sb-alien:unsigned-long event "type"))
        (window (message object view "window")))
    ;; NSApplication's queue also contains menu, application, and other-window
    ;; events. Query location/characters only for events belonging to this view.
    (unless (input-for-window-p type (message object event "window") window)
      (return-from cocoa-event nil))
    (when (= type 9)
      (setf (cocoa-app-pointer-x *app*) -1 (cocoa-app-pointer-y *app*) -1)
      (return-from cocoa-event (make-event :kind :move :x -1 :y -1)))
    (when (= type 10)
      (let ((characters (message object event "characters")))
        (return-from cocoa-event
          (cocoa-key-input
           (message sb-alien:unsigned-short event "keyCode")
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
    (let* ((location (message point event "locationInWindow"))
           (local (message point view "convertPoint:fromView:"
                           point location object (sb-sys:int-sap 0)))
           (x (sb-alien:slot local 'x))
           (y (sb-alien:slot local 'y)))
      (update-cursor x y)
      (if (= type 22)
          (make-event :kind :scroll :x x :y y
                      :value (- (message sb-alien:double event
                                         "scrollingDeltaY")))
          (make-event :kind (case type (1 :press) (2 :release)
                                  (otherwise :move))
                      :x x :y y)))))

(fn poll-cocoa-events (application view)
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
    (nreverse events)))

(fn install-pointer-tracking (view frame)
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
      (message sb-alien:void tracking "release"))))

(fn run-cocoa ((draw function) &key title width height (interactive t))
  (unless (member :darwin *features*)
    (error "The Cocoa backend requires macOS and SBCL."))
  (unless (sb-thread:main-thread-p)
    (error "Run Cocoa on the main thread."))
  (with-cocoa-float-mode
    (sb-alien:load-shared-object
     "/System/Library/Frameworks/AppKit.framework/AppKit")
    (let* ((pool (message object
                          (message object (objc-class "NSAutoreleasePool")
                                   "alloc")
                          "init"))
           (application nil)
           (font nil)
           (renderer nil)
           (context nil)
           (*app* (make-cocoa-app))
           (*unit* 8))
      (unwind-protect
           (progn
             (setf application (message object (objc-class "NSApplication")
                                        "sharedApplication")
                   font (open-font)
                   renderer (make-renderer :font font
                                           :polygons #'cocoa-polygons
                                           :clip #'cocoa-clip)
                   context (make-context
                            :measure
                            (lambda (widget width)
                              (measure-widget renderer widget width)))
                   (cocoa-app-renderer *app*) renderer
                   (cocoa-app-context *app*) context)
             (message objc-bool application "setActivationPolicy:"
                      sb-alien:long 0)
             (with-rect (frame 0 0 (or width 720) (or height 520))
               (setf (cocoa-app-window *app*)
                     (require-object
                      (message object
                               (message object (objc-class "NSWindow")
                                        "alloc")
                               "initWithContentRect:styleMask:backing:defer:"
                               rect frame sb-alien:unsigned-long 15
                               sb-alien:unsigned-long 2 objc-bool 0)
                      "window"))
               ;; CLOSE must never release our owning reference, including when
               ;; later view initialization fails and cleanup closes the window.
               (message sb-alien:void (cocoa-app-window *app*)
                        "setReleasedWhenClosed:" objc-bool 0)
               (setf (cocoa-app-view *app*)
                     (require-object
                      (message object (message object (view-class) "alloc")
                               "initWithFrame:" rect frame)
                      "drawing view"))
               (install-pointer-tracking (cocoa-app-view *app*) frame)
               ;; Native AppKit backdrop material; no desktop capture or pixels.
               (let ((backdrop
                      (require-object
                       (message object
                                (message object
                                         (objc-class "NSVisualEffectView")
                                         "alloc")
                                "initWithFrame:" rect frame)
                       "backdrop view")))
                 (unwind-protect
                      (progn
                        (message sb-alien:void backdrop "setMaterial:"
                                 sb-alien:long 13)
                        (message sb-alien:void backdrop "setBlendingMode:"
                                 sb-alien:long 0)
                        (message sb-alien:void backdrop "setState:"
                                 sb-alien:long 1)
                        (message sb-alien:void (cocoa-app-view *app*)
                                 "setAutoresizingMask:"
                                 sb-alien:unsigned-long 18)
                        (message sb-alien:void backdrop "addSubview:"
                                 object (cocoa-app-view *app*))
                        (message sb-alien:void (cocoa-app-window *app*)
                                 "setContentView:" object backdrop))
                   (message sb-alien:void backdrop "release"))))
             (let ((window (cocoa-app-window *app*)))
               (message sb-alien:void window "setTitle:"
                        object (ns-string title))
               (message sb-alien:void window "setAcceptsMouseMovedEvents:"
                        objc-bool 1)
               (message sb-alien:void window "center")
               (message sb-alien:void window "makeKeyAndOrderFront:"
                        object (sb-sys:int-sap 0))
               (message objc-bool window "makeFirstResponder:"
                        object (cocoa-app-view *app*)))
             (message sb-alien:void application "finishLaunching")
             (message sb-alien:void application "activateIgnoringOtherApps:"
                      objc-bool 1)
             (loop :while (not (zerop
                                (message objc-bool (cocoa-app-window *app*)
                                         "isVisible")))
                   :do
                   (let* ((view (cocoa-app-view *app*))
                          (frame-pool
                           (message object
                                    (message object
                                             (objc-class "NSAutoreleasePool")
                                             "alloc")
                                    "init")))
                     (unwind-protect
                          (let ((events (poll-cocoa-events application view)))
                            (when (zerop (message objc-bool
                                                  (cocoa-app-window *app*)
                                                  "isVisible"))
                              (return context))
                            (let* ((bounds (message rect view "bounds"))
                                   (size (sb-alien:slot bounds 'size)))
                              (with-frame
                                  (context (sb-alien:slot size 'width)
                                           (sb-alien:slot size 'height)
                                           :events events)
                                (funcall draw)))
                            (update-cursor (cocoa-app-pointer-x *app*)
                                           (cocoa-app-pointer-y *app*))
                            (message sb-alien:void application
                                     "updateWindows")
                            (message sb-alien:void view "setNeedsDisplay:"
                                     objc-bool 1)
                            (message sb-alien:void view "displayIfNeeded")
                            (when (cocoa-app-error *app*)
                              (error (cocoa-app-error *app*))))
                       (message sb-alien:void frame-pool "drain")))
                   :unless interactive :do (return context)
                   :do (sleep 0.016)))
        (when (cocoa-app-window *app*)
          (message sb-alien:void (cocoa-app-window *app*) "close")
          (message sb-alien:void (cocoa-app-window *app*) "release"))
        (when (cocoa-app-view *app*)
          (message sb-alien:void (cocoa-app-view *app*) "release"))
        (when font (close-font font))
        (message sb-alien:void pool "drain")))))

#+darwin
(register-backend :cocoa #'run-cocoa)
