(defpackage #:lui.tests.win32
  (:use #:cl #:lui #:lui.layout #:lui.frame #:lui.draw))

(in-package #:lui.tests.win32)

(cffi:defcfun ("GetPixel" get-pixel :convention :stdcall) :uint32
  (dc :pointer) (x :int) (y :int))
(cffi:defcfun ("PostMessageW" post-message :convention :stdcall) :int
  (window :pointer) (message :uint32) (wparam :uintptr) (lparam :intptr))
(cffi:defcfun ("SetWindowPos" set-window-position :convention :stdcall) :int
  (window :pointer) (after :pointer) (x :int) (y :int) (width :int)
  (height :int) (flags :uint32))

(defun rectangle (x y width height)
  (list (cons x y) (cons (+ x width) y)
    (cons (+ x width) (+ y height)) (cons x (+ y height))))

(defun pixel (window x y)
  (lui.win32::checked
    (lui.win32::flush-graphics (lui.win32::win-window-graphics window) 1))
  (get-pixel (lui.win32::win-window-dc window) x y))

(lui.fn:fn test-readline-keys ()
  (dolist (entry '((65 . :home) (69 . :end) (66 . :left) (70 . :right)
                   (68 . :delete) (72 . :backspace) (75 . :kill-end)
                   (85 . :kill-start) (87 . :kill-word) (89 . :yank)
                   (84 . :transpose)))
    (assert (eq (cdr entry)
                (event-key (lui.win32::key-input (car entry) t nil nil t)))))
  (assert (eq :select-all
              (event-key (lui.win32::key-input 65 t nil t t))))
  (assert (eq :word-left
              (event-key (lui.win32::key-input 66 nil t nil t))))
  (assert (eq :word-right
              (event-key (lui.win32::key-input 39 t nil nil t))))
  (assert (null (lui.win32::key-input 65 t nil nil nil)))
  (assert (null (lui.win32::key-input 13 nil t nil nil)))
  (assert (null (lui.win32::key-input 66 t t nil t))))

(lui.fn:fn test-batched-focus ()
  (let ((context (make-context
                  :measure (lambda (widget width)
                             (declare (ignore widget width))
                             (values 160 30)))))
    (with-frame (context 400 200)
      (lui.glass:text-field :edit "value"))
    (let* ((box (element-box
                 (gethash :edit (lui.frame::context-ids context))))
           (events (list (make-event :kind :press :x (+ 1 (box-x box))
                                     :y (+ 1 (box-y box)))))
           (predicted (pending-input-context context events 400 200)))
      (assert (null (context-focus context)))
      (assert (eq :edit (context-focus predicted)))
      (assert (eq :select-all
                  (event-key
                   (lui.win32::key-input
                    65 t nil t
                    (lui.widgets:text-field-focused-p predicted)))))
      ;; Resizing invalidates pointer regions before the next solved frame.
      (assert (eq context (pending-input-context context events 500 200))))))

(test-batched-focus)

(defun test-copy (window)
  (let ((text "Selected Unicode: lambda λ and face 🙂"))
    (funcall (context-copy (lui.win32::win-window-context window)) text)
    (assert (plusp (lui.win32::open-clipboard
                    (lui.win32::win-window-handle window))))
    (unwind-protect
         (let* ((memory (cffi:foreign-funcall
                         ("GetClipboardData" :convention :stdcall)
                         :uint 13 :pointer))
                (pointer (lui.win32::global-lock memory)))
           (assert (not (cffi:null-pointer-p pointer)))
           (unwind-protect
                (assert (equal text (cffi:foreign-string-to-lisp
                                     pointer :encoding :utf-16le)))
             (lui.win32::global-unlock memory)))
      (lui.win32::close-clipboard))))


(lui.fn:fn test-navigation-and-cursors ()
  (assert (eq :backward
              (event-key (lui.win32::key-input 9 nil nil t nil))))
  (assert (eq :activate
              (event-kind (lui.win32::key-input 32 nil nil nil nil t))))
  (assert (null (lui.win32::key-input 32 nil nil nil t)))
  (let ((window (lui.win32::make-win-window :suppressed-spaces 1)))
    ;; A Space activation must not also become text through WM_CHAR.
    (lui.win32::window-message window #x102 32 0)
    (assert (null (lui.win32::win-window-events window)))
    (lui.win32::window-message window #x102 32 0)
    (assert (equal " " (event-value
                       (first (lui.win32::win-window-events window))))))
  (dolist (kind '(:default :pointer :text :not-allowed
                  :resize-horizontal))
    (assert (not (cffi:null-pointer-p
                  (lui.win32::load-cursor
                   (cffi:null-pointer)
                   (cffi:make-pointer (lui.win32::cursor-id kind))))))))

(test-navigation-and-cursors)

(test-readline-keys)

(let ((window nil) (frames 0) (gallery (lui.example:make-gallery))
      (lui.font:*font-path*
        (or lui.font:*font-path*
          (find-if #'probe-file
            '("Z:/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"
              "Z:/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
          (lui.font::default-font))))
  (let ((lui.win32::*window-hook*
          (lambda (native)
            (setf window native)
            (let ((handle (lui.win32::win-window-handle native)))
              (assert (plusp (post-message handle #x201 0 #x140014)))
              (assert (plusp (post-message handle #x202 0 #x140014)))
              (assert (plusp (post-message handle #x100 9 0)))
              (assert (plusp (post-message handle #x102 #x3bb 0))))
            (lui.win32::pump-messages native)
            (lui.win32::window-message native #x2a3 0 0)
            (let ((events (lui.win32::win-window-events native)))
              (assert (member :press (mapcar #'event-kind events)))
              (assert (member :release (mapcar #'event-kind events)))
              (assert (find-if (lambda (event)
                                 (and (eq :move (event-kind event))
                                      (= -1 (event-x event))))
                               events))
              (assert (find "λ" events
                        :key #'event-value :test #'equal))))))
    (let ((context
            (run
              (lambda ()
                (incf frames)
                (test-copy window)
                (lui.example:draw gallery)
                (let ((graphics (lui.win32::win-window-graphics window)))
                  (lui.win32::checked
                    (lui.win32::clear-graphics graphics #xff000000))
                  (lui.win32::draw-polygons window
                    (list (rectangle 10 10 80 80)
                      (reverse (rectangle 30 30 40 40))) "#ffffff" 1)
                  (assert (= #xffffff (pixel window 20 20)))
                  (assert (= 0 (pixel window 50 50)))
                  (lui.win32::clip-window window
                    (make-box :x 0 :y 0 :width 30 :height 30))
                  (lui.win32::draw-polygons window
                    (list (rectangle 0 0 100 100)) "#ff0000" 0.5)
                  (assert (= #xffffff (pixel window 40 20)))
                  (assert (<= 126 (logand #xff (pixel window 5 5)) 129))
                  (lui.win32::checked (lui.win32::reset-clip graphics))
                  ;; A sharp edge must become intermediate gray inside glass.
                  (lui.win32::checked
                    (lui.win32::clear-graphics graphics #xff000000))
                  (lui.win32::draw-polygons window
                    (list (rectangle 50 0 50 100)) "#ffffff" 1)
                  (lui.win32::blur-backdrop window
                    (make-box :x 20 :y 20 :width 60 :height 60) 16 12)
                  (assert (< 5 (logand #xff (pixel window 48 50)) 250))
                  (assert (= 0 (pixel window 20 20)))
                  (assert (= #xffffff (pixel window 60 10)))
                  ;; The glass operation must restore the previous clip.
                  (lui.win32::draw-polygons window
                    (list (rectangle 0 0 10 10)) "#ff0000" 1)
                  (assert (= #xff (pixel window 5 5)))))
              :backend :win32 :width 720 :height 520 :interactive nil)))
      (assert (= 720 (box-width (element-box (context-root context)))))
      (assert (= 1 frames))))
  (assert (zerop (hash-table-count lui.win32::*windows*)))
  (assert (cffi:null-pointer-p (lui.win32::win-window-dc window)))
  ;; A normal interactive loop must observe native resizes and WM_CLOSE.
  (let ((lui.win32::*window-hook*
          (lambda (native)
            (setf window native)
            (assert (plusp
                      (set-window-position
                        (lui.win32::win-window-handle native)
                        (cffi:null-pointer) 0 0 900 700 #x16))))))
    (setf frames 0)
    (run (lambda ()
           (incf frames)
           (lui.example:draw gallery)
           (when (= frames 2)
             (assert (> (lui.win32::win-window-width window) 720))
             (assert (plusp
                       (post-message (lui.win32::win-window-handle window)
                         #x10 0 0)))))
      :backend :win32 :width 720 :height 520))
  (assert (= frames 2))
  (assert (zerop (hash-table-count lui.win32::*windows*)))
  (format t "Win32 native paths, holes, alpha, clip, glass blur, input, resize, demo, and disposal passed.~%"))
