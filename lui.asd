(in-package #:asdf-user)

(defsystem "lui/core"
  :description "Portable dependency-free immediate-mode UI core"
  :version "0.1.0"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "01-fn")
                             (:file "02-conditions")
                             (:file "03-text")
                             (:file "04-layout")
                             (:file "05-frame")
                             (:file "06-widgets")
                             (:file "07-palette")
                             (:file "08-toolkit")
                             (:file "09-lui")
                             (:file "10-interaction")
                             (:file "11-glass")
                             (:file "12-motif")
                             (:file "13-macos")
                             (:file "14-qt")
                             (:file "15-garnet"))))
  :in-order-to ((test-op (test-op "lui/tests"))))

(defsystem "lui"
  :description "LUI core with this host's supported backends"
  :defsystem-depends-on ("trivial-features")
  :version "0.1.0"
  :depends-on ("lui/core" "lui/terminal"
               (:feature (:or :linux (:and :bsd (:not :darwin))) "lui/x11")
               (:feature :linux "lui/wayland")
               (:feature :windows "lui/win32")
               (:feature (:and :darwin :sbcl) "lui/cocoa"))
  :components ((:module "src" :components ((:file "backend-host"))))
  :in-order-to ((test-op (test-op "lui/tests"))))

(defsystem "lui/debug"
  :depends-on ("lui/core")
  :components ((:module "src" :components ((:file "16-debug")))))

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

(defsystem "lui/manual-demo"
  :depends-on ("lui/core")
  :components ((:module "examples" :components ((:file "manual-demo")))))

(defsystem "lui/tests"
  :depends-on ("lui/demo" "lui/manual-demo")
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "support")
                             (:file "debug")
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
             (uiop:symbol-call :%lui.tests.debug :run-tests)
             (uiop:symbol-call :%lui.tests.core :run-tests)
             (uiop:symbol-call :%lui.tests.widgets :run-tests)
             (uiop:symbol-call :%lui.tests.interaction :run-tests)
             (uiop:symbol-call :%lui.tests.gallery :run-tests)
             (uiop:symbol-call :%lui.tests.seven.model :run-tests)
             (uiop:symbol-call :%lui.tests.seven :run-tests)
             (uiop:symbol-call :%lui.tests.seven.circles :run-tests)
             (uiop:symbol-call :%lui.tests.seven.cells :run-tests)))

(defsystem "lui/native"
  :depends-on ("lui/core" "cffi" "zpb-ttf"
                          (:feature (:not :lui-no-font-discovery) "font-discovery"))
  :components ((:module "src"
                :serial t
                :components ((:file "backend-common")
                             (:file "paint-glass")
                             (:file "paint-motif")
                             (:file "paint-macos")
                             (:file "paint-qt")
                             (:file "paint-garnet")))))

(defsystem "lui/pdf"
  :description "Render a layout to a single vector PDF page"
  ;; The cl-pdf writer uses EXTENDED-ASCII-P from its parser system.
  :depends-on ("lui/native" "cl-pdf-parser")
  :components ((:module "src" :components ((:file "backend-pdf"))))
  :in-order-to ((test-op (test-op "lui/pdf/tests"))))

(defsystem "lui/pdf/tests"
  :depends-on ("lui/pdf")
  :components ((:module "tests" :components ((:file "pdf"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :%lui.tests.pdf :run-tests)))

(defsystem "lui/x11"
  :depends-on ("lui/gl")
  :components ((:module "src"
                :components ((:file "backend-x11")))))

(defsystem "lui/gl"
  :depends-on ("lui/native")
  :components ((:module "src"
                :components ((:file "backend-common-gl")))))

(defsystem "lui/wayland"
  :depends-on ("lui/gl")
  :components ((:module "src"
                :components ((:file "backend-wayland")))))

(defsystem "lui/win32"
  :depends-on ("lui/native")
  :components ((:module "src"
                :components ((:file "backend-win32")))))

(defsystem "lui/cocoa"
  :depends-on ("lui/gl")
  :components ((:module "src"
                :components ((:file "backend-cocoa")))))

(defsystem "lui/terminal"
  :depends-on ("lui/core" (:version "uncursed" "0.7.0"))
  :components ((:module "src" :components ((:file "backend-terminal"))))
  :in-order-to ((test-op (test-op "lui/terminal/tests"))))

(defsystem "lui/terminal/tests"
  :depends-on ("lui/terminal" "lui/demo")
  :components ((:module "tests" :components ((:file "terminal-render"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :%lui.tests.terminal-render :run-tests)))

(defsystem "lui/native/tests"
  :depends-on ("lui/native")
  :components ((:module "tests"
                :components ((:file "native"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :%lui.tests.native :run-tests)))
