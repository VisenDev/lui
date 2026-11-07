(defpackage #:lui.wayland-protocol
  (:use #:cl #:lui.fn)
  (:export #:interface #:request #:listen-proxy #:destroy-proxy
           #:connect-display #:disconnect-display #:roundtrip
           #:dispatch-display #:flush-display #:pump-display
           #:call-with-interfaces))
(in-package #:lui.wayland-protocol)

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
  (let ((pointer (apply #'cffi:foreign-alloc type options)))
    (push pointer *interface-storage*)
    pointer))

(fn (metadata-string cffi:foreign-pointer) ((text string))
  (let ((pointer (cffi:foreign-string-alloc text)))
    (push pointer *interface-storage*)
    pointer))

(fn (interface cffi:foreign-pointer) ((name string))
  "Return connection-scoped extension metadata or a core interface pointer by NAME."
  (or (gethash name *interfaces*)
      (cffi:foreign-symbol-pointer
       (concatenate 'string name "_interface"))))

(fn (make-messages cffi:foreign-pointer) ((descriptions list))
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

(fn (define-interfaces null) ((descriptions list))
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
         (make-messages events))))))

(fn (request cffi:foreign-pointer) (proxy (opcode integer) result-interface (args list)
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
                     (setf (cffi:mem-ref pointer type) value)))
           (marshal proxy opcode
                    (if result-interface (interface result-interface)
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
      (error "Cannot install Wayland listener."))
    listeners))

(fn (pump-display null) (display &optional (timeout 16))
  "Flush requests, wait briefly for readable input, and dispatch pending callbacks.
Signal an error when the display disconnects or its read/dispatch operation fails."
  (loop :while
        (not (zerop
              (cffi:foreign-funcall "wl_display_prepare_read"
                                    :pointer display :int)))
        :do
        (setf timeout 0)
        (when (minusp (cffi:foreign-funcall "wl_display_dispatch_pending"
                                          :pointer display :int))
          (error "Wayland display disconnected.")))
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
              (error "Wayland read failed."))
            (cffi:foreign-funcall "wl_display_cancel_read"
                                  :pointer display :void))))
    (when (minusp (cffi:foreign-funcall "wl_display_dispatch_pending"
                                      :pointer display :int))
      (error "Wayland dispatch failed."))))

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
      ("zxdg_toplevel_decoration_v1" "xdg_toplevel")))
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
