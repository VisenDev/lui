(defpackage #:%lui.example.daw-files
  (:use #:cl)
  (:export #:choose-file #:*picker* #:apple-string #:macos-script))
(in-package #:%lui.example.daw-files)

(define-condition picker-error (simple-error)
  ()
  (:documentation "The native DAW file picker could not complete."))

(defun apple-string (text)
  "Quote literal AppleScript text without interpreting paths as code."
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop :for char :across text
          :do (when (find char '(#\\ #\")) (write-char #\\ stream))
              (write-char char stream))
    (write-char #\" stream)))

(defun macos-script (open-p title default type)
  "Build a native picker script, handling user cancellation separately."
  (let ((directory (uiop:pathname-directory-pathname default)))
    (format nil
            "try~%activate~%set chosen to choose ~A with prompt ~A~A~A~%~
             return POSIX path of chosen~%on error number -128~%~
             return \"\"~%end try"
            (if open-p "file" "file name") (apple-string title)
            (if open-p
                (format nil " of type {~A}" (apple-string type))
                ;; else
                (format nil " default name ~A"
                        (apple-string (file-namestring default))))
            (if (probe-file directory)
                (format nil " default location (POSIX file ~A)"
                        (apple-string (namestring directory)))
                ;; else
                ""))))

(defun macos-picker (open-p title default type)
  "Run the system picker outside LUI's Cocoa application and event loop."
  (let* ((output (uiop:run-program
                  (list "/usr/bin/osascript" "-e"
                        (macos-script open-p title default type))
                  :output :string :error-output :string
                  :external-format :utf-8))
         ;; Remove only osascript's final newline, preserving filename spaces.
         (path (if (and (plusp (length output))
                        (char= #\Newline (char output (1- (length output)))))
                   (subseq output 0 (1- (length output)))
                   output)))
    (unless (zerop (length path)) (uiop:parse-native-namestring path))))

(defun native-picker (open-p title default type)
  "Choose a single file using the platform's native dialog provider."
  (if (member :darwin *features*)
      (macos-picker open-p title default type)
      ;; else
      (multiple-value-bind (path accepted-p)
          (funcall (if open-p #'org.shirakumo.file-select:existing
                       #'org.shirakumo.file-select:new)
                   :title title :default default :filter type)
        (when accepted-p (pathname path)))))

(defvar *picker* #'native-picker
  "File dialog provider, dynamically replaceable for headless DAW tests.")

(defun choose-file (open-p title default type)
  "Return a selected pathname or NIL on cancellation; report picker errors."
  (handler-case
      (let ((path (funcall *picker* open-p title default type)))
        (when path
          (if (or open-p (pathname-type path)) path
              (make-pathname :type type :defaults path))))
    (error (condition)
      (error 'picker-error :format-control "File dialog failed: ~A"
                           :format-arguments (list condition)))))
