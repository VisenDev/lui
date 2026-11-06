(in-package #:asdf-user)

(defsystem "lui"
  :description "Immediate-mode Common Lisp UI library"
  :version "0.1.0"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "fn")
                             (:file "layout")
                             (:file "frame")
                             (:file "widgets")
                             (:file "app")
                             (:file "interaction")
                             (:file "glass")
                             (:file "motif")
                             (:file "garnet")
                             (:file "terminal"))))
  :in-order-to ((test-op (test-op "lui/tests"))))

(defsystem "lui/debug"
  :depends-on ("lui")
  :components ((:module "src" :components ((:file "debug")))))

(defsystem "lui/demo"
  :depends-on ("lui/debug")
  :serial t
  :components ((:module "examples"
                :serial t
                :components ((:file "seven-model")
                             (:file "seven-circles")
                             (:file "seven-cells")
                             (:file "seven")
                             (:file "demo")))))

(defsystem "lui/tests"
  :depends-on ("lui/demo")
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "debug")
                             (:file "core")
                             (:file "widgets")
                             (:file "interaction")
                             (:file "gallery")
                             (:file "seven-model")
                             (:file "seven-circles")
                             (:file "seven-cells")
                             (:file "seven"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :lui.tests.debug :run-tests)
             (uiop:symbol-call :lui.tests :run-tests)
             (uiop:symbol-call :lui.tests.widgets :run-tests)
             (uiop:symbol-call :lui.tests.interaction :run-tests)
             (uiop:symbol-call :lui.tests.gallery :run-tests)
             (uiop:symbol-call :lui.tests.seven.model :run-tests)
             (uiop:symbol-call :lui.tests.seven :run-tests)
             (uiop:symbol-call :lui.tests.seven.circles :run-tests)
             (uiop:symbol-call :lui.tests.seven.cells :run-tests)))

(defsystem "lui/native"
  :depends-on ("lui" "cffi" "zpb-ttf")
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "font")
                             (:file "draw")))))

(defsystem "lui/x11"
  :depends-on ("lui/gl")
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
                :serial t
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
