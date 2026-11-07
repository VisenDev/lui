(defpackage #:lui.win32
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.font #:lui.draw)
  (:export #:run-win32))

(in-package #:lui.win32)

;; Win64 uses the platform calling convention for both C and WinAPI calls.
;; Explicit STDCALL also permits 32-bit Common Lisp implementations.
(cffi:define-foreign-library kernel32 (:windows "kernel32.dll"))
(cffi:define-foreign-library gdiplus (:windows "gdiplus.dll"))
(cffi:use-foreign-library kernel32)
(cffi:use-foreign-library gdiplus)

(defmacro api (name result &rest args)
  `(cffi:defcfun (,@name :convention :stdcall) ,result ,@args))

(api ("MsgWaitForMultipleObjectsEx" wait-messages) :uint
  (count :uint) (handles :pointer) (timeout :uint) (mask :uint) (flags :uint))

(api ("OpenClipboard" open-clipboard) :int (window :pointer))
(api ("CloseClipboard" close-clipboard) :int)
(api ("EmptyClipboard" empty-clipboard) :int)
(api ("SetClipboardData" set-clipboard-data) :pointer
  (format :uint) (memory :pointer))
(api ("GlobalAlloc" global-alloc) :pointer (flags :uint) (bytes :size))
(api ("GlobalLock" global-lock) :pointer (memory :pointer))
(api ("GlobalUnlock" global-unlock) :int (memory :pointer))
(api ("GlobalFree" global-free) :pointer (memory :pointer))

;; FTW covers windowing and GDI. The bindings above/below extend it with
;; clipboard, input tracking, frame waiting, and GDI+, which FTW does not expose.
;; FTW's POINT slots are unsigned; preserve signed Win32 screen coordinates.
(fn signed-coordinate ((value integer))
  (if (logbitp 31 value) (- value #x100000000) value))

(fn screen-to-client (window point)
  (let ((coordinates (ftw:screen-to-client window
                       (list (logand #xffffffff (cffi:mem-aref point :int 0))
                             (logand #xffffffff (cffi:mem-aref point :int 1))))))
    (setf (cffi:mem-aref point :int 0) (signed-coordinate (first coordinates))
          (cffi:mem-aref point :int 1) (signed-coordinate (second coordinates))))
  1)

(fn cursor-position (point)
  (let ((coordinates (ftw:get-cursor-position)))
    (setf (cffi:mem-aref point :int 0) (signed-coordinate (first coordinates))
          (cffi:mem-aref point :int 1) (signed-coordinate (second coordinates))))
  1)

(fn copy-text (window (text string))
  (let* ((bytes (* 2 (1+ (loop :for char :across text
                              :sum (if (> (char-code char) #xffff) 2 1)))))
         (memory (global-alloc #x42 bytes)))
    (unless (cffi:null-pointer-p memory)
      (unwind-protect
           (let ((pointer (global-lock memory)))
             (unless (cffi:null-pointer-p pointer)
               (unwind-protect
                    (cffi:lisp-string-to-foreign text pointer bytes
                                                 :encoding :utf-16le)
                 (global-unlock memory))
               (unless (zerop (open-clipboard window))
                 (unwind-protect
                      (progn
                        (empty-clipboard)
                        (unless (cffi:null-pointer-p
                                 (set-clipboard-data 13 memory))
                          (setf memory (cffi:null-pointer))))
                   (close-clipboard)))))
        (unless (cffi:null-pointer-p memory) (global-free memory))))))

(api ("AdjustWindowRect" adjust-rect) :int
  (rect :pointer) (style :uint32) (menu :int))
(api ("ValidateRect" validate-rect) :int
  (window :pointer) (rect :pointer))

(api ("SetCapture" set-capture) :pointer (window :pointer))
(api ("ReleaseCapture" release-capture) :int)

(api ("GetKeyState" key-state) :short (key :int))
(api ("TrackMouseEvent" track-mouse-event) :int (tracking :pointer))

(api ("SetCursor" set-cursor) :pointer (cursor :pointer))

(api ("GdiplusStartup" startup) :int
  (token :pointer) (input :pointer) (output :pointer))
(api ("GdiplusShutdown" shutdown) :void (token :uintptr))
(api ("GdipCreateFromHDC" create-graphics) :int
  (dc :pointer) (graphics :pointer))
(api ("GdipDeleteGraphics" delete-graphics) :int (graphics :pointer))
(api ("GdipSetSmoothingMode" smoothing-mode) :int
  (graphics :pointer) (mode :int))
(api ("GdipGraphicsClear" clear-graphics) :int
  (graphics :pointer) (argb :uint32))
(api ("GdipCreatePath" create-path) :int (mode :int) (path :pointer))
(api ("GdipAddPathPolygon" add-polygon) :int
  (path :pointer) (points :pointer) (count :int))
(api ("GdipDeletePath" delete-path) :int (path :pointer))
(api ("GdipCreateSolidFill" solid-fill) :int
  (argb :uint32) (brush :pointer))
(api ("GdipDeleteBrush" delete-brush) :int (brush :pointer))
(api ("GdipFillPath" fill-path) :int
  (graphics :pointer) (brush :pointer) (path :pointer))
(api ("GdipResetClip" reset-clip) :int (graphics :pointer))
(api ("GdipSetClipRect" set-clip) :int
  (graphics :pointer) (x :float) (y :float) (width :float)
  (height :float) (mode :int))
(api ("GdipFlush" flush-graphics) :int (graphics :pointer) (intent :int))

(api ("GdipGetDC" graphics-dc) :int
  (graphics :pointer) (dc :pointer))
(api ("GdipReleaseDC" release-graphics-dc) :int
  (graphics :pointer) (dc :pointer))
(api ("GdipCreateBitmapFromScan0" create-image) :int
  (width :int) (height :int) (stride :int) (format :int)
  (pixels :pointer) (image :pointer))
(api ("GdipGetImageGraphicsContext" image-graphics) :int
  (image :pointer) (graphics :pointer))
(api ("GdipDisposeImage" dispose-image) :int (image :pointer))
(api ("GdipSetInterpolationMode" interpolation-mode) :int
  (graphics :pointer) (mode :int))
(api ("GdipDrawImageRectRectI" draw-image) :int
  (graphics :pointer) (image :pointer) (dx :int) (dy :int)
  (dw :int) (dh :int) (sx :int) (sy :int) (sw :int) (sh :int)
  (unit :int) (attributes :pointer) (callback :pointer) (data :pointer))
(api ("GdipSaveGraphics" save-graphics) :int
  (graphics :pointer) (state :pointer))
(api ("GdipRestoreGraphics" restore-graphics) :int
  (graphics :pointer) (state :uint32))
(api ("GdipSetClipPath" clip-path) :int
  (graphics :pointer) (path :pointer) (mode :int))

(cffi:defcstruct mouse-tracking
  (size :uint32) (flags :uint32) (window :pointer) (hover-time :uint32))
(cffi:defcstruct startup-input
  (version :uint32) (callback :pointer) (thread :int) (codecs :int))

(defstruct win-window
  redraw-p
  (handle (cffi:null-pointer))
  (dc (cffi:null-pointer))
  (bitmap (cffi:null-pointer))
  (old-bitmap (cffi:null-pointer))
  (graphics (cffi:null-pointer))
  (width 0 :type integer) (height 0 :type integer)
  (events nil :type list)
  quit error surrogate context suppress-system-char tracking-p
  (suppressed-spaces 0 :type integer)
  (capture-p nil :type boolean))

(defvar *windows* (make-hash-table))
(defvar *class-counter* 0)
(defvar *window-hook* nil "Test hook called once after creating a window.")

(fn checked ((status integer))
  (unless (zerop status) (error "GDI+ status ~D." status)))

(fn nonnull (pointer)
  (when (or (null pointer) (cffi:null-pointer-p pointer))
    (error "Win32 allocation failed."))
  pointer)

(fn signed-word ((value integer))
  (let ((word (logand value #xffff)))
    (if (logbitp 15 word) (- word #x10000) word)))

(fn queue-input ((window win-window) (event event))
  (push event (win-window-events window)))

(fn character-input ((window win-window) (code integer))
  (cond
    ((<= #xd800 code #xdbff) (setf (win-window-surrogate window) code))
    ((<= #xdc00 code #xdfff)
      (when (win-window-surrogate window)
        (character-input window
          (+ #x10000 (* (- (win-window-surrogate window) #xd800) 1024)
            (- code #xdc00)))))
    (t
      (setf (win-window-surrogate window) nil)
      (when (>= code 32)
        (let ((char (code-char code)))
          (when char
            (queue-input window
              (make-event :kind :text :value (string char)))))))))

(fn key-input ((code integer) control alt shift text-p
               &optional activation-p)
  (let* ((key (cdr (assoc code
                          '((37 . :left) (38 . :up) (39 . :right)
                            (40 . :down) (36 . :home) (35 . :end)
                            (8 . :backspace) (46 . :delete) (27 . :escape)))))
         (name (case code
                 (37 "ArrowLeft") (39 "ArrowRight") (8 "Backspace")
                 (otherwise (if (<= 32 code 126)
                                (string (code-char code)) ""))))
         (command (when (and text-p (not (and control alt)))
                    (lui.widgets:readline-key name :control control
                                             :alt alt :shift shift))))
    (cond ((and control (not alt) (= code 67))
           (make-event :kind :key :key :copy))
          (command (make-event :kind :key :key command))
          ((and (not alt) (= code 9))
           (make-event :kind :tab :key (when shift :backward)))
          ((and (= code 32) activation-p (not control) (not alt))
           (make-event :kind :activate))
          ((and (not alt) (= code 13)) (make-event :kind :activate))
          ((and key (not alt))
           (make-event :kind :key
                       :key (if (and text-p shift)
                                (case key
                                  (:left :shift-left) (:right :shift-right)
                                  (otherwise key))
                                key))))))

(fn cursor-name ((kind symbol))
  (case kind (:not-allowed :no) (:pointer :hand) (:text :ibeam)
        (:resize-horizontal :sizewe) (:resize-vertical :sizens)
        (otherwise :arrow)))

(fn update-cursor ((window win-window))
  (when (win-window-context window)
    (cffi:with-foreign-object (point :int 2)
      (when (and (plusp (cursor-position point))
                 (plusp (screen-to-client (win-window-handle window) point)))
        (let ((x (cffi:mem-aref point :int 0))
              (y (cffi:mem-aref point :int 1)))
          (when (and (<= 0 x) (< x (win-window-width window))
                     (<= 0 y) (< y (win-window-height window)))
            (set-cursor
             (ftw:load-cursor
               (cursor-name (lui.widgets:cursor-at
                              (win-window-context window) x y))))))))))

(fn window-message
  ((window win-window) (message integer) (wparam integer)
    (lparam integer))
  (let ((handle (win-window-handle window))
        (x (signed-word lparam)) (y (signed-word (ash lparam -16))))
    (case message
      (#x10 (setf (win-window-quit window) t))
      (#x05 (setf (win-window-redraw-p window) t))
      (#x0f (setf (win-window-redraw-p window) t)
             (validate-rect handle (cffi:null-pointer)))
      (#x14 (return-from window-message 1))
      (#x20
       (if (= (logand lparam #xffff) 1)
           (progn (update-cursor window) (return-from window-message 1))
           (return-from window-message
             (ftw:default-window-proc handle message wparam lparam))))
      ((#x8 #x1f #x215)
       (let ((owned (win-window-capture-p window)))
         (when (or (/= message #x215) owned)
           (setf (win-window-capture-p window) nil)
           (when (and owned (/= message #x215)) (release-capture))
           (queue-input window (make-event :kind :cancel :buttons 0)))))
      (#x2a3
       (setf (win-window-tracking-p window) nil)
       ;; Captured WM_MOUSEMOVE retains real out-of-window drag coordinates.
       (unless (win-window-capture-p window)
         (queue-input window (make-event :kind :move :x -1 :y -1
                                         :buttons 0))))
      ((#x200 #x201 #x202 #x204 #x205)
        (when (and (= message #x200) (not (win-window-tracking-p window)))
          (cffi:with-foreign-object (tracking '(:struct mouse-tracking))
            (cffi:with-foreign-slots
                ((size flags window hover-time) tracking
                 (:struct mouse-tracking))
              (setf size (cffi:foreign-type-size '(:struct mouse-tracking))
                    flags 2 window handle hover-time 0))
            (setf (win-window-tracking-p window)
                  (not (zerop (track-mouse-event tracking))))))
        (when (and (= message #x200) (win-window-capture-p window)
                   (not (logbitp 0 wparam)))
          (setf (win-window-capture-p window) nil)
          (release-capture))
        (when (= message #x201)
          (setf (win-window-capture-p window) t)
          (set-capture handle))
        (when (= message #x202)
          ;; ReleaseCapture synchronously sends WM_CAPTURECHANGED. This is a
          ;; normal button-up, so do not turn that notification into :CANCEL.
          (let ((owned (win-window-capture-p window)))
            (setf (win-window-capture-p window) nil)
            (when owned (release-capture))))
        (queue-input window
          (make-event :kind
            (case message ((#x201 #x204) :press)
                          ((#x202 #x205) :release) (t :move))
            :button (if (member message '(#x204 #x205))
                        :secondary :primary)
            :buttons (logand wparam 3) :x x :y y)))
      (#x20a
        (cffi:with-foreign-object (point :int 2)
          (setf (cffi:mem-aref point :int 0) x
            (cffi:mem-aref point :int 1) y)
          (screen-to-client handle point)
          (queue-input window
            (make-event :kind :scroll
              :x (cffi:mem-aref point :int 0)
              :y (cffi:mem-aref point :int 1)
              :value (* -32 (/ (signed-word (ash wparam -16)) 120))))))
      ((#x100 #x104)
       (let* ((context (win-window-context window))
              (predicted
                (when context
                  (pending-input-context
                   context (win-window-events window)
                   (win-window-width window) (win-window-height window))))
              (input (key-input
                      wparam (minusp (key-state 17))
                      (minusp (key-state 18)) (minusp (key-state 16))
                      (and predicted
                           (lui.widgets:text-field-focused-p predicted))
                      (and predicted
                           (lui.widgets:activation-focused-p predicted)))))
         (when input
           (queue-input window input)
           (when (and (= wparam 32) (eq (event-kind input) :activate))
             (incf (win-window-suppressed-spaces window)))
           (when (= message #x104)
             (setf (win-window-suppress-system-char window) t)))
         (when (and (= message #x104) (null input))
           (return-from window-message
             (ftw:default-window-proc handle message wparam lparam)))))
      (#x105
       (setf (win-window-suppress-system-char window) nil)
       (return-from window-message
         (ftw:default-window-proc handle message wparam lparam)))
      (#x106
       (unless (shiftf (win-window-suppress-system-char window) nil)
         (return-from window-message
           (ftw:default-window-proc handle message wparam lparam))))
      (#x102
       (if (and (= wparam 32) (plusp (win-window-suppressed-spaces window)))
           (decf (win-window-suppressed-spaces window))
           (character-input window wparam)))
      (otherwise
        (return-from window-message
          (ftw:default-window-proc handle message wparam lparam)))))
  0)

(cffi:defcallback (window-procedure :convention :stdcall) :intptr
  ((handle :pointer) (message :uint32) (wparam :uintptr) (lparam :intptr))
  (let ((window (gethash (cffi:pointer-address handle) *windows*)))
    (if window
      (handler-case (window-message window message wparam lparam)
        (error (condition)
          (setf (win-window-error window) condition
            (win-window-quit window) t)
          0))
      (ftw:default-window-proc handle message wparam lparam))))

(fn free-buffer ((window win-window))
  (unless (cffi:null-pointer-p (win-window-graphics window))
    (delete-graphics (win-window-graphics window)))
  (unless (cffi:null-pointer-p (win-window-old-bitmap window))
    (ftw:select-object (win-window-dc window) (win-window-old-bitmap window)))
  (unless (cffi:null-pointer-p (win-window-bitmap window))
    (ftw:delete-object (win-window-bitmap window)))
  (unless (cffi:null-pointer-p (win-window-dc window))
    (ftw:delete-dc (win-window-dc window)))
  (setf (win-window-graphics window) (cffi:null-pointer)
    (win-window-dc window) (cffi:null-pointer)
    (win-window-bitmap window) (cffi:null-pointer)
    (win-window-old-bitmap window) (cffi:null-pointer)))

(fn resize-buffer ((window win-window) (width integer) (height integer))
  (free-buffer window)
  (let ((dc (nonnull (ftw:get-dc (win-window-handle window)))))
    (unwind-protect
      (progn
        (setf (win-window-width window) (max 1 width)
          (win-window-height window) (max 1 height)
          (win-window-dc window) (nonnull (ftw:create-compatible-dc dc))
          (win-window-bitmap window)
          (nonnull (ftw:create-compatible-bitmap dc (max 1 width) (max 1 height)))
          (win-window-old-bitmap window)
          (ftw:select-object (win-window-dc window) (win-window-bitmap window)))
        (cffi:with-foreign-object (out :pointer)
          (checked (create-graphics (win-window-dc window) out))
          (setf (win-window-graphics window) (cffi:mem-ref out :pointer)))
        (checked (smoothing-mode (win-window-graphics window) 4)))
      ;; Upstream RELEASE-DC names its arguments HDC/HWND but forwards them
      ;; in HWND/HDC order. Pass native order to release the correct DC.
      (ftw:release-dc (win-window-handle window) dc))))

(fn argb ((color string) (alpha real))
  (logior (ash (round (* 255 (max 0 (min 1 alpha)))) 24)
    (parse-integer color :start 1 :radix 16)))

(fn draw-polygons
  ((window win-window) (contours list) (color string) (alpha real))
  (cffi:with-foreign-objects ((path-out :pointer) (brush-out :pointer))
    (checked (create-path 1 path-out))
    (let ((path (cffi:mem-ref path-out :pointer)) (brush nil))
      (unwind-protect
        (progn
          (dolist (points contours)
            (when (>= (length points) 3)
              (cffi:with-foreign-object (data :float (* 2 (length points)))
                (loop :for point :in points :for i :from 0 :by 2 :do
                  (setf (cffi:mem-aref data :float i)
                    (float (car point) 1.0f0)
                    (cffi:mem-aref data :float (1+ i))
                    (float (cdr point) 1.0f0)))
                (checked (add-polygon path data (length points))))))
          (checked (solid-fill (argb color alpha) brush-out))
          (setf brush (cffi:mem-ref brush-out :pointer))
          (checked (fill-path (win-window-graphics window) brush path)))
        (when brush (delete-brush brush))
        (delete-path path)))))

(fn clip-window ((window win-window) (box box))
  (checked (reset-clip (win-window-graphics window)))
  (checked
    (set-clip (win-window-graphics window)
      (float (box-x box) 1.0f0) (float (box-y box) 1.0f0)
      (float (max 0 (box-width box)) 1.0f0)
      (float (max 0 (box-height box)) 1.0f0) 0)))

(fn blit-image
  (graphics image (x integer) (y integer) (width integer) (height integer)
    (sx integer) (sy integer) (sw integer) (sh integer))
  (checked
    (draw-image graphics image x y width height sx sy sw sh 2
      (cffi:null-pointer) (cffi:null-pointer) (cffi:null-pointer))))

(fn capture-backdrop
  ((window win-window) (x integer) (y integer)
    (width integer) (height integer))
  (let ((image nil) (target nil) (source-dc nil) (target-dc nil)
        (complete nil) (source (win-window-graphics window)))
    (cffi:with-foreign-object (out :pointer)
      (unwind-protect
        (progn
          ;; Native RGB storage avoids undefined alpha from GDI BitBlt.
          (checked
            (create-image width height 0 #x21808 (cffi:null-pointer) out))
          (setf image (cffi:mem-ref out :pointer))
          (checked (image-graphics image out))
          (setf target (cffi:mem-ref out :pointer))
          (checked (graphics-dc target out))
          (setf target-dc (cffi:mem-ref out :pointer))
          (checked (graphics-dc source out))
          (setf source-dc (cffi:mem-ref out :pointer))
          (ftw:bit-blt target-dc 0 0 source-dc x y
            :width width :height height :raster-op :srccopy)
          (setf complete t)
          image)
        (when source-dc (release-graphics-dc source source-dc))
        (when target-dc (release-graphics-dc target target-dc))
        (when target (delete-graphics target))
        (when (and image (not complete)) (dispose-image image))))))

(fn blur-backdrop
  ((window win-window) (box box) (radius real) (blur real))
  "Approximate backdrop blur with native filtered downsampling and upsampling.
GDI+ owns all image storage, filtering, clipping, and rasterization. This is a
compact tent-like blur rather than a Gaussian kernel; it also works in Wine."
  (when (<= blur 0) (return-from blur-backdrop nil))
  (let* ((graphics (win-window-graphics window))
         (left (max 0 (floor (- (box-x box) (* 2 blur)))))
         (top (max 0 (floor (- (box-y box) (* 2 blur)))))
         (right (min (win-window-width window)
                  (ceiling (+ (box-x box) (box-width box) (* 2 blur)))))
         (bottom (min (win-window-height window)
                   (ceiling (+ (box-y box) (box-height box) (* 2 blur)))))
         (width (- right left)) (height (- bottom top))
         (factor (max 1 (ceiling blur 2)))
         (small-width (max 1 (ceiling width factor)))
         (small-height (max 1 (ceiling height factor)))
         (snapshot nil) (small nil) (small-graphics nil) (path nil)
         (saved nil))
    (unless (and (plusp width) (plusp height))
      (return-from blur-backdrop nil))
    (cffi:with-foreign-objects ((out :pointer) (state :uint32))
      (unwind-protect
        (progn
          (checked (flush-graphics graphics 1))
          (setf snapshot (capture-backdrop window left top width height))
          ;; NULL asks GDI+ to allocate storage; Lisp never supplies pixels.
          (checked
            (create-image small-width small-height 0 #x26200a
              (cffi:null-pointer) out))
          (setf small (cffi:mem-ref out :pointer))
          (checked (image-graphics small out))
          (setf small-graphics (cffi:mem-ref out :pointer))
          (checked (interpolation-mode small-graphics 7))
          (blit-image small-graphics snapshot 0 0 small-width small-height
            0 0 width height)
          (checked (delete-graphics small-graphics))
          (setf small-graphics nil)
          (checked (create-path 1 out))
          (setf path (cffi:mem-ref out :pointer))
          (let ((points (rounded-polygon box radius)))
            (cffi:with-foreign-object (data :float (* 2 (length points)))
              (loop :for point :in points :for i :from 0 :by 2 :do
                (setf (cffi:mem-aref data :float i)
                  (float (car point) 1.0f0)
                  (cffi:mem-aref data :float (1+ i))
                  (float (cdr point) 1.0f0)))
              (checked (add-polygon path data (length points)))))
          (checked (save-graphics graphics state))
          (setf saved (cffi:mem-ref state :uint32))
          ;; Intersect with the current widget/ancestor clip.
          (checked (clip-path graphics path 1))
          (checked (interpolation-mode graphics 7))
          (blit-image graphics small left top width height
            0 0 small-width small-height))
        (when saved (restore-graphics graphics saved))
        (when path (delete-path path))
        (when small-graphics (delete-graphics small-graphics))
        (when small (dispose-image small))
        (when snapshot (dispose-image snapshot))))))

(fn pump-messages ((window win-window))
  (let ((message (ftw:make-msg)))
    (loop :while (ftw:peek-message message :hwnd (win-window-handle window)
                                  :remove-msg :remove :error-p nil) :do
      (ftw:translate-message message)
      (ftw:dispatch-message message)))
  (when (win-window-error window) (error (win-window-error window))))

(fn wait-win32 ((window win-window) (context context) input)
  (loop
    (pump-messages window)
    (let ((delay (lui.frame::frame-wait context input)))
      (when (or (zerop delay) (win-window-events window)
                (win-window-redraw-p window) (win-window-quit window))
        (return))
      (wait-messages 0 (cffi:null-pointer) (ceiling (* 1000 delay))
                     #x4ff 0)))
  (unless (win-window-quit window) (lui.frame::limit-frame-rate context)))

(fn render-frame
  ((window win-window) (renderer renderer) (context context)
    (draw function))
  (let* ((rect (ftw:get-client-rect (win-window-handle window)))
         (width (max 1 (ftw:rect-right rect)))
         (height (max 1 (ftw:rect-bottom rect))))
    (unless (and (= width (win-window-width window))
                 (= height (win-window-height window)))
      (resize-buffer window width height)))
  (with-frame
    (context (win-window-width window) (win-window-height window)
      :events (nreverse (shiftf (win-window-events window) nil)))
    (funcall draw))
  (checked (reset-clip (win-window-graphics window)))
  (checked (clear-graphics (win-window-graphics window) #xff202532))
  (when (win-window-tracking-p window) (update-cursor window))
  (paint-frame renderer context)
  (checked (flush-graphics (win-window-graphics window) 1))
  (let ((dc (nonnull (ftw:get-dc (win-window-handle window)))))
    (unwind-protect
      (ftw:bit-blt dc 0 0 (win-window-dc window) 0 0
        :width (win-window-width window) :height (win-window-height window)
        :raster-op :srccopy)
      ;; Upstream RELEASE-DC names its arguments HDC/HWND but forwards them
      ;; in HWND/HDC order. Pass native order to release the correct DC.
      (ftw:release-dc (win-window-handle window) dc)))
  context)

(fn run-win32
  ((draw function) &key (title "LUI") width height (interactive t))
  "Open a Win32 window and run the shared DRAW callback; INTERACTIVE NIL renders a single frame."
  (let ((window (make-win-window)) (font nil) (token nil)
        (registered nil) (*unit* 8)
        (instance (ftw:get-module-handle))
        (class-name (format nil "LUI-~D" (incf *class-counter*))))
    (unwind-protect
      (progn
        (cffi:with-foreign-objects
          ((input '(:struct startup-input)) (out :uintptr))
          (loop :for i :below
            (cffi:foreign-type-size '(:struct startup-input)) :do
            (setf (cffi:mem-aref input :uint8 i) 0))
          (setf (cffi:foreign-slot-value input
                  '(:struct startup-input) 'version) 1)
          (checked (startup out input (cffi:null-pointer)))
          (setf token (cffi:mem-ref out :uintptr)))
        (unless (plusp (ftw:register-class class-name
                         (cffi:callback window-procedure)
                         :cursor (ftw:load-cursor :arrow)
                         :background (cffi:null-pointer)))
          (error "RegisterClassExW failed."))
        (setf registered t)
        (cffi:with-foreign-object (rect :int 4)
          (setf (cffi:mem-aref rect :int 0) 0
            (cffi:mem-aref rect :int 1) 0
            (cffi:mem-aref rect :int 2) (or width 720)
            (cffi:mem-aref rect :int 3) (or height 520))
          (unless (plusp (adjust-rect rect #x00cf0000 0))
            (error "AdjustWindowRect failed."))
          (setf (win-window-handle window)
            (nonnull
              (ftw:create-window class-name :window-name title
                :styles #x00cf0000 :ex-styles 0 :x 80 :y 80
                :width (- (cffi:mem-aref rect :int 2)
                          (cffi:mem-aref rect :int 0))
                :height (- (cffi:mem-aref rect :int 3)
                           (cffi:mem-aref rect :int 1))
                :instance instance))))
        (setf (gethash (cffi:pointer-address (win-window-handle window))
                *windows*) window
          font (open-font))
        (ftw:show-window (win-window-handle window) :show)
        (let* ((renderer
                 (make-renderer :font font :polygons
                   (lambda (polygons color alpha)
                     (draw-polygons window polygons color alpha))
                   :clip (lambda (box) (clip-window window box))
                   :glass (lambda (box radius blur)
                            (blur-backdrop window box radius blur))))
               (context
                 (make-context :copy
                   (lambda (text)
                     (copy-text (win-window-handle window) text))
                   :measure
                   (lambda (widget width)
                     (measure-widget renderer widget width)))))
          (setf (win-window-context window) context)
          (when *window-hook* (funcall *window-hook* window))
          (loop
            (pump-messages window)
            (when (win-window-quit window) (return context))
            (let ((input (win-window-events window)))
              (setf (win-window-redraw-p window) nil)
              (render-frame window renderer context draw)
              (unless interactive (return context))
              (wait-win32 window context input)))))
      (when font (close-font font))
      (free-buffer window)
      (unless (cffi:null-pointer-p (win-window-handle window))
        (ftw:destroy-window (win-window-handle window))
        (remhash (cffi:pointer-address (win-window-handle window))
          *windows*))
      (when registered (ftw:unregister-class class-name))
      (when token (shutdown token)))))

(register-backend :win32 #'run-win32)
