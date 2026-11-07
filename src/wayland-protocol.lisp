(defpackage #:lui.wayland-protocol
  (:use #:cl #:wayflan-client)
  (:export #:decoration-manager #:decoration #:get-decoration #:set-decoration-mode
           #:fractional-manager #:fractional-scale #:get-fractional-scale
           #:cursor-manager #:cursor-device #:get-cursor-device #:set-cursor-shape))
(in-package #:lui.wayland-protocol)

;; Desktop extensions absent from Wayflan's bundled stable protocols. These
;; descriptions generate Lisp proxy classes and requests, with no native ABI.
(define-interface decoration-manager ()
  (:interface-name "zxdg_decoration_manager_v1"))
(define-interface decoration ()
  (:interface-name "zxdg_toplevel_decoration_v1"))
(define-request (destroy-decoration-manager decoration-manager 0) () (:type :destructor))
(define-request (get-decoration decoration-manager 1)
  ((id :type (:new-id :interface decoration))
   (toplevel :type (:object :interface wayflan-client.xdg-shell:xdg-toplevel))))
(define-request (destroy-decoration decoration 0) () (:type :destructor))
(define-request (set-decoration-mode decoration 1) ((mode :type :uint)))
(define-event (:configure decoration 0) ((mode :type :uint)))

(define-interface fractional-manager ()
  (:interface-name "wp_fractional_scale_manager_v1"))
(define-interface fractional-scale ()
  (:interface-name "wp_fractional_scale_v1"))
(define-request (destroy-fractional-manager fractional-manager 0) () (:type :destructor))
(define-request (get-fractional-scale fractional-manager 1)
  ((id :type (:new-id :interface fractional-scale))
   (surface :type (:object :interface wl-surface))))
(define-request (destroy-fractional-scale fractional-scale 0) () (:type :destructor))
(define-event (:preferred-scale fractional-scale 0) ((scale :type :uint)))

(define-interface cursor-manager ()
  (:interface-name "wp_cursor_shape_manager_v1"))
(define-interface cursor-device ()
  (:interface-name "wp_cursor_shape_device_v1"))
(define-request (destroy-cursor-manager cursor-manager 0) () (:type :destructor))
(define-request (get-cursor-device cursor-manager 1)
  ((id :type (:new-id :interface cursor-device))
   (pointer :type (:object :interface wl-pointer))))
(define-request (destroy-cursor-device cursor-device 0) () (:type :destructor))
(define-request (set-cursor-shape cursor-device 1)
  ((serial :type :uint) (shape :type :uint)))
