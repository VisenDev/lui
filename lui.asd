(in-package #:asdf-user)

(defsystem "lui"
  :description "Immediate-mode Common Lisp UI library"
  :version "0.1.0"
  :serial t
  :components ((:module "src"
                :components ((:file "fn")
                             (:file "layout")
                             (:file "frame")
                             (:file "widgets")
                             (:file "glass")
                             (:file "motif")
                             (:file "app")
                             (:file "terminal"))))
  :in-order-to ((test-op (test-op "lui/tests"))))

(defsystem "lui/tests"
  :depends-on ("lui")
  :components ((:module "tests"
                :components ((:file "core")
                             (:file "widgets"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :lui.tests :run-tests)
             (uiop:symbol-call :lui.tests.widgets :run-tests)))

(defsystem "lui/native"
  :depends-on ("lui" "cffi" "zpb-ttf")
  :serial t
  :components ((:module "src"
                :components ((:file "font")
                             (:file "draw")))))

(defsystem "lui/x11"
  :depends-on ("lui/native")
  :components ((:module "src"
                :components ((:file "x11")))))

(defsystem "lui/gl"
  :depends-on ("lui/native")
  :components ((:module "src"
                :components ((:file "gl")))))

(defsystem "lui/wayland"
  :depends-on ("lui/gl")
  :serial t
  :components ((:module "src"
                :components ((:file "wayland-protocol")
                             (:file "wayland")))))

(defsystem "lui/win32"
  :depends-on ("lui/native")
  :components ((:module "src"
                :components ((:file "win32")))))

(defsystem "lui/cocoa"
  :depends-on ("lui/native")
  :components ((:module "src"
                :components ((:file "cocoa")))))

(defsystem "lui/terminal"
  :depends-on ("lui" "cffi")
  :components ((:module "src"
                :components ((:file "terminal-io")))))

(defsystem "lui/native/tests"
  :depends-on ("lui/native")
  :components ((:module "tests"
                :components ((:file "native"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :lui.tests.native :run-tests)))
