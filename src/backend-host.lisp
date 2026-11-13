(defpackage #:%lui.host
  (:use #:cl #:%lui.fn))
(in-package #:%lui.host)

(fn (wayland-session-p (or null string pathname)) ()
  "Recognize a current Wayland socket without opening a display connection."
  (or (uiop:getenvp "WAYLAND_SOCKET")
      (let ((name (uiop:getenvp "WAYLAND_DISPLAY"))
            (directory (uiop:getenvp "XDG_RUNTIME_DIR")))
        (when (and name (or directory (uiop:absolute-pathname-p name)))
          (handler-case
              (probe-file
               (if (uiop:absolute-pathname-p name) name
                   ;; else
                   (merge-pathnames
                    name (uiop:ensure-directory-pathname directory))))
            (file-error () nil))))))

(fn (preferred-backend (or null symbol)) ()
  "Choose a registered host backend from the environment at run time."
  (let ((backends (lui:available-backends)))
    (flet ((available (name) (when (find name backends) name)))
      (or #+lui-linux-host (and (wayland-session-p) (available :wayland))
          #+(or lui-linux-host lui-bsd-host)
          (and (uiop:getenvp "DISPLAY") (available :x11))
          #+lui-windows-host (available :win32)
          #+(and lui-darwin-host sbcl) (available :cocoa)
          (available :terminal)))))

;; This module is loaded only by the aggregate system. Keep core/custom backend
;; registration independent of host libraries and inspect the restored session.
(setf lui:%*default-backend-function* #'preferred-backend)
