(defpackage #:lui.cocoa
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font
        #:lui.draw)
  (:export #:run-cocoa))
(in-package #:lui.cocoa)

(sb-alien:define-alien-type object sb-alien:system-area-pointer)
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

(defmacro message (result receiver selector &rest arguments)
  (let ((function
          (if (and (eq result 'rect) (member :x86-64 *features*))
              "objc_msgSend_stret"
              "objc_msgSend")))
    `(sb-alien:alien-funcall
      (sb-alien:extern-alien ,function
        (function ,result object object
                  ,@(loop :for (type value) :on arguments :by #'cddr
                          :collect type)))
      ,receiver (selector ,selector)
      ,@(loop :for (type value) :on arguments :by #'cddr
              :collect value))))

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

(defstruct cocoa-app window view renderer context error)
(defvar *app*)

(fn ns-string ((text string))
  (message object (objc-class "NSString") "stringWithUTF8String:"
           sb-alien:c-string text))

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

(sb-alien:define-alien-callable flipped sb-alien:char
    ((view object) (selector object))
  (when view selector)
  1)

(sb-alien:define-alien-callable draw-view sb-alien:void
    ((view object) (selector object) (dirty rect))
  (when view selector dirty)
  ;; Never unwind a Lisp error through an Objective-C callback.
  (handler-case
      (let ((graphics (objc-class "NSGraphicsContext")))
        (message sb-alien:void graphics "saveGraphicsState")
        (unwind-protect
             (paint-frame (cocoa-app-renderer *app*)
                          (cocoa-app-context *app*))
          (message sb-alien:void graphics "restoreGraphicsState")))
    (error (condition) (setf (cocoa-app-error *app*) condition))))

(fn install-method (class (name string) (function symbol) (signature string))
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "class_addMethod"
     (function sb-alien:char object object object sb-alien:c-string))
   class (selector name)
   (sb-alien:alien-sap (sb-alien:alien-callable-function function))
   signature))

(fn view-class ()
  (let ((class (objc-class "LuiDrawingView")))
    (when (zerop (sb-sys:sap-int class))
      (setf class
            (sb-alien:alien-funcall
             (sb-alien:extern-alien "objc_allocateClassPair"
               (function object object sb-alien:c-string
                         sb-alien:unsigned-long))
             (objc-class "NSView") "LuiDrawingView" 0))
      (install-method class "isFlipped" 'flipped "c@:")
      (install-method class "acceptsFirstResponder" 'flipped "c@:")
      (install-method class "drawRect:" 'draw-view
                  "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
      (sb-alien:alien-funcall
       (sb-alien:extern-alien "objc_registerClassPair"
         (function sb-alien:void object))
       class))
    class))

(fn cocoa-event (event view)
  (let* ((type (message sb-alien:unsigned-long event "type"))
         (location (message point event "locationInWindow"))
         (local (message point view "convertPoint:fromView:"
                         point location object (sb-sys:int-sap 0)))
         (x (sb-alien:slot local 'x))
         (y (sb-alien:slot local 'y)))
    (case type
      ((1 2 5 6)
       (make-event :kind (case type (1 :press) (2 :release)
                                   (otherwise :move))
                   :x x :y y))
      (22
       (make-event :kind :scroll :x x :y y
                   :value (- (message sb-alien:double event
                                      "scrollingDeltaY"))))
      (10
       (let* ((code (message sb-alien:unsigned-short event "keyCode"))
              (flags (message sb-alien:unsigned-long event "modifierFlags"))
              (key (cdr (assoc code
                               '((123 . :left) (124 . :right)
                                 (125 . :down) (126 . :up)
                                 (115 . :home) (119 . :end)
                                 (51 . :backspace) (117 . :delete)))))
              (characters (message object event "characters")))
         (cond ((= code 48) (make-event :kind :tab))
               ((= code 36) (make-event :kind :activate))
               ((and (= code 0) (logtest flags #x100000))
                (make-event :kind :key :key :select-all))
               (key (make-event :kind :key :key key))
               ((not (logtest flags #x100000))
                (make-event :kind :text
                            :value (message sb-alien:c-string characters
                                            "UTF8String"))))))
      (otherwise nil))))

(fn run-cocoa ((draw function) &key title width height (interactive t))
  (unless (member :darwin *features*)
    (error "The Cocoa backend requires macOS and SBCL."))
  (unless (sb-thread:main-thread-p)
    (error "Run Cocoa on the main thread."))
  (sb-alien:load-shared-object
   "/System/Library/Frameworks/AppKit.framework/AppKit")
  (let* ((pool (message object
                        (message object (objc-class "NSAutoreleasePool")
                                 "alloc")
                        "init"))
         (application (message object (objc-class "NSApplication")
                               "sharedApplication"))
         (font (open-font))
         (renderer (make-renderer :font font :polygons #'cocoa-polygons
                                  :clip #'cocoa-clip))
         (context (make-context
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width))))
         (*app* (make-cocoa-app :renderer renderer :context context))
         (*unit* 8))
    (unwind-protect
         (progn
           (message sb-alien:char application "setActivationPolicy:"
                    sb-alien:long 0)
           (with-rect (frame 0 0 (or width 720) (or height 520))
             (setf (cocoa-app-window *app*)
                   (message object
                            (message object (objc-class "NSWindow") "alloc")
                            "initWithContentRect:styleMask:backing:defer:"
                            rect frame sb-alien:unsigned-long 15
                            sb-alien:unsigned-long 2 sb-alien:char 0)
                   (cocoa-app-view *app*)
                   (message object (message object (view-class) "alloc")
                            "initWithFrame:" rect frame))
             ;; Native AppKit backdrop material; no desktop capture or pixels.
             (let ((backdrop
                     (message object
                              (message object
                                       (objc-class "NSVisualEffectView")
                                       "alloc")
                              "initWithFrame:" rect frame)))
               (message sb-alien:void backdrop "setMaterial:"
                        sb-alien:long 13)
               (message sb-alien:void backdrop "setBlendingMode:"
                        sb-alien:long 0)
               (message sb-alien:void backdrop "setState:"
                        sb-alien:long 1)
               (message sb-alien:void (cocoa-app-view *app*)
                        "setAutoresizingMask:" sb-alien:unsigned-long 18)
               (message sb-alien:void backdrop "addSubview:"
                        object (cocoa-app-view *app*))
               (message sb-alien:void (cocoa-app-window *app*)
                        "setContentView:" object backdrop)
               (message sb-alien:void backdrop "release")))
           (let ((window (cocoa-app-window *app*)))
             (message sb-alien:void window "setReleasedWhenClosed:"
                      sb-alien:char 0)
             (message sb-alien:void window "setTitle:"
                      object (ns-string title))
             (message sb-alien:void window "setAcceptsMouseMovedEvents:"
                      sb-alien:char 1)
             (message sb-alien:void window "center")
             (message sb-alien:void window "makeKeyAndOrderFront:"
                      object (sb-sys:int-sap 0))
             (message sb-alien:char window "makeFirstResponder:"
                      object (cocoa-app-view *app*)))
           (message sb-alien:void application "finishLaunching")
           (message sb-alien:void application "activateIgnoringOtherApps:"
                    sb-alien:char 1)
           (loop :while
                 (plusp (message sb-alien:char
                                 (cocoa-app-window *app*) "isVisible"))
                 :do
                 (let ((events nil)
                       (view (cocoa-app-view *app*))
                       (frame-pool
                         (message object
                                  (message object
                                           (objc-class "NSAutoreleasePool")
                                           "alloc")
                                  "init")))
                   (unwind-protect
                        (progn
                          (loop :for event :=
                                (message object application
                                         "nextEventMatchingMask:untilDate:inMode:dequeue:"
                                         sb-alien:unsigned-long
                                         #xffffffffffffffff
                                         object
                                         (message object (objc-class "NSDate")
                                                  "distantPast")
                                         object (ns-string "kCFRunLoopDefaultMode")
                                         sb-alien:char 1)
                                :until (zerop (sb-sys:sap-int event))
                                :do
                                (let ((input (cocoa-event event view)))
                                  (when input (push input events))
                                  (unless (= 10 (message sb-alien:unsigned-long
                                                         event "type"))
                                    (message sb-alien:void application
                                             "sendEvent:" object event))))
                          (let* ((bounds (message rect view "bounds"))
                                 (size (sb-alien:slot bounds 'size)))
                            (with-frame
                                (context (sb-alien:slot size 'width)
                                 (sb-alien:slot size 'height)
                                 :events (nreverse events))
                              (funcall draw)))
                          (message sb-alien:void view "setNeedsDisplay:"
                                   sb-alien:char 1)
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
      (close-font font)
      (message sb-alien:void pool "drain"))))

#+darwin
(register-backend :cocoa #'run-cocoa)
