(in-package #:asdf-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Some implementations report only :UNIX. Detect the OS before dependency
  ;; planning, without loading a portability library into the zero-dep core.
  (let ((os (uiop:operating-system)))
    (when (or (eq os :unix) (and (null os) (member :unix *features*)))
      (setf os (ignore-errors
                 (intern (string-upcase
                          (string-trim '(#\Space #\Newline #\Return)
                                       (uiop:run-program '("uname" "-s")
                                                         :output :string)))
                         :keyword))))
    (dolist (flag '(:lui-linux-host :lui-bsd-host :lui-darwin-host
                   :lui-windows-host :lui-posix-host))
      (setf *features* (remove flag *features*)))
    (case os
      (:linux (pushnew :lui-linux-host *features*))
      ((:darwin :macos :macosx) (pushnew :lui-darwin-host *features*))
      ((:bsd :freebsd :openbsd :netbsd) (pushnew :lui-bsd-host *features*))
      ((:win :windows :win32 :mswindows)
       (pushnew :lui-windows-host *features*)))
    (when (intersection '(:lui-linux-host :lui-darwin-host :lui-bsd-host)
                        *features*)
      (pushnew :lui-posix-host *features*))))

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
  :version "0.1.0"
  :depends-on ("lui/core" "lui/terminal"
               #+(or lui-linux-host lui-bsd-host) "lui/x11"
               #+lui-linux-host "lui/wayland"
               #+lui-windows-host "lui/win32"
               #+(and lui-darwin-host sbcl) "lui/cocoa")
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
  :depends-on ("lui/core" "cffi" "zpb-ttf")
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
