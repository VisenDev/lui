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

(let ((window nil) (frames 0)
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
            (let ((events (lui.win32::win-window-events native)))
              (assert (member :press (mapcar #'event-kind events)))
              (assert (member :release (mapcar #'event-kind events)))
              (assert (find "λ" events
                        :key #'event-value :test #'equal))))))
    (let ((context
            (run
              (lambda ()
                (incf frames)
                (lui.example:draw)
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
                  (lui.win32::checked (lui.win32::reset-clip graphics))))
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
           (lui.example:draw)
           (when (= frames 2)
             (assert (> (lui.win32::win-window-width window) 720))
             (assert (plusp
                       (post-message (lui.win32::win-window-handle window)
                         #x10 0 0)))))
      :backend :win32 :width 720 :height 520))
  (assert (= frames 2))
  (assert (zerop (hash-table-count lui.win32::*windows*)))
  (format t "Win32 native paths, holes, alpha, clip, input, resize, demo, and disposal passed.~%"))
