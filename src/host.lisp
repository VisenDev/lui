(defpackage #:lui.host
  (:use #:cl))
(in-package #:lui.host)

(defun wayland-session-p ()
  "Recognize a current Wayland socket without opening a display connection."
  (or (uiop:getenvp "WAYLAND_SOCKET")
      (let ((name (uiop:getenvp "WAYLAND_DISPLAY"))
            (directory (uiop:getenvp "XDG_RUNTIME_DIR")))
        (when name
          (ignore-errors
            (probe-file
             (if (uiop:absolute-pathname-p name) name
                 (when directory
                   (merge-pathnames name
                                    (uiop:ensure-directory-pathname
                                     directory))))))))))

(defun preferred-backend ()
  "Choose a registered host backend from the environment at run time."
  (let ((backends (lui:available-backends)))
    (flet ((available (name) (when (member name backends) name)))
      (or #+lui-linux-host (and (wayland-session-p) (available :wayland))
          #+(or lui-linux-host lui-bsd-host)
          (and (uiop:getenvp "DISPLAY") (available :x11))
          #+lui-windows-host (available :win32)
          #+(and lui-darwin-host sbcl) (available :cocoa)
          (available :terminal)))))

;; This module is loaded only by the aggregate system. Keep core/custom backend
;; registration independent of host libraries and inspect the restored session.
(setf lui:*default-backend-function* #'preferred-backend)
