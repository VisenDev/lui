(defpackage #:lui.wayland-protocol
  (:use #:cl #:lui.fn)
  (:export #:interface #:request #:listen-proxy #:destroy-proxy
           #:connect-display #:disconnect-display #:roundtrip
           #:dispatch-display #:flush-display #:pump-display))
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
  (name :pointer))
(cffi:defcfun ("wl_display_disconnect" disconnect-display) :void
  (display :pointer))
(cffi:defcfun ("wl_display_roundtrip" roundtrip) :int
  (display :pointer))
(cffi:defcfun ("wl_display_dispatch" dispatch-display) :int
  (display :pointer))
(cffi:defcfun ("wl_display_flush" flush-display) :int
  (display :pointer))
(cffi:defcfun ("wl_proxy_destroy" destroy-proxy) :void (proxy :pointer))
(cffi:defcfun ("wl_proxy_add_listener" add-listener) :int
  (proxy :pointer) (listeners :pointer) (data :pointer))
(cffi:defcfun ("wl_proxy_get_version" proxy-version) :uint32
  (proxy :pointer))
(cffi:defcfun ("wl_proxy_marshal_array_flags" marshal) :pointer
  (proxy :pointer) (opcode :uint32) (interface :pointer)
  (version :uint32) (flags :uint32) (args :pointer))

(defvar *interfaces* (make-hash-table :test 'equal))

(fn interface ((name string))
  (or (gethash name *interfaces*)
      (cffi:foreign-symbol-pointer
       (concatenate 'string name "_interface"))))

(fn make-messages ((descriptions list))
  (let ((messages
          (cffi:foreign-alloc '(:struct wl-message)
                              :count (max 1 (length descriptions)))))
    (loop :for (name signature types) :in descriptions
          :for i :from 0
          :for message :=
          (cffi:mem-aptr messages '(:struct wl-message) i)
          :do
          (let ((type-array
                  (cffi:foreign-alloc :pointer
                                      :count (max 1 (length types)))))
            (loop :for type :in types :for j :from 0
                  :do (setf (cffi:mem-aref type-array :pointer j)
                            (if type (interface type)
                                (cffi:null-pointer))))
            (setf
             (cffi:foreign-slot-value message '(:struct wl-message) 'name)
             (cffi:foreign-string-alloc name)
             (cffi:foreign-slot-value message '(:struct wl-message)
                                      'signature)
             (cffi:foreign-string-alloc signature)
             (cffi:foreign-slot-value message '(:struct wl-message) 'types)
             type-array)))
    messages))

(fn define-interfaces ((descriptions list))
  ;; Interface metadata has library lifetime, like system wl_*_interface data.
  (dolist (description descriptions)
    (setf (gethash (first description) *interfaces*)
          (cffi:foreign-alloc '(:struct wl-interface))))
  (dolist (description descriptions)
    (destructuring-bind (name methods events) description
      (let ((pointer (interface name)))
        (setf
         (cffi:foreign-slot-value pointer '(:struct wl-interface) 'name)
         (cffi:foreign-string-alloc name)
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

(fn request (proxy (opcode integer) result-interface (args list)
             &optional version (destroy-p nil))
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

(fn listen-proxy (proxy (callbacks list))
  "Return listener storage; caller frees it after destroying the proxy."
  (let ((listeners (cffi:foreign-alloc :pointer :count (length callbacks))))
    (loop :for callback :in callbacks :for i :from 0
          :do (setf (cffi:mem-aref listeners :pointer i) callback))
    (unless (zerop (add-listener proxy listeners (cffi:null-pointer)))
      (cffi:foreign-free listeners)
      (error "Cannot install Wayland listener."))
    listeners))

(fn pump-display (display)
  (loop :while
        (not (zerop
              (cffi:foreign-funcall "wl_display_prepare_read"
                                    :pointer display :int)))
        :do
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
                                       :ulong 1 :int 16 :int)))
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

;; XDG shell v1 metadata. See NOTICE for the protocol license.
(define-interfaces
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
     ("popup_done" "" ())))))
