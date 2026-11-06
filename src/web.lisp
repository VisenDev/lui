(defpackage #:lui.web
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.draw)
  (:export #:mount #:unmount #:refresh))
(in-package #:lui.web)

(defstruct* web-app
  host canvas graphics renderer context callback cleanup observer resize
  animation-frame deadline-timer events pending-p (alive-p t))

(fn rounded-path (g (box box) radius &optional (inset 0))
  ((jscl/ffi:oget g "beginPath"))
  ((jscl/ffi:oget g "roundRect")
   (+ inset (box-x box)) (+ inset (box-y box))
   (max 0 (- (box-width box) (* 2 inset)))
   (max 0 (- (box-height box) (* 2 inset))) (max 0 (- radius inset))))

(fn canvas-renderer (canvas g)
  (let* ((tile (#j:document:createElement #j"canvas"))
         (ink ((jscl/ffi:oget tile "getContext") #j"2d"))
         (sample (#j:document:createElement #j"canvas"))
         (blur ((jscl/ffi:oget sample "getContext") #j"2d")))
    (setf (jscl/ffi:oget tile "width") 2 (jscl/ffi:oget tile "height") 2)
    ((jscl/ffi:oget ink "fillRect") 0 0 1 1)
    ((jscl/ffi:oget ink "fillRect") 1 1 1 1)
    (let ((dots ((jscl/ffi:oget g "createPattern") tile #j"repeat")))
      (make-renderer
       :font (lui.font:open-font)
       :surface
       (lambda (box radius color alpha &optional stroke)
         (setf (jscl/ffi:oget g "globalAlpha") alpha)
         (rounded-path g box radius (if stroke (/ stroke 2) 0))
         (if stroke
             (progn
               (setf (jscl/ffi:oget g "lineWidth") stroke
                     (jscl/ffi:oget g "strokeStyle")
                     (jscl/ffi:jsstring color))
               ((jscl/ffi:oget g "stroke")))
             (progn
               (setf (jscl/ffi:oget g "fillStyle") (jscl/ffi:jsstring color))
               ((jscl/ffi:oget g "fill")))))
       :polygons
       (lambda (paths color alpha)
         (setf (jscl/ffi:oget g "fillStyle") (jscl/ffi:jsstring color)
               (jscl/ffi:oget g "globalAlpha") alpha)
         ((jscl/ffi:oget g "beginPath"))
         (dolist (path paths)
           (when path
             ((jscl/ffi:oget g "moveTo") (caar path) (cdar path))
             (dolist (p (cdr path))
               ((jscl/ffi:oget g "lineTo") (car p) (cdr p)))
             ((jscl/ffi:oget g "closePath"))))
         ((jscl/ffi:oget g "fill")))
       :text
       (lambda (font text x y color)
         (setf (jscl/ffi:oget g "globalAlpha") 1
               (jscl/ffi:oget g "font")
               (jscl/ffi:jsstring (lui.font:font-css font))
               (jscl/ffi:oget g "fillStyle") (jscl/ffi:jsstring color))
         ((jscl/ffi:oget g "fillText") (jscl/ffi:jsstring text) x y))
       :clip
       (lambda (box)
         ((jscl/ffi:oget g "restore"))
         ((jscl/ffi:oget g "save"))
         (rounded-path g box 0)
         ((jscl/ffi:oget g "clip")))
       :stipple
       (lambda (box border)
         (setf (jscl/ffi:oget g "globalAlpha") 1
               (jscl/ffi:oget g "fillStyle") dots)
         (rounded-path g box 0)
         (when (and border (> (box-width box) (* 2 border))
                    (> (box-height box) (* 2 border)))
           ((jscl/ffi:oget g "rect") (+ (box-x box) border)
            (+ (box-y box) border) (- (box-width box) (* 2 border))
            (- (box-height box) (* 2 border))))
         ((jscl/ffi:oget g "fill") #j"evenodd"))
       :glass
       (lambda (box radius frost)
         (when (plusp frost)
           (let* ((scale #j:window:devicePixelRatio)
                  (x (box-x box)) (y (box-y box))
                  (w (box-width box)) (h (box-height box))
                  (step (max 1 (/ frost 2)))
                  (sw (max 1 (ceiling (/ w step))))
                  (sh (max 1 (ceiling (/ h step)))))
             ;; Sample the underlying artwork at the frost scale, then
             ;; interpolate it back into the rounded surface.
             (when (> sw (jscl/ffi:oget sample "width"))
               (setf (jscl/ffi:oget sample "width") sw))
             (when (> sh (jscl/ffi:oget sample "height"))
               (setf (jscl/ffi:oget sample "height") sh))
             ((jscl/ffi:oget blur "clearRect") 0 0 sw sh)
             ((jscl/ffi:oget blur "drawImage") canvas
              (* scale x) (* scale y) (* scale w) (* scale h) 0 0 sw sh)
             ((jscl/ffi:oget g "save"))
             (rounded-path g box radius)
             ((jscl/ffi:oget g "clip"))
             (setf (jscl/ffi:oget g "globalAlpha") 1)
             ((jscl/ffi:oget g "drawImage") sample 0 0 sw sh x y w h)
             ((jscl/ffi:oget g "restore")))))))))

(fn queue-event ((app web-app) (event event))
  (when (web-app-alive-p app)
    (if (and (eq (event-kind event) :move)
             (web-app-events app)
             (eq (event-kind (first (web-app-events app))) :move))
        (setf (first (web-app-events app)) event)
        (push event (web-app-events app)))
    (refresh app)))

(fn cancel-deadline ((app web-app))
  (when (web-app-deadline-timer app)
    (#j:clearTimeout (web-app-deadline-timer app))
    (setf (web-app-deadline-timer app) nil)))

(fn schedule-deadline ((app web-app))
  (unless (web-app-pending-p app)
    (cancel-deadline app)
    (let ((delay (lui.frame::frame-wait (web-app-context app))))
      (if (zerop delay)
          (refresh app)
          (setf (web-app-deadline-timer app)
                (#j:setTimeout (lambda () (refresh app))
                               (ceiling (* delay 1000))))))))

(fn draw-frame ((app web-app))
  (let* ((canvas (web-app-canvas app)) (g (web-app-graphics app))
         (context (web-app-context app)) (*unit* 8)
         (width (jscl/ffi:oget canvas "clientWidth"))
         (height (jscl/ffi:oget canvas "clientHeight"))
         (scale #j:window:devicePixelRatio)
         (events (nreverse (shiftf (web-app-events app) nil))))
    (let ((w (round (* width scale))) (h (round (* height scale))))
      (unless (= w (jscl/ffi:oget canvas "width"))
        (setf (jscl/ffi:oget canvas "width") w))
      (unless (= h (jscl/ffi:oget canvas "height"))
        (setf (jscl/ffi:oget canvas "height") h)))
    (with-frame (context width height :events events)
      (funcall (web-app-callback app)))
    ((jscl/ffi:oget g "setTransform") scale 0 0 scale 0 0)
    (setf (jscl/ffi:oget g "fillStyle") #j"#202432")
    ((jscl/ffi:oget g "fillRect") 0 0 width height)
    ((jscl/ffi:oget g "save"))
    (unwind-protect (paint-frame (web-app-renderer app) context)
      ((jscl/ffi:oget g "restore")))
    (when (some (lambda (e) (not (eq :move (event-kind e)))) events)
      (refresh app))
    (lui.web.input:update-accessibility canvas context)
    (schedule-deadline app)))

(fn refresh ((app web-app))
  "Request one redraw of a mounted application, coalescing pending requests."
  (when (and (web-app-alive-p app) (not (web-app-pending-p app)))
    (cancel-deadline app)
    (setf (web-app-pending-p app) t)
    (flet ((enqueue ()
             (setf (web-app-deadline-timer app) nil
                   (web-app-animation-frame app)
                   (#j:requestAnimationFrame
                    (lambda (time)
                      (declare (ignore time))
                      (setf (web-app-pending-p app) nil
                            (web-app-animation-frame app) nil)
                      (when (web-app-alive-p app)
                        (draw-frame app)))))))
      (let* ((context (web-app-context app))
             (wait (if (context-root context)
                       (lui.frame::frame-wait context t) 0)))
        (if (zerop wait)
            (enqueue)
            (setf (web-app-deadline-timer app)
                  (#j:setTimeout #'enqueue (ceiling (* wait 1000)))))))))

(fn mount (host (callback function) &key (min-fps lui.frame::*min-fps*)
           (max-fps lui.frame::*max-fps*))
  "Mount a Canvas 2D application inside HOST and return its lifetime handle."
  (assert (< 0 min-fps)) (assert (<= min-fps max-fps))
  (let* ((canvas (#j:document:createElement #j"canvas"))
         (g ((jscl/ffi:oget canvas "getContext") #j"2d"))
         (renderer (canvas-renderer canvas g))
         (context (make-context
                   :min-fps min-fps :max-fps max-fps
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width))))
         (app (make-web-app :host host :canvas canvas :graphics g
                            :renderer renderer :context context
                            :callback callback))
         (resize (lambda (&rest ignored)
                   (declare (ignore ignored)) (refresh app))))
    (setf (jscl/ffi:oget canvas "style" "cssText")
          #j"display:block;width:100%;height:100%;touch-action:none"
          (jscl/ffi:oget canvas "luiApp") app)
    ((jscl/ffi:oget host "appendChild") canvas)
    (setf (web-app-cleanup app)
          (lui.web.input:install-input
           host canvas context (lambda (event) (queue-event app event)))
          (web-app-resize app) resize
          (web-app-observer app) (jscl/ffi:new #j:ResizeObserver resize))
    ((jscl/ffi:oget (web-app-observer app) "observe") host)
    (#j:window:addEventListener #j"resize" resize)
    (refresh app)
    app))

(fn unmount ((app web-app))
  "Cancel scheduled work and release the mounted canvas and input listeners."
  (when (web-app-alive-p app)
    (setf (web-app-alive-p app) nil)
    (cancel-deadline app)
    (when (web-app-animation-frame app)
      (#j:cancelAnimationFrame (web-app-animation-frame app)))
    ((jscl/ffi:oget (web-app-observer app) "disconnect"))
    (#j:window:removeEventListener #j"resize" (web-app-resize app))
    (funcall (web-app-cleanup app))
    (lui.font:close-font (renderer-font (web-app-renderer app)))
    ((jscl/ffi:oget (web-app-canvas app) "remove"))))

(fn css-size (value fallback)
  (if value ((jscl/ffi:oget (#j:String value) "concat") #j"px") fallback))

(fn run-web ((draw function) &key title width height (interactive t))
  (declare (ignore interactive))
  (setf (jscl/ffi:oget #j:document "title") (jscl/ffi:jsstring title))
  (let ((host (#j:document:createElement #j"main")))
    ((jscl/ffi:oget host "setAttribute") #j"aria-label"
     (jscl/ffi:jsstring title))
    (setf (jscl/ffi:oget host "style" "width")
          (css-size width #j"100%")
          (jscl/ffi:oget host "style" "height")
          (css-size height #j"100vh"))
    (#j:document:body:appendChild host)
    (mount host draw)))

(register-backend :web #'run-web)
