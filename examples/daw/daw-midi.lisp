(defpackage #:%lui.example.daw-midi
  (:use #:cl)
  (:export #:input #:list-inputs #:open-input #:close-input #:poll-input
           #:midi-error))
(in-package #:%lui.example.daw-midi)

(define-condition midi-error (error)
  ((message :initarg :message :reader midi-error-message))
  (:report (lambda (condition stream)
             (write-string (midi-error-message condition) stream)))
  (:documentation "A native MIDI library, device, or input operation failed."))

(cffi:define-foreign-library rtmidi
  (:darwin (:or "librtmidi.7.dylib" "librtmidi.6.dylib" "librtmidi.dylib"))
  (:windows "rtmidi.dll")
  (:unix (:or "librtmidi.so.7" "librtmidi.so.6" "librtmidi.so")))

;; RtMidi 5/6 use two pointers before OK. The newer error-callback API adds
;; a third pointer. Select that layout by its exported API, never by SONAME.
(cffi:defcstruct wrapper
  (object :pointer) (callback :pointer) (ok :bool) (message :pointer))
(cffi:defcstruct callback-wrapper
  (object :pointer) (callback :pointer) (error-callback :pointer)
  (ok :bool) (message :pointer))

(defvar *library* nil "Lazily loaded so editing/export need no MIDI library.")
(defvar *wrapper-type* '(:struct wrapper))

(cffi:defcfun ("rtmidi_in_create" create-device) :pointer
  (api :int) (name :string) (queue-size :unsigned-int))
(cffi:defcfun ("rtmidi_in_free" free-device) :void (device :pointer))
(cffi:defcfun ("rtmidi_open_port" open-port) :void
  (device :pointer) (index :unsigned-int) (name :string))
(cffi:defcfun ("rtmidi_close_port" close-port) :void (device :pointer))
(cffi:defcfun ("rtmidi_get_port_count" port-count) :unsigned-int
  (device :pointer))
(cffi:defcfun ("rtmidi_get_port_name" port-name) :int
  (device :pointer) (index :unsigned-int) (buffer :pointer) (size :pointer))
(cffi:defcfun ("rtmidi_in_ignore_types" ignore-types) :void
  (device :pointer) (sysex :bool) (timing :bool) (sense :bool))
(cffi:defcfun ("rtmidi_in_get_message" get-message) :double
  (device :pointer) (buffer :pointer) (size :pointer))

(defstruct (input (:constructor make-input (device)))
  (device (cffi:null-pointer) :type cffi:foreign-pointer)
  (seconds nil :type (or null real)))

(defun ensure-library ()
  "Load RtMidi only on demand; LUI_DAW_MIDI_LIBRARY can name its full path."
  (unless *library*
    (handler-case
        (setf *library*
              (cffi:load-foreign-library
               (or (uiop:getenv "LUI_DAW_MIDI_LIBRARY") 'rtmidi)))
      (error (condition)
        (error 'midi-error :message
               (format nil "Install the RtMidi shared library: ~A" condition))))
    (setf *wrapper-type*
          (if (cffi:foreign-symbol-pointer "rtmidi_set_error_callback"
                                          :library *library*)
              '(:struct callback-wrapper)
              ;; else
              '(:struct wrapper))))
  *library*)

(defun check-device (device)
  "Translate the C wrapper status before making another native call."
  (when (cffi:null-pointer-p device)
    (error 'midi-error :message "RtMidi could not allocate an input."))
  (unless (cffi:foreign-slot-value device *wrapper-type* 'ok)
    ;; Older RtMidi wrappers can retain a destroyed exception's message
    ;; pointer. Never dereference it, even to report an initialization error.
    (error 'midi-error :message
           "Native MIDI failed; check the host MIDI service and input device."))
  device)

(defun new-device ()
  "Create a queued input, freeing the wrapper if initialization fails."
  (ensure-library)
  (let ((device (create-device 0 "LUI Pocket Studio" 4096)))
    (handler-case (check-device device)
      (error (condition)
        (unless (cffi:null-pointer-p device) (free-device device))
        (error condition)))))

(defun input-name (device index)
  "Read an input name with the size negotiated through RtMidi's C API."
  (cffi:with-foreign-object (size :int)
    (setf (cffi:mem-ref size :int) 0)
    (port-name device index (cffi:null-pointer) size)
    (check-device device)
    (let ((length (cffi:mem-ref size :int)))
      (unless (< 0 length 65536)
        (error 'midi-error :message "RtMidi returned an invalid name length."))
      (cffi:with-foreign-object (buffer :char length)
        (port-name device index buffer size)
        (check-device device)
        (cffi:foreign-string-to-lisp buffer :max-chars (1- length))))))

(defun list-inputs ()
  "Return a vector of input names; vector indices are native port numbers."
  (let ((device (new-device)))
    (unwind-protect
         (let* ((count (port-count device))
                (names (make-array count :element-type 'string :initial-element "")))
           (check-device device)
           (dotimes (index count) (setf (aref names index)
                                      (input-name device index)))
           names)
      (free-device device))))

(defun open-input (index)
  "Open an input for nonblocking polling; filter SysEx, clock and sensing."
  (let ((device (new-device)))
    (handler-case
        (let ((count (port-count device)))
          (check-device device)
          (unless (and (integerp index) (<= 0 index) (< index count))
            (error 'midi-error :message "No MIDI input at that port index."))
          (ignore-types device t t t)
          (check-device device)
          (open-port device index "Record")
          (check-device device)
          (make-input device))
      (error (condition)
        (free-device device)
        (error condition)))))

(defun close-input (input)
  "Release an input exactly once, including after a failed read."
  (declare (values))
  (unless (cffi:null-pointer-p (input-device input))
    (let ((device (input-device input)))
      (setf (input-device input) (cffi:null-pointer))
      (unwind-protect (close-port device) (free-device device))))
  (values))

(defun poll-input (input elapsed receiver)
  "Drain queued channel messages, calling RECEIVER with seconds and MIDI bytes.
The first message is anchored to ELAPSED (within one UI poll, normally 33 ms).
Later messages use native delta timestamps, including ignored short messages.
No Lisp callback runs on a foreign thread. Limit work per frame to queue size."
  (declare (values))
  (cffi:with-foreign-objects ((buffer :unsigned-char 3) (size :size))
    (loop :repeat 4096
          :do (setf (cffi:mem-ref size :size) 3)
              (let* ((delta (get-message (input-device input) buffer size))
                     (length (cffi:mem-ref size :size)))
                (check-device (input-device input))
                (when (zerop length) (return))
                (setf (input-seconds input)
                      (if (input-seconds input)
                          (+ (input-seconds input) (max 0 delta)) elapsed))
                (when (= length 3)
                  (funcall receiver (input-seconds input)
                           (cffi:mem-aref buffer :unsigned-char 0)
                           (cffi:mem-aref buffer :unsigned-char 1)
                           (cffi:mem-aref buffer :unsigned-char 2))))))
  (values))
