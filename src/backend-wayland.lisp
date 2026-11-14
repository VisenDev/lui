(defpackage #:%lui.wayland-protocol
  (:use #:cl #:%lui.fn)
  (:export #:interface #:request #:listen-proxy #:destroy-proxy
           #:connect-display #:disconnect-display #:roundtrip
           #:dispatch-display #:flush-display #:pump-display
           #:call-with-interfaces))
(in-package #:%lui.wayland-protocol)

(cffi:define-foreign-library wayland-client
    (:unix (:or "libwayland-client.so.0" "libwayland-client.so")))
(cffi:use-foreign-library wayland-client)

(cffi:defcstruct wl-message
    (name :pointer)
  (signature :pointer)
  (types :pointer))
(cffi:defcstruct wl-interface
    (name :pointer)
  (version :int)
  (method-count :int)
  (methods :pointer)
  (event-count :int)
  (events :pointer))
(cffi:defcunion argument
    (i :int32) (u :uint32) (s :pointer) (o :pointer) (h :int32))
(cffi:defcstruct pollfd
    (fd :int) (events :short) (revents :short))

(cffi:defcfun ("wl_display_connect" connect-display) :pointer
  "Connect to NAME (a C string pointer), or the default display for a null pointer.
Return a display pointer, or a null pointer when the connection fails."
  (name :pointer))
(cffi:defcfun ("wl_display_disconnect" disconnect-display) :void
  "Disconnect DISPLAY and release its client-side connection resources."
  (display :pointer))
(cffi:defcfun ("wl_display_roundtrip" roundtrip) :int
  "Flush DISPLAY and dispatch callbacks until a synchronization reply arrives.
Return the dispatched event count, or -1 on error; this call blocks."
  (display :pointer))
(cffi:defcfun ("wl_display_dispatch" dispatch-display) :int
  "Read and dispatch DISPLAY callbacks, blocking until events are available.
Return the dispatched event count, or -1 on error."
  (display :pointer))
(cffi:defcfun ("wl_display_flush" flush-display) :int
  "Send buffered DISPLAY requests without blocking for compositor replies.
Return bytes written, or -1 when the connection is not writable or has failed."
  (display :pointer))
(cffi:defcfun ("wl_proxy_destroy" destroy-proxy) :void
  "Release the client-side PROXY without sending a protocol destructor request."
  (proxy :pointer))
(cffi:defcfun ("wl_proxy_add_listener" add-listener) :int
  (proxy :pointer) (listeners :pointer) (data :pointer))
(cffi:defcfun ("wl_proxy_get_version" proxy-version) :uint32
  (proxy :pointer))
(cffi:defcfun ("wl_proxy_marshal_array_flags" marshal) :pointer
  (proxy :pointer) (opcode :uint32) (interface :pointer)
  (version :uint32) (flags :uint32) (args :pointer))

(defvar *interfaces*)
(defvar *interface-storage*)

(fn (allocate-metadata cffi:foreign-pointer) (type &rest options)
  "Allocate foreign protocol metadata and register it for scoped cleanup."
  (let ((pointer (apply #'cffi:foreign-alloc type options)))
    (push pointer *interface-storage*)
    pointer))

(fn (metadata-string cffi:foreign-pointer) ((text string))
  "Allocate a protocol string whose lifetime follows the interface metadata scope."
  (let ((pointer (cffi:foreign-string-alloc text)))
    (push pointer *interface-storage*)
    pointer))

(fn (interface cffi:foreign-pointer) ((name string))
  "Return connection-scoped extension metadata or a core interface pointer by NAME."
  (or (gethash name *interfaces*)
      (cffi:foreign-symbol-pointer
       (concatenate 'string name "_interface"))))

(fn (make-messages cffi:foreign-pointer) ((descriptions list))
  "Build foreign Wayland message descriptors from protocol descriptions."
  (let ((messages
         (allocate-metadata '(:struct wl-message)
                            :count (max 1 (length descriptions)))))
    (loop :for (name signature types) :in descriptions
          :for i :from 0
          :for message :=
          (cffi:mem-aptr messages '(:struct wl-message) i)
          :do
          (let ((type-array
                 (allocate-metadata :pointer
                                    :count (max 1 (length types)))))
            (loop :for type :in types :for j :from 0
                  :do (setf (cffi:mem-aref type-array :pointer j)
                            (if type (interface type)
                                ;; else
                                (cffi:null-pointer))))
            (setf
             (cffi:foreign-slot-value message '(:struct wl-message) 'name)
             (metadata-string name)
             (cffi:foreign-slot-value message '(:struct wl-message)
                                      'signature)
             (metadata-string signature)
             (cffi:foreign-slot-value message '(:struct wl-message) 'types)
             type-array)))
    messages))

(fn (define-interfaces (values)) ((descriptions list))
  "Allocate and connect the interface descriptions needed by Wayland requests."
  ;; Metadata belongs to the active connection, never to a saved Lisp image.
  (dolist (description descriptions)
    (setf (gethash (first description) *interfaces*)
          (allocate-metadata '(:struct wl-interface))))
  (dolist (description descriptions)
    (destructuring-bind (name methods events) description
      (let ((pointer (interface name)))
        (setf
         (cffi:foreign-slot-value pointer '(:struct wl-interface) 'name)
         (metadata-string name)
         (cffi:foreign-slot-value pointer '(:struct wl-interface) 'version)
         1
         (cffi:foreign-slot-value pointer '(:struct wl-interface)
                                  'method-count)
         (length methods)
         (cffi:foreign-slot-value pointer '(:struct wl-interface) 'methods)
         (make-messages methods)
         (cffi:foreign-slot-value pointer '(:struct wl-interface)
                                  'event-count)
         (length events)
         (cffi:foreign-slot-value pointer '(:struct wl-interface) 'events)
         (make-messages events)))))
  (values))

(fn (request cffi:foreign-pointer) (proxy (opcode integer) result-interface
                                    (args list)
                                    &optional version (destroy-p nil))
  "Marshal a Wayland request OPCODE to PROXY with typed argument conses ARGS.
RESULT-INTERFACE names a created proxy type or is NIL. VERSION defaults to the
proxy version; DESTROY-P tells libwayland to destroy the sending proxy."
  (let ((strings nil))
    (unwind-protect
         (cffi:with-foreign-object (arguments '(:union argument)
                                              (max 1 (length args)))
           (loop :for (type . value) :in args :for i :from 0
                 :for pointer :=
                 (cffi:mem-aptr arguments '(:union argument) i)
                 :do
                 (if (eq type :string)
                     (let ((text (cffi:foreign-string-alloc value)))
                       (push text strings)
                       (setf (cffi:mem-ref pointer :pointer) text))

                     ;; else
                     (setf (cffi:mem-ref pointer type) value)))
           (marshal proxy opcode
                    (if result-interface (interface result-interface)
                        ;; else
                        (cffi:null-pointer))
                    (or version (proxy-version proxy))
                    (if destroy-p 1 0) arguments))
      (dolist (string strings) (cffi:foreign-string-free string)))))

(fn (listen-proxy cffi:foreign-pointer) (proxy (callbacks list))
  "Return listener storage; caller frees it after destroying the proxy."
  (let ((listeners (cffi:foreign-alloc :pointer :count (length callbacks))))
    (loop :for callback :in callbacks :for i :from 0
          :do (setf (cffi:mem-aref listeners :pointer i) callback))
    (unless (zerop (add-listener proxy listeners (cffi:null-pointer)))
      (cffi:foreign-free listeners)
      (error '%lui.conditions:backend-error
             :backend :wayland
             :operation :listen-proxy
             :format-control "Cannot install Wayland listener."))
    listeners))

(fn (pump-display (values)) (display &optional (timeout 16))
  "Flush requests, wait briefly for readable input, and dispatch pending callbacks.
Signal an error when the display disconnects or its read/dispatch operation fails."

  ;; Drain queued callbacks until Wayland allows a prepared read.
  (loop :while
        (not (zerop
              (cffi:foreign-funcall "wl_display_prepare_read"
                                    :pointer display :int)))
        :do
        (setf timeout 0)

        (when (minusp (cffi:foreign-funcall "wl_display_dispatch_pending"
                                            :pointer display :int))
          (error '%lui.conditions:backend-error
                 :backend :wayland
                 :operation :pump-display
                 :format-control "Wayland display disconnected.")))

  ;; Flush requests before polling; an unread reservation must be cancelled.
  (flush-display display)
  (cffi:with-foreign-object (poll '(:struct pollfd))
    (cffi:with-foreign-slots ((fd events revents) poll (:struct pollfd))
      (setf fd (cffi:foreign-funcall "wl_display_get_fd"
                                     :pointer display :int)
            events 1 revents 0)
      (let ((ready (cffi:foreign-funcall "poll" :pointer poll
                                         :ulong 1 :int timeout :int)))
        (if (and (plusp ready) (logtest revents 1))
            (when (minusp
                   (cffi:foreign-funcall "wl_display_read_events"
                                         :pointer display :int))
              (error '%lui.conditions:backend-error
                     :backend :wayland
                     :operation :pump-display
                     :format-control "Wayland read failed."))

            ;; else
            (cffi:foreign-funcall "wl_display_cancel_read"
                                  :pointer display :void))))
    ;; Dispatch newly read callbacks and report connection failures.
    (when (minusp (cffi:foreign-funcall "wl_display_dispatch_pending"
                                        :pointer display :int))
      (error '%lui.conditions:backend-error
             :backend :wayland
             :operation :pump-display
             :format-control "Wayland dispatch failed.")))
  (values))

;; XDG shell and optional desktop extensions. See NOTICE for licenses.
(defparameter *xdg-interfaces*
  '(("xdg_wm_base"
     (("destroy" "" ())
      ("create_positioner" "n" ("xdg_positioner"))
      ("get_xdg_surface" "no" ("xdg_surface" "wl_surface"))
      ("pong" "u" (nil)))
     (("ping" "u" (nil))))
    ("xdg_positioner"
     (("destroy" "" ())
      ("set_size" "ii" (nil nil))
      ("set_anchor_rect" "iiii" (nil nil nil nil))
      ("set_anchor" "u" (nil))
      ("set_gravity" "u" (nil))
      ("set_constraint_adjustment" "u" (nil))
      ("set_offset" "ii" (nil nil)))
     ())
    ("xdg_surface"
     (("destroy" "" ())
      ("get_toplevel" "n" ("xdg_toplevel"))
      ("get_popup" "n?oo" ("xdg_popup" "xdg_surface" "xdg_positioner"))
      ("set_window_geometry" "iiii" (nil nil nil nil))
      ("ack_configure" "u" (nil)))
     (("configure" "u" (nil))))
    ("xdg_toplevel"
     (("destroy" "" ())
      ("set_parent" "?o" ("xdg_toplevel"))
      ("set_title" "s" (nil))
      ("set_app_id" "s" (nil))
      ("show_window_menu" "ouii" ("wl_seat" nil nil nil))
      ("move" "ou" ("wl_seat" nil))
      ("resize" "ouu" ("wl_seat" nil nil))
      ("set_max_size" "ii" (nil nil))
      ("set_min_size" "ii" (nil nil))
      ("set_maximized" "" ())
      ("unset_maximized" "" ())
      ("set_fullscreen" "?o" ("wl_output"))
      ("unset_fullscreen" "" ())
      ("set_minimized" "" ()))
     (("configure" "iia" (nil nil nil))
      ("close" "" ())))
    ("xdg_popup"
     (("destroy" "" ())
      ("grab" "ou" ("wl_seat" nil)))
     (("configure" "iiii" (nil nil nil nil))
      ("popup_done" "" ())))
    ("zxdg_decoration_manager_v1"
     (("destroy" "" ())
      ("get_toplevel_decoration" "no"
                                 ("zxdg_toplevel_decoration_v1"
                                  "xdg_toplevel")))
     ())
    ("zxdg_toplevel_decoration_v1"
     (("destroy" "" ())
      ("set_mode" "u" (nil))
      ("unset_mode" "" ()))
     (("configure" "u" (nil))))
    ("wp_viewporter"
     (("destroy" "" ())
      ("get_viewport" "no" ("wp_viewport" "wl_surface")))
     ())
    ("wp_viewport"
     (("destroy" "" ())
      ("set_source" "ffff" (nil nil nil nil))
      ("set_destination" "ii" (nil nil)))
     ())
    ("wp_fractional_scale_manager_v1"
     (("destroy" "" ())
      ("get_fractional_scale" "no" ("wp_fractional_scale_v1" "wl_surface")))
     ())
    ("wp_fractional_scale_v1"
     (("destroy" "" ()))
     (("preferred_scale" "u" (nil))))
    ("wp_cursor_shape_manager_v1"
     (("destroy" "" ())
      ("get_pointer" "no" ("wp_cursor_shape_device_v1" "wl_pointer"))
      ;; Tablet tools are not bound by this backend; leave that object untyped.
      ("get_tablet_tool_v2" "no" ("wp_cursor_shape_device_v1" nil)))
     ())
    ("wp_cursor_shape_device_v1"
     (("destroy" "" ()) ("set_shape" "uu" (nil nil)))
     ())))

(fn (call-with-interfaces t) ((function function))
  "Call FUNCTION with fresh dynamically scoped Wayland extension metadata.
Free all interface allocations on return or error; proxies must not outlive it."
  (let ((*interfaces* (make-hash-table :test 'equal))
        (*interface-storage* nil))
    (unwind-protect
         (progn
           (define-interfaces *xdg-interfaces*)
           (funcall function))
      (dolist (pointer *interface-storage*)
        (cffi:foreign-free pointer)))))

(defpackage #:%lui.wayland
  (:use #:cl #:%lui.fn #:lui #:%lui.layout #:%lui.frame #:lui.font
        #:lui.draw #:%lui.gl #:%lui.wayland-protocol)
  (:export #:run-wayland))
(in-package #:%lui.wayland)

(cffi:define-foreign-library wayland-egl
    (:unix (:or "libwayland-egl.so.1" "libwayland-egl.so")))
(cffi:define-foreign-library xkbcommon
    (:unix (:or "libxkbcommon.so.0" "libxkbcommon.so")))
(cffi:use-foreign-library wayland-egl)
(cffi:use-foreign-library xkbcommon)

(cffi:define-foreign-library wayland-cursor
    (:unix (:or "libwayland-cursor.so.0" "libwayland-cursor.so")))
(cffi:defcstruct themed-cursor
    (count :uint) (images :pointer) (name :pointer))
(cffi:defcstruct cursor-image
    (width :uint) (height :uint) (hotspot-x :uint) (hotspot-y :uint)
    (delay :uint))

(defstruct wl-window
  display registry compositor shell seat surface xdg toplevel
  decoration-manager decoration decoration-mode pending-decoration-mode
  viewporter viewport fractional-manager fractional-object
  cursor-manager cursor-device cursor-serial cursor-kind
  shm cursor-theme cursor-theme-attempted-p cursor-surface
  (compositor-version 1 :type integer)
  (scale120 120 :type integer) (buffer-scale 1 :type integer)
  applied-buffer-scale
  (viewport-width 0 :type integer) (viewport-height 0 :type integer)
  clipboard-manager clipboard-device clipboard-source clipboard-listener
  clipboard-text clipboard-serial
  pointer keyboard native gpu font xkb-context keymap key-state
  (seat-version 1 :type integer)
  ;; Older keyboards have no repeat_info; use conventional client defaults.
  (repeat-rate 25 :type integer) (repeat-delay 600 :type integer)
  repeat-code repeat-at
  (width 720 :type integer) (height 520 :type integer)
  (x 0 :type real) (y 0 :type real) (buttons 0 :type integer)
  (configured-p nil :type boolean) (quit-p nil :type boolean)
  (events nil :type list) (listeners nil :type list))
(defvar *window*)

(fn (attach-listener (values)) (proxy (callbacks list))
  "Attach callback pointers to a proxy for the active window."
  (push (listen-proxy proxy callbacks) (wl-window-listeners *window*))
  (values))

(defmacro callback (name arguments &body body)
  "Define a Wayland callback using the protocol ABI and declared arguments."
  `(cffi:defcallback ,name :void
     ((data :pointer) (proxy :pointer) ,@arguments)
     (declare (ignore data) (ignorable proxy))
     ,@body))

(fn (queue-input (values)) ((kind symbol) &rest options)
  "Append a translated input event to the active Wayland window's queue."
  (push (apply #'make-event :kind kind options)
        (wl-window-events *window*))
  (values))

(fn (release-clipboard-source (values)) ((window wl-window))
  "Destroy WINDOW's current clipboard data source and clear its ownership."
  (when (wl-window-clipboard-source window)
    (request (wl-window-clipboard-source window) 1 nil nil nil t)
    (setf (wl-window-clipboard-source window) nil
          (wl-window-clipboard-text window) nil))
  (when (wl-window-clipboard-listener window)
    (cffi:foreign-free (wl-window-clipboard-listener window))
    (setf (wl-window-clipboard-listener window) nil))
  (values))

(fn (write-clipboard-fd (values)) ((text string) (fd integer))
  "Write UTF-8 clipboard text to a compositor-supplied descriptor and close it."
  (unwind-protect
       (cffi:with-foreign-string ((bytes byte-size) text :encoding :utf-8)
         (let ((size (1- byte-size))
               (offset 0))
           (loop :while (< offset size)
                 :for count :=
                 (cffi:foreign-funcall "write" :int fd
                                       :pointer (cffi:inc-pointer bytes
                                                                  offset)
                                       :size (- size offset) :long)
                 :do (cond ((plusp count) (incf offset count))
                           ((and (minusp count)
                                 (= 4 (cffi:mem-ref
                                       (cffi:foreign-funcall
                                        "__errno_location" :pointer) :int))))
                           (t (return nil))))))
    (cffi:foreign-funcall "close" :int fd :int))
  (values))

(callback clipboard-target ((mime :pointer))
          (declare (ignore mime)))
(callback clipboard-send ((mime :string) (fd :int))
          ;; FD belongs to this event; close it even for an unsupported target.
          (handler-case
              (write-clipboard-fd
               (if (and (wl-window-clipboard-source *window*)
                        (cffi:pointer-eq proxy
                                         (wl-window-clipboard-source
                                          *window*))
                        (member mime '("text/plain;charset=utf-8"
                                       "text/plain")
                                :test #'string=))
                   (or (wl-window-clipboard-text *window*) "")
                   ;; else
                   "") fd)
            (error () nil)))
(callback clipboard-cancelled ()
          (when (and (wl-window-clipboard-source *window*)
                     (cffi:pointer-eq proxy (wl-window-clipboard-source
                                             *window*)))
            (release-clipboard-source *window*)))

(callback clipboard-offer ((offer :pointer))
          ;; This backend publishes text. Unrequested incoming offers need no transfer.
          (request offer 2 nil nil nil t))
(callback clipboard-enter
          ((serial :uint32) (surface :pointer) (x :int32) (y :int32)
           (offer :pointer))
          (declare (ignore serial surface x y offer)))
(callback clipboard-leave ())
(callback clipboard-motion ((time :uint32) (x :int32) (y :int32))
          (declare (ignore time x y)))
(callback clipboard-drop ())
(callback clipboard-selection ((offer :pointer))
          (declare (ignore offer)))

(fn (create-clipboard-device (values)) ((window wl-window))
  "Create WINDOW's clipboard device when the compositor supports it."
  ;; Core protocol v1 is enough for clipboard ownership on older compositors.
  (when (and (wl-window-clipboard-manager window) (wl-window-seat window))
    (let ((device
           (request (wl-window-clipboard-manager window) 1 "wl_data_device"
                    (list (cons :pointer (cffi:null-pointer))
                          (cons :pointer (wl-window-seat window))) 1)))
      (setf (wl-window-clipboard-device window) device)
      (attach-listener device
                       (list (cffi:callback clipboard-offer)
                             (cffi:callback clipboard-enter)
                             (cffi:callback clipboard-leave)
                             (cffi:callback clipboard-motion)
                             (cffi:callback clipboard-drop)
                             (cffi:callback clipboard-selection)))))
  (values))

(fn (copy-clipboard (or null integer)) ((window wl-window) (text string))
  "Publish TEXT as the current Wayland clipboard selection when available."
  (when (and (wl-window-clipboard-device window)
             (wl-window-clipboard-serial window))
    (release-clipboard-source window)
    (let ((source
           (request (wl-window-clipboard-manager window) 0 "wl_data_source"
                    (list (cons :pointer (cffi:null-pointer))) 1)))
      (setf (wl-window-clipboard-source window) source
            (wl-window-clipboard-text window) (copy-seq text)
            (wl-window-clipboard-listener window)
            (listen-proxy source (list (cffi:callback clipboard-target)
                                       (cffi:callback clipboard-send)
                                       (cffi:callback clipboard-cancelled))))
      (dolist (mime '("text/plain;charset=utf-8" "text/plain"))
        (request source 0 nil (list (cons :string mime))))
      (request (wl-window-clipboard-device window) 1 nil
               (list (cons :pointer source)
                     (cons :uint32 (wl-window-clipboard-serial window))))
      (flush-display (wl-window-display window)))))

(fn (cursor-shape integer) ((kind symbol))
  "Map a LUI cursor kind to the Wayland cursor-shape protocol value."
  (case kind (:not-allowed 15) (:pointer 4) (:text 9)
        (:resize-horizontal 26) (:resize-vertical 27) (otherwise 1)))

(fn (cursor-image-for (or null cffi:foreign-pointer)) ((window wl-window)
                                                       (kind symbol))
  "Find a theme cursor image for KIND, loading a theme for WINDOW when needed."
  (when (and (wl-window-shm window)
             (not (wl-window-cursor-theme-attempted-p window)))
    (setf (wl-window-cursor-theme-attempted-p window) t)
    (handler-case
        (progn
          (cffi:use-foreign-library wayland-cursor)
          (let ((theme (cffi:foreign-funcall
                        "wl_cursor_theme_load" :pointer (cffi:null-pointer)
                        :int 24 :pointer (wl-window-shm window) :pointer)))
            (unless (cffi:null-pointer-p theme)
              (setf (wl-window-cursor-theme window) theme))))
      (cffi:load-foreign-library-error () nil)))
  (when (wl-window-cursor-theme window)
    (loop :for name :in (case kind
                          (:not-allowed '("not-allowed" "crossed_circle"))
                          (:pointer '("pointer" "hand2"))
                          (:text '("text" "xterm"))
                          (:resize-horizontal
                           '("ew-resize" "sb_h_double_arrow"
                             "h_double_arrow"))
                          (:resize-vertical
                           '("ns-resize" "sb_v_double_arrow"
                             "v_double_arrow"))
                          (otherwise '("default" "left_ptr")))
          :for cursor :=
          (cffi:foreign-funcall "wl_cursor_theme_get_cursor"
                                :pointer (wl-window-cursor-theme window)
                                :string name :pointer)
          :unless (cffi:null-pointer-p cursor)
          :do (return
                (cffi:mem-ref
                 (cffi:foreign-slot-value
                  cursor '(:struct themed-cursor) 'images) :pointer)))))

(fn (set-themed-cursor boolean) ((kind symbol))
  "Apply a cursor theme image and report whether a suitable image was available."
  (let ((image (cursor-image-for *window* kind)))
    (when image
      (unless (wl-window-cursor-surface *window*)
        (setf (wl-window-cursor-surface *window*)
              (request (wl-window-compositor *window*) 0 "wl_surface"
                       (list (cons :pointer (cffi:null-pointer)))))
        (attach-listener
         (wl-window-cursor-surface *window*)
         (list (cffi:callback surface-enter) (cffi:callback surface-leave)
               (cffi:callback preferred-buffer-scale)
               (cffi:callback preferred-buffer-transform))))
      (cffi:with-foreign-slots
          ((width height hotspot-x hotspot-y) image (:struct cursor-image))
        (request (wl-window-pointer *window*) 0 nil
                 (list (cons :uint32 (wl-window-cursor-serial *window*))
                       (cons :pointer (wl-window-cursor-surface *window*))
                       (cons :int32 hotspot-x) (cons :int32 hotspot-y)))
        (request (wl-window-cursor-surface *window*) 1 nil
                 (list (cons :pointer
                             (cffi:foreign-funcall
                              "wl_cursor_image_get_buffer"
                              :pointer image :pointer))
                       (cons :int32 0) (cons :int32 0)))
        (request (wl-window-cursor-surface *window*) 2 nil
                 (list (cons :int32 0) (cons :int32 0)
                       (cons :int32 width) (cons :int32 height)))
        (request (wl-window-cursor-surface *window*) 6 nil nil))
      t)))

(fn (update-cursor symbol) ()
  "Select the native cursor for the current pointer target."
  (when (and (wl-window-pointer *window*)
             (wl-window-cursor-serial *window*))
    (let ((kind (if (boundp '*context*)
                    (%lui.widgets:cursor-at
                     *context* (wl-window-x *window*) (wl-window-y *window*))

                    ;; else
                    :default)))
      (unless (eq kind (wl-window-cursor-kind *window*))
        (when (cond ((wl-window-cursor-device *window*)
                     (request
                      (wl-window-cursor-device *window*) 1 nil
                      (list (cons :uint32 (wl-window-cursor-serial *window*))
                            (cons :uint32 (cursor-shape kind))))
                     t)
                    (t (set-themed-cursor kind)))
          (setf (wl-window-cursor-kind *window*) kind))))))

(fn (create-cursor-device symbol) ()
  "Create cursor-shape support for the active pointer when the protocol is available."
  (when (and (wl-window-cursor-manager *window*)
             (wl-window-pointer *window*)
             (null (wl-window-cursor-device *window*)))
    (setf (wl-window-cursor-device *window*)
          (request (wl-window-cursor-manager *window*) 1
                   "wp_cursor_shape_device_v1"
                   (list (cons :pointer (cffi:null-pointer))
                         (cons :pointer (wl-window-pointer *window*))))
          (wl-window-cursor-kind *window*) nil)
    (update-cursor)))

(fn (cancel-pointer (values)) ((window wl-window))
  "Cancel active pointer input and clear WINDOW's pressed-button state."
  (setf (wl-window-buttons window) 0)
  (push (make-event :kind :cancel :buttons 0) (wl-window-events window))
  (values))

(callback pointer-enter
          ((serial :uint32) (surface :pointer) (x :int32) (y :int32))
          (declare (ignore surface))
          (setf (wl-window-buttons *window*) 0
                (wl-window-cursor-serial *window*) serial
                (wl-window-cursor-kind *window*) nil
                (wl-window-x *window*) (/ x 256.0f0)
                (wl-window-y *window*) (/ y 256.0f0))
          (queue-input :move :buttons 0
                       :x (wl-window-x *window*) :y (wl-window-y *window*))
          (update-cursor))

(callback pointer-leave ((serial :uint32) (surface :pointer))
          (declare (ignore serial surface))
          (cancel-pointer *window*)
          (setf (wl-window-cursor-serial *window*) nil
                (wl-window-cursor-kind *window*) nil
                (wl-window-x *window*) -1 (wl-window-y *window*) -1)
          (queue-input :move :buttons 0 :x -1 :y -1))

(callback pointer-motion ((time :uint32) (x :int32) (y :int32))
          (declare (ignore time))
          (setf (wl-window-x *window*) (/ x 256.0f0)
                (wl-window-y *window*) (/ y 256.0f0))
          (queue-input :move :buttons (wl-window-buttons *window*)
                       :x (wl-window-x *window*) :y (wl-window-y *window*))
          (update-cursor))

(callback pointer-button
          ((serial :uint32) (time :uint32) (button :uint32) (state :uint32))
          (declare (ignore time))
          (setf (wl-window-clipboard-serial *window*) serial)
          (when (member button '(#x110 #x111))
            (let ((bit (if (= button #x111) 2 1)))
              (setf (wl-window-buttons *window*)
                    (if (zerop state) (logandc2 (wl-window-buttons *window*)
                                                bit)

                        ;; else
                        (logior (wl-window-buttons *window*) bit))))
            (queue-input (if (zerop state) :release :press)
                         :button (if (= button #x111) :secondary :primary)
                         :buttons (wl-window-buttons *window*)
                         :x (wl-window-x *window*) :y (wl-window-y
                                                       *window*))))

(callback pointer-axis ((time :uint32) (axis :uint32) (value :int32))
          (declare (ignore time))
          (when (zerop axis)
            (queue-input :scroll :x (wl-window-x *window*)
                         :y (wl-window-y *window*) :value (/ value 256.0f0))))

(fn (stop-key-repeat (values)) ((window wl-window))
  "Clear WINDOW's repeating key and repeat deadline."
  (setf (wl-window-repeat-code window) nil
        (wl-window-repeat-at window) nil)
  (values))

(fn (start-key-repeat (or null real)) ((code integer)
                                       &optional ((now real)
                                                  (get-internal-real-time)))
  "Schedule key repeat for CODE using the compositor's rate and delay."
  (when (and (plusp (wl-window-repeat-rate *window*))
             (wl-window-keymap *window*)
             (plusp (cffi:foreign-funcall
                     "xkb_keymap_key_repeats"
                     :pointer (wl-window-keymap *window*)
                     :uint (+ code 8) :int)))
    (setf (wl-window-repeat-code *window*) code
          (wl-window-repeat-at *window*)
          (+ now (* (/ internal-time-units-per-second 1000)
                    (wl-window-repeat-delay *window*))))))

(fn (release-keymap (values)) ((window wl-window))
  "Release WINDOW's XKB state, keymap, and context."
  (stop-key-repeat window)
  (when (wl-window-key-state window)
    (cffi:foreign-funcall "xkb_state_unref"
                          :pointer (wl-window-key-state window) :void)
    (setf (wl-window-key-state window) nil))
  (when (wl-window-keymap window)
    (cffi:foreign-funcall "xkb_keymap_unref"
                          :pointer (wl-window-keymap window) :void)
    (setf (wl-window-keymap window) nil))
  (values))

(callback keyboard-map ((format :uint32) (fd :int32) (size :uint32))
          (unwind-protect
               (when (and (= format 1) (< 0 size (* 16 1024 1024)))
                 (cffi:with-foreign-object (text :char (1+ size))
                   (loop :with offset := 0
                         :for count :=
                         (when (< offset size)
                           (cffi:foreign-funcall
                            "read" :int fd
                            :pointer (cffi:inc-pointer text offset)
                            :size (- size offset) :long))
                         :while (< offset size)
                         :do (when (<= count 0) (return))
                         (incf offset count)
                         :finally
                         (setf (cffi:mem-aref text :char size) 0)
                         (release-keymap *window*)
                         (let ((keymap
                                (cffi:foreign-funcall
                                 "xkb_keymap_new_from_string"
                                 :pointer (wl-window-xkb-context *window*)
                                 :pointer text :uint 1 :uint 0 :pointer)))
                           (unless (cffi:null-pointer-p keymap)
                             (setf (wl-window-keymap *window*) keymap
                                   (wl-window-key-state *window*)
                                   (cffi:foreign-funcall "xkb_state_new"
                                                         :pointer keymap
                                                         :pointer)))))))
            (cffi:foreign-funcall "close" :int fd :int)))

(callback keyboard-enter
          ((serial :uint32) (surface :pointer) (keys :pointer))
          (declare (ignore serial surface keys))
          (stop-key-repeat *window*))
(callback keyboard-leave ((serial :uint32) (surface :pointer))
          (declare (ignore serial surface))
          (stop-key-repeat *window*)
          (cancel-pointer *window*))

(fn (modifier-active-p boolean) (state (name string))
  "Test whether a named XKB modifier is active in STATE."
  (plusp (cffi:foreign-funcall
          "xkb_state_mod_name_is_active" :pointer state
          :string name :uint 8 :int)))

(fn (editor-command symbol) (state (symbol integer) context)
  "Resolve a modified key symbol to the platform's editor command."
  (when (and context (%lui.widgets:text-field-focused-p context))
    (cffi:with-foreign-object (name :char 64)
      (let ((length (cffi:foreign-funcall
                     "xkb_keysym_get_name" :uint symbol
                     :pointer name :size 64 :int)))
        (when (< 0 length 64)
          (%lui.widgets:readline-key
           (cffi:foreign-string-to-lisp name :count length)
           :control (modifier-active-p state "Control")
           :alt (modifier-active-p state "Mod1")
           :shift (modifier-active-p state "Shift")))))))

(fn (emit-key-input (values)) ((code integer))
  "Translate CODE through the active XKB state and enqueue keyboard or text input."
  (when (wl-window-key-state *window*)

    ;; Predict focus from queued pointer input before interpreting XKB keys.
    (let* ((context
            (when (and (boundp '*context*) *context*)
              (pending-input-context
               *context* (wl-window-events *window*)
               (wl-window-width *window*) (wl-window-height *window*))))
           (state (wl-window-key-state *window*))
           (key (+ code 8))
           (symbol (cffi:foreign-funcall "xkb_state_key_get_one_sym"
                                         :pointer state :uint key :uint))
           (editor (editor-command state symbol context))
           (command
            (cdr (assoc symbol
                        '((#xff51 . :left) (#xff53 . :right)
                          (#xff52 . :up) (#xff54 . :down)
                          (#xff50 . :home) (#xff57 . :end)
                          (#xff08 . :backspace) (#xffff . :delete)
                          (#xff1b . :escape))))))

      ;; Shared editor commands and activation take precedence over text.
      (cond ((and (member symbol '(#x63 #x43))
                  (modifier-active-p state "Control")
                  (not (modifier-active-p state "Mod1")))
             (queue-input :key :key :copy))
            (editor (queue-input :key :key editor))
            ((member symbol '(#xff09 #xfe20))
             (queue-input :tab :key
                          (when (or (= symbol #xfe20)
                                    (modifier-active-p state "Shift"))
                            :backward)))
            ((and (= symbol 32) context
                  (%lui.widgets:activation-focused-p context))
             (queue-input :activate))
            ((= symbol #xff0d) (queue-input :activate))
            (command (queue-input :key :key command))
            (t

             ;; Only the remaining keys use XKB's UTF-8 text conversion.
             (cffi:with-foreign-object (text :char 64)
               (let ((length
                      (cffi:foreign-funcall "xkb_state_key_get_utf8"
                                            :pointer state :uint key
                                            :pointer text :size 64 :int)))
                 (when (< 0 length 64)
                   (queue-input
                    :text :value
                    (cffi:foreign-string-to-lisp text :count length
                                                 :encoding :utf-8)))))))))
  (values))

(callback keyboard-key
          ((serial :uint32) (time :uint32) (code :uint32) (pressed :uint32))
          (declare (ignore time))
          (setf (wl-window-clipboard-serial *window*) serial)
          (case pressed
            (0
             (when (eql code (wl-window-repeat-code *window*))
               (stop-key-repeat *window*)))
            (1
             (emit-key-input code)
             (start-key-repeat code)) (otherwise nil)))

(callback keyboard-repeat-info ((rate :int32) (delay :int32))
          (setf (wl-window-repeat-rate *window*) (max 0 rate)
                (wl-window-repeat-delay *window*) (max 0 delay))
          (let ((code (wl-window-repeat-code *window*)))
            (stop-key-repeat *window*)
            (when code (start-key-repeat code))))

(fn (repeat-input (or null real)) (&optional ((now real)
                                              (get-internal-real-time)))
  "Emit a due repeated key and advance its repeat deadline."
  (when (and (wl-window-repeat-code *window*)
             (wl-window-repeat-at *window*)
             (plusp (wl-window-repeat-rate *window*)))
    (let ((interval (/ internal-time-units-per-second
                       (wl-window-repeat-rate *window*))))
      ;; Bound catch-up after a stalled frame so one held key cannot flood UI.
      (loop :repeat 8
            :while (<= (wl-window-repeat-at *window*) now)
            :do (emit-key-input (wl-window-repeat-code *window*))
            (incf (wl-window-repeat-at *window*) interval))
      (when (<= (wl-window-repeat-at *window*) now)
        (setf (wl-window-repeat-at *window*) (+ now interval))))))

(callback keyboard-modifiers
          ((serial :uint32) (depressed :uint32) (latched :uint32)
           (locked :uint32) (group :uint32))
          (declare (ignore serial))
          (when (wl-window-key-state *window*)
            (cffi:foreign-funcall "xkb_state_update_mask"
                                  :pointer (wl-window-key-state *window*)
                                  :uint depressed :uint latched :uint locked
                                  :uint 0 :uint 0 :uint group :uint)))

(callback seat-name ((name :string))
          (declare (ignore name)))

(fn (release-keyboard (values)) ((window wl-window))
  "Stop repetition and release the window's keyboard and keymap resources."
  (release-keymap window)
  (when (wl-window-keyboard window)
    (cancel-pointer window)
    (if (>= (wl-window-seat-version window) 3)
        (request (wl-window-keyboard window) 0 nil nil nil t)
        ;; else
        (destroy-proxy (wl-window-keyboard window)))
    (setf (wl-window-keyboard window) nil))
  (values))

(callback seat-capabilities ((capabilities :uint32))
          (when (and (not (logtest capabilities 1))
                     (or (wl-window-pointer *window*)
                         (plusp (wl-window-buttons *window*))))
            (cancel-pointer *window*))
          (unless (logtest capabilities 1)
            (when (wl-window-cursor-device *window*)
              (request (wl-window-cursor-device *window*) 0 nil nil nil t)
              (setf (wl-window-cursor-device *window*) nil))
            (when (wl-window-pointer *window*)
              (if (>= (wl-window-seat-version *window*) 3)
                  (request (wl-window-pointer *window*) 1 nil nil nil t)
                  ;; else
                  (destroy-proxy (wl-window-pointer *window*)))
              (setf (wl-window-pointer *window*) nil))
            (setf (wl-window-cursor-serial *window*) nil
                  (wl-window-cursor-kind *window*) nil))
          (unless (logtest capabilities 2) (release-keyboard *window*))
          (when (and (logtest capabilities 1) (null (wl-window-pointer
                                                     *window*)))
            (let ((pointer
                   (request proxy 0 "wl_pointer"
                            (list (cons :pointer (cffi:null-pointer)))
                            (wl-window-seat-version *window*))))
              (setf (wl-window-pointer *window*) pointer)
              (attach-listener
               pointer (list (cffi:callback pointer-enter)
                             (cffi:callback pointer-leave)
                             (cffi:callback pointer-motion)
                             (cffi:callback pointer-button)
                             (cffi:callback pointer-axis)))
              (create-cursor-device)))
          (when (and (logtest capabilities 2) (null (wl-window-keyboard
                                                     *window*)))
            (let ((keyboard
                   (request proxy 1 "wl_keyboard"
                            (list (cons :pointer (cffi:null-pointer)))
                            (wl-window-seat-version *window*))))
              (setf (wl-window-keyboard *window*) keyboard)
              (attach-listener
               keyboard (list (cffi:callback keyboard-map)
                              (cffi:callback keyboard-enter)
                              (cffi:callback keyboard-leave)
                              (cffi:callback keyboard-key)
                              (cffi:callback keyboard-modifiers)
                              (cffi:callback keyboard-repeat-info))))))

(callback shell-ping ((serial :uint32))
          (request proxy 3 nil (list (cons :uint32 serial))))

(callback registry-global
          ((name :uint32) (interface-name :string) (version :uint32))
          (when (member interface-name
                        '("wl_compositor" "xdg_wm_base" "wl_seat" "wl_shm"
                          "wl_data_device_manager"
                          "zxdg_decoration_manager_v1" "wp_viewporter"
                          "wp_fractional_scale_manager_v1"
                          "wp_cursor_shape_manager_v1")
                        :test #'string=)
            (let* ((version
                    (min version
                         (cond ((string= interface-name "wl_compositor") 6)
                               ((string= interface-name "wl_seat") 4)
                               (t 1))))
                   (object
                    (request proxy 0 interface-name
                             (list (cons :uint32 name)
                                   (cons :string interface-name)
                                   (cons :uint32 version)
                                   (cons :pointer (cffi:null-pointer)))
                             version)))
              (cond ((string= interface-name "wl_compositor")
                     (setf (wl-window-compositor *window*) object
                           (wl-window-compositor-version *window*) version))
                    ((string= interface-name "wl_data_device_manager")
                     (setf (wl-window-clipboard-manager *window*) object))
                    ((string= interface-name "wl_shm")
                     (setf (wl-window-shm *window*) object))
                    ((string= interface-name "wp_cursor_shape_manager_v1")
                     (setf (wl-window-cursor-manager *window*) object)
                     (create-cursor-device))
                    ((string= interface-name "wp_viewporter")
                     (setf (wl-window-viewporter *window*) object))
                    ((string= interface-name "wp_fractional_scale_manager_v1")
                     (setf (wl-window-fractional-manager *window*) object))
                    ((string= interface-name "zxdg_decoration_manager_v1")
                     (setf (wl-window-decoration-manager *window*) object))
                    ((string= interface-name "xdg_wm_base")
                     (setf (wl-window-shell *window*) object)
                     (attach-listener object (list (cffi:callback
                                                    shell-ping))))
                    (t
                     (setf (wl-window-seat *window*) object
                           (wl-window-seat-version *window*) version)
                     (attach-listener
                      object (list (cffi:callback seat-capabilities)
                                   (cffi:callback seat-name))))))))

(callback registry-remove ((name :uint32))
          (declare (ignore name)))

(callback surface-enter ((output :pointer))
          (declare (ignore output)))

(callback surface-leave ((output :pointer))
          (declare (ignore output)))

(callback preferred-buffer-scale ((scale :int32))
          (when (and (plusp scale)
                     (or (null (wl-window-surface *window*))
                         (cffi:pointer-eq proxy (wl-window-surface
                                                 *window*))))
            (setf (wl-window-buffer-scale *window*) scale)))

(callback preferred-buffer-transform ((transform :uint32))
          ;; Upright buffers remain valid; the compositor handles output transforms.
          (declare (ignore transform)))

(callback fractional-preferred-scale ((scale :uint32))
          (when (plusp scale) (setf (wl-window-scale120 *window*) scale)))

(fn (create-scaling (values)) ((window wl-window))
  "Create optional viewport and fractional-scale protocol objects for WINDOW."
  (attach-listener
   (wl-window-surface window)
   (list (cffi:callback surface-enter) (cffi:callback surface-leave)
         (cffi:callback preferred-buffer-scale)
         (cffi:callback preferred-buffer-transform)))
  (when (and (wl-window-viewporter window)
             (wl-window-fractional-manager window))
    (setf (wl-window-viewport window)
          (request (wl-window-viewporter window) 1 "wp_viewport"
                   (list (cons :pointer (cffi:null-pointer))
                         (cons :pointer (wl-window-surface window))))
          (wl-window-fractional-object window)
          (request (wl-window-fractional-manager window) 1
                   "wp_fractional_scale_v1"
                   (list (cons :pointer (cffi:null-pointer))
                         (cons :pointer (wl-window-surface window)))))
    (attach-listener (wl-window-fractional-object window)
                     (list (cffi:callback fractional-preferred-scale))))
  (values))

(fn (surface-scale real) ((window wl-window))
  "Return WINDOW's effective fractional or integer surface scale."
  (if (wl-window-fractional-object window)
      (/ (wl-window-scale120 window) 120)
      ;; else
      (wl-window-buffer-scale window)))

(fn (framebuffer-size (values integer integer)) ((window wl-window))
  "Return WINDOW's scaled framebuffer width and height in pixels."
  (let ((scale (surface-scale window)))
    (values (max 1 (ceiling (* (wl-window-width window) scale)))
            (max 1 (ceiling (* (wl-window-height window) scale))))))

(fn (sync-window-size (values)) ((window wl-window))
  "Apply configured logical size and scaling to the surface and EGL window."
  (let ((gpu (wl-window-gpu window))
        (width (wl-window-width window))
        (height (wl-window-height window))
        (buffer-scale (if (wl-window-viewport window)
                          1
                          ;; else
                          (wl-window-buffer-scale window))))
    (when (and (>= (wl-window-compositor-version window) 3)
               (not (eql buffer-scale
                         (wl-window-applied-buffer-scale window))))
      (request (wl-window-surface window) 8 nil
               (list (cons :int32 buffer-scale)))
      (setf (wl-window-applied-buffer-scale window) buffer-scale))
    (when (and (wl-window-viewport window)
               (or (/= width (wl-window-viewport-width window))
                   (/= height (wl-window-viewport-height window))))
      (request (wl-window-viewport window) 2 nil
               (list (cons :int32 width) (cons :int32 height)))
      (setf (wl-window-viewport-width window) width
            (wl-window-viewport-height window) height))
    (setf (gpu-logical-width gpu) width (gpu-logical-height gpu) height)
    (multiple-value-bind (pixel-width pixel-height) (framebuffer-size window)
      (unless (and (= pixel-width (gpu-width gpu))
                   (= pixel-height (gpu-height gpu)))
        (setf (gpu-width gpu) pixel-width (gpu-height gpu) pixel-height)
        (cffi:foreign-funcall
         "wl_egl_window_resize" :pointer (wl-window-native window)
         :int pixel-width :int pixel-height :int 0 :int 0 :void))))
  (values))

(callback decoration-configure ((mode :uint32))
          ;; This pending state belongs to the next xdg_surface.configure sequence.
          (setf (wl-window-pending-decoration-mode *window*) mode))

(fn (accept-surface-configure (eql t)) ((window wl-window))
  "Apply the latest surface configuration and mark WINDOW ready to render."
  (when (wl-window-pending-decoration-mode window)
    (setf (wl-window-decoration-mode window)
          (wl-window-pending-decoration-mode window)
          (wl-window-pending-decoration-mode window) nil))
  (setf (wl-window-configured-p window) t))

(callback surface-configure ((serial :uint32))
          (request proxy 4 nil (list (cons :uint32 serial)))
          (accept-surface-configure *window*))

(fn (create-decoration (or null cffi:foreign-pointer)) ((window wl-window))
  "Request server-side decorations when the compositor supports them."
  (when (wl-window-decoration-manager window)
    (setf (wl-window-decoration window)
          (request (wl-window-decoration-manager window) 1
                   "zxdg_toplevel_decoration_v1"
                   (list (cons :pointer (cffi:null-pointer))
                         (cons :pointer (wl-window-toplevel window)))))
    (attach-listener (wl-window-decoration window)
                     (list (cffi:callback decoration-configure)))
    ;; Version 1 requires this before the first surface commit or buffer.
    (request (wl-window-decoration window) 1 nil (list (cons :uint32 2)))))

(fn (destroy-extension (or null cffi:foreign-pointer)) (proxy)
  "Destroy a non-NIL extension proxy through its protocol destructor."
  (when proxy (request proxy 0 nil nil nil t)))

(fn (release-extensions (values)) ((window wl-window))
  "Release WINDOW's optional decoration, scaling, clipboard, and cursor resources."
  (release-clipboard-source window)
  (dolist (proxy (list (wl-window-clipboard-device window)
                       (wl-window-clipboard-manager window)))
    (when proxy (destroy-proxy proxy)))
  (setf (wl-window-clipboard-device window) nil
        (wl-window-clipboard-manager window) nil
        (wl-window-clipboard-serial window) nil)
  ;; Children disappear before their xdg_toplevel/wl_surface and managers.
  (dolist (proxy (list (wl-window-cursor-surface window)
                       (wl-window-cursor-device window)
                       (wl-window-decoration window)
                       (wl-window-viewport window)
                       (wl-window-fractional-object window)))
    (destroy-extension proxy))
  (when (wl-window-cursor-theme window)
    (cffi:foreign-funcall "wl_cursor_theme_destroy"
                          :pointer (wl-window-cursor-theme window) :void))
  (setf (wl-window-cursor-surface window) nil
        (wl-window-cursor-theme window) nil
        (wl-window-cursor-device window) nil
        (wl-window-decoration window) nil
        (wl-window-viewport window) nil
        (wl-window-fractional-object window) nil)
  (dolist (proxy (list (wl-window-cursor-manager window)
                       (wl-window-decoration-manager window)
                       (wl-window-viewporter window)
                       (wl-window-fractional-manager window)))
    (destroy-extension proxy))
  (setf (wl-window-cursor-manager window) nil
        (wl-window-decoration-manager window) nil
        (wl-window-viewporter window) nil
        (wl-window-fractional-manager window) nil)
  (values))

(callback toplevel-configure
          ((width :int32) (height :int32) (states :pointer))
          (declare (ignore states))
          (when (and (plusp width) (plusp height))
            (setf (wl-window-width *window*) width
                  (wl-window-height *window*) height)))

(callback toplevel-close ()
          (setf (wl-window-quit-p *window*) t))

(fn (wait-wayland (values)) (display (context context) events)
  "Wait for display input, key repetition, or the context's next frame deadline."
  (loop :for delay := (%lui.frame:frame-wait context events)
        :for repeat := (wl-window-repeat-at *window*)
        :when repeat
        :do (let ((ticks (- repeat (get-internal-real-time))))
              (setf delay
                    (min delay (/ (max 0 ticks)
                                  internal-time-units-per-second))))
        :do (pump-display display (ceiling (* 1000 delay)))
        :until (or (zerop delay) (wl-window-events *window*)
                   (wl-window-quit-p *window*)
                   (/= (wl-window-width *window*) (context-width context))
                   (/= (wl-window-height *window*) (context-height context))))
  (%lui.frame:limit-frame-rate context)
  (values))

(fn (close-wayland-window (values)) (display)
  "Release the active window's graphics, input, proxies, listeners, and display."
  (when (wl-window-gpu *window*)
    (close-gpu (wl-window-gpu *window*)))
  (when (wl-window-native *window*)
    (cffi:foreign-funcall "wl_egl_window_destroy"
                          :pointer (wl-window-native *window*) :void))
  (when (wl-window-font *window*)
    (close-font (wl-window-font *window*)))
  (release-keymap *window*)
  (when (wl-window-xkb-context *window*)
    (cffi:foreign-funcall "xkb_context_unref"
                          :pointer (wl-window-xkb-context *window*)
                          :void))
  (release-extensions *window*)
  (dolist (proxy (list (wl-window-keyboard *window*)
                       (wl-window-pointer *window*)
                       (wl-window-seat *window*)
                       (wl-window-shm *window*)
                       (wl-window-toplevel *window*)
                       (wl-window-xdg *window*)
                       (wl-window-surface *window*)
                       (wl-window-shell *window*)
                       (wl-window-compositor *window*)
                       (wl-window-registry *window*)))
    (when proxy (destroy-proxy proxy)))
  (dolist (listener (wl-window-listeners *window*))
    (cffi:foreign-free listener))
  (disconnect-display display)
  (values))

(fn (run-wayland-frames (or null context))
    ((draw function) display interactive)
  "Render frames and process input until the active Wayland window closes."
  (let* ((gpu (wl-window-gpu *window*))
         (renderer (gpu-renderer gpu))
         (context
          (%make-render-context
           renderer :copy
           (when (wl-window-clipboard-device *window*)
             (let ((window *window*))
               (lambda (text) (copy-clipboard window text))))))
         (*context* context))
    (loop :with events
          :until (wl-window-quit-p *window*)
          :do
          (sync-window-size *window*)
          (repeat-input)
          (setf events (nreverse (shiftf (wl-window-events *window*)
                                         nil)))
          (with-frame
              (context (wl-window-width *window*)
                       (wl-window-height *window*)
                       :events events)
            (funcall draw))
          (update-cursor)
          (begin-gpu-frame gpu)
          (%paint-frame renderer context)
          (present-gpu gpu)
          (unless interactive (return context))
          (wait-wayland display context events))))

(fn (discover-wayland-globals (values)) (display)
  "Bind registry globals and require the compositor and desktop shell protocols."
  (setf (wl-window-xkb-context *window*)
        (cffi:foreign-funcall "xkb_context_new" :uint 0 :pointer)
        (wl-window-registry *window*)
        (request display 1 "wl_registry"
                 (list (cons :pointer (cffi:null-pointer))) 1))
  (attach-listener (wl-window-registry *window*)
                   (list (cffi:callback registry-global)
                         (cffi:callback registry-remove)))
  (when (minusp (roundtrip display))
    (error '%lui.conditions:backend-error
           :backend :wayland
           :operation :run-window
           :format-control "Wayland registry roundtrip failed."))
  (create-clipboard-device *window*)
  (unless (and (wl-window-compositor *window*)
               (wl-window-shell *window*))
    (error '%lui.conditions:backend-error
           :backend :wayland
           :operation :run-window
           :format-control "Wayland compositor requires wl_compositor and xdg_wm_base."))
  (values))

(fn (configure-wayland-surface (values)) (display title)
  "Create the desktop surface, install listeners, and wait for initial configuration."
  (setf (wl-window-surface *window*)
        (request (wl-window-compositor *window*) 0 "wl_surface"
                 (list (cons :pointer (cffi:null-pointer))))
        (wl-window-xdg *window*)
        (request (wl-window-shell *window*) 2 "xdg_surface"
                 (list (cons :pointer (cffi:null-pointer))
                       (cons :pointer (wl-window-surface *window*))))
        (wl-window-toplevel *window*)
        (request (wl-window-xdg *window*) 1 "xdg_toplevel"
                 (list (cons :pointer (cffi:null-pointer)))))
  (attach-listener (wl-window-xdg *window*)
                   (list (cffi:callback surface-configure)))
  (attach-listener (wl-window-toplevel *window*)
                   (list (cffi:callback toplevel-configure)
                         (cffi:callback toplevel-close)))
  (create-decoration *window*)
  (create-scaling *window*)
  (request (wl-window-toplevel *window*) 2 nil
           (list (cons :string title)))
  (request (wl-window-toplevel *window*) 3 nil
           (list (cons :string "lui")))
  (request (wl-window-surface *window*) 6 nil nil)
  (loop :until (wl-window-configured-p *window*)
        :do (when (minusp (dispatch-display display))
              (error '%lui.conditions:backend-error
                     :backend :wayland
                     :operation :run-window
                     :format-control "Wayland initial configure failed.")))
  (values))

(fn (run-window (or null context)) ((draw function) &key title width height
                                                      (interactive t))
  "Run one Wayland application window and release its native resources on exit."
  (let* ((display (connect-display (cffi:null-pointer)))
         (*window* (make-wl-window :display display
                                   :width (or width 720)
                                   :height (or height 520)))
         (*unit* 8))
    (when (cffi:null-pointer-p display)
      (error '%lui.conditions:backend-error
             :backend :wayland
             :operation :run-window
             :format-control "Cannot connect to the Wayland display."))
    (unwind-protect
         (progn
           (discover-wayland-globals display)
           (configure-wayland-surface display title)
           (multiple-value-bind (pixel-width pixel-height)
               (framebuffer-size *window*)
             (setf (wl-window-native *window*)
                   (cffi:foreign-funcall
                    "wl_egl_window_create"
                    :pointer (wl-window-surface *window*)
                    :int pixel-width :int pixel-height :pointer)
                   (wl-window-font *window*) (open-font)
                   (wl-window-gpu *window*)
                   (open-gpu display (wl-window-native *window*)
                             (wl-window-font *window*)
                             pixel-width pixel-height)))
           (run-wayland-frames draw display interactive))
      (close-wayland-window display))))

(fn (run-wayland (or null context)) ((draw function) &key title width height
                                                       (interactive t))
  "Run DRAW in a Wayland window using EGL and the shared OpenGL renderer.
TITLE, WIDTH, and HEIGHT configure the window; INTERACTIVE NIL draws one frame.
Own and release the display, protocol metadata, input devices, and GPU resources."
  (call-with-interfaces
   (lambda ()
     (run-window draw :title title :width width :height height
                 :interactive interactive))))

(register-backend :wayland #'run-wayland)
