(defpackage #:lui.web
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.draw)
  (:import-from #:lui.js #:property #:invoke #:global #:new #:same-p)
  (:export #:mount #:unmount #:refresh))
(in-package #:lui.web)

(lui::expose-api mount unmount refresh)

(defstruct web-app
  host stage overlay canvas graphics renderer context callback cleanup
  observer resize scrollport (scroll-listener nil :type t) (viewport-offset 0)
  (scroll-delta 0) (velocity 0) (scroll-time 0)
  (overlay-order #() :type vector) overlay-geometry overlay-cache
  animation-frame deadline-timer events pending-p (alive-p t))

(defvar *mounted-apps* nil)

(fn (canvas-app t) (canvas)
  (find canvas *mounted-apps* :key #'web-app-canvas :test #'same-p))

(fn (page-scrollport t) (host)
  (do ((element host (property element "parentElement")))
      ((same-p element lui.js:+null+) (global "window"))
    (let ((overflow (property
                     (invoke (global "window") "getComputedStyle" element) "overflowY")))
      (when (or (equal overflow "auto") (equal overflow "scroll"))
        (return element)))))

(fn (page-viewport-height real) (port)
  (if (same-p port (global "window"))
      (property (global "window") "innerHeight")
      (property port "clientHeight")))

(fn (page-offset real) (stage port)
  (let ((top (property
              (invoke stage "getBoundingClientRect") "top")))
    (if (same-p port (global "window"))
        (- top)
        (- (+ (property
               (invoke port "getBoundingClientRect") "top")
              (property port "clientTop")) top))))

(fn (page-scroll-by t) (port delta)
  (let ((options (new (global "Object"))))
    (setf (property options "top") delta
          (property options "behavior") "instant")
    (invoke port "scrollBy" options)))

(fn (rounded-path t) (g (box box) radius &optional (inset 0))
  (invoke g "beginPath")
  (invoke g "roundRect"
          (+ inset (box-x box)) (+ inset (box-y box))
          (max 0 (- (box-width box) (* 2 inset)))
          (max 0 (- (box-height box) (* 2 inset))) (max 0 (- radius inset))))

(fn (canvas-renderer renderer) (canvas g)
  (let* ((tile (invoke (global "document") "createElement" "canvas"))
         (ink (invoke tile "getContext" "2d"))
         (sample (invoke (global "document") "createElement" "canvas"))
         (blur (invoke sample "getContext" "2d")))
    (setf (property tile "width") 2 (property tile "height") 2)
    (let ((patterns (make-hash-table :test 'equal)))
      (make-renderer :font (lui.font:open-font) :surface
       (lambda (box radius color alpha &optional stroke)
         (setf (property g "globalAlpha") alpha)
         (if stroke
             (setf (property g "lineWidth") stroke
                   (property g "strokeStyle") color)
             (setf (property g "fillStyle") color))
         (cond ((zerop radius)
                (if stroke
                    (invoke g "strokeRect"
                            (+ (box-x box) (/ stroke 2))
                            (+ (box-y box) (/ stroke 2))
                            (max 0 (- (box-width box) stroke))
                            (max 0 (- (box-height box) stroke)))
                    (invoke g "fillRect" (box-x box) (box-y box)
                            (box-width box) (box-height box))))
               (t
                (rounded-path g box radius (if stroke (/ stroke 2) 0))
                (if stroke
                    (invoke g "stroke")
                    (invoke g "fill"))))) :polygons
       (lambda (paths color alpha)
         (setf (property g "fillStyle") color
               (property g "globalAlpha") alpha)
         (invoke g "beginPath")
         (dotimes (index (length paths))
           (let ((path (aref paths index)))
             (when (plusp (length path))
               (invoke g "moveTo" (car (aref path 0)) (cdr (aref path 0)))
               (dotimes (i (1- (length path)))
                 (let ((p (aref path (1+ i))))
                   (invoke g "lineTo" (car p) (cdr p))))
               (invoke g "closePath"))))
         (invoke g "fill")) :text
       (lambda (font text x y color)
         (setf (property g "globalAlpha") 1
               (property g "font")
               (lui.font:font-css font)
               (property g "fillStyle") color)
         (invoke g "fillText" text x y)) :clip
       (lambda (box)
         (invoke g "restore")
         (invoke g "save")
         (rounded-path g box 0)
         (invoke g "clip")) :stipple
       (lambda (box border color)
         (let ((pattern (gethash color patterns)))
           (unless pattern
             (invoke ink "clearRect" 0 0 2 2)
             (setf (property ink "fillStyle") color)
             (invoke ink "fillRect" 0 0 1 1)
             (invoke ink "fillRect" 1 1 1 1)
             (setf pattern (invoke g "createPattern" tile "repeat")
                   (gethash color patterns) pattern))
           (setf (property g "globalAlpha") 1
                 (property g "fillStyle") pattern))
         (rounded-path g box 0)
         (when (and border (> (box-width box) (* 2 border))
                    (> (box-height box) (* 2 border)))
           (invoke g "rect" (+ (box-x box) border)
                   (+ (box-y box) border) (- (box-width box) (* 2
 border))
                   (- (box-height box) (* 2 border))))
         (invoke g "fill" "evenodd")) :glass
       (lambda (box radius frost)
         (when (plusp frost)
           (let* ((scale (property (global "window") "devicePixelRatio"))
                  (offset (property canvas "luiViewportOffset"))
                  (x (max 0 (box-x box)))
                  (y (max offset (box-y box)))
                  (w (max 0 (- (min (+ (box-x box) (box-width box))
                                    (/ (property canvas "width") scale)) x)))
                  (h (max 0 (- (min (+ (box-y box) (box-height box))
                                    (+ offset (/ (property canvas "height")
                                                 scale))) y)))
                  (step (max 1 (/ frost 2)))
                  (sw (max 1 (ceiling (/ w step))))
                  (sh (max 1 (ceiling (/ h step)))))
             ;; Restrict the scratch bitmap to the visible artwork. The original
             ;; rounded surface still supplies the destination clip.
             (when (and (plusp w) (plusp h))
               (when (> sw (property sample "width"))
                 (setf (property sample "width") sw))
               (when (> sh (property sample "height"))
                 (setf (property sample "height") sh))
               (invoke blur "clearRect" 0 0 sw sh)
               (invoke blur "drawImage" canvas
                       (* scale x) (* scale (- y offset)) (* scale w)
                       (* scale h) 0 0 sw sh)
               (invoke g "save")
               (rounded-path g box radius)
               (invoke g "clip")
               (setf (property g "globalAlpha") 1)
               (invoke g "drawImage" sample 0 0 sw sh x y w h)
               (invoke g "restore")))))))))

(fn (queue-event t) ((app web-app) (event event))
  (when (web-app-alive-p app)
    (if (and (eq (event-kind event) :move)
             (web-app-events app)
             (eq (event-kind (first (web-app-events app))) :move))
        (setf (first (web-app-events app)) event)
        (push event (web-app-events app)))
    (refresh app)))

(fn (cancel-deadline null) ((app web-app))
  (when (web-app-deadline-timer app)
    (invoke (global) "clearTimeout" (web-app-deadline-timer app))
    (setf (web-app-deadline-timer app) nil)))

(fn (schedule-deadline t) ((app web-app))
  (unless (web-app-pending-p app)
    (cancel-deadline app)
    (let ((delay (lui.frame::frame-wait (web-app-context app))))
      (if (zerop delay)
          (refresh app)
          (setf (web-app-deadline-timer app)
                (invoke (global) "setTimeout"
                        (lui.js:callback (lambda () (refresh app)))
                        (ceiling (* delay 1000))))))))

(defstruct dom-widget key element text style state geometry hidden-p)

(defparameter *overlay-cache-limit* 32)

(defstruct overlay-region x y right bottom candidate visible)

(fn (overlay-candidates (vector list)) ((app web-app) (root element))
  ;; Earlier regions in this walk paint in front of later ones. An unchanged
  ;; prefix therefore has exactly the same occlusion as on the previous frame.
  (let ((previous (web-app-overlay-geometry app)) seen bands
        (entries (make-array 0 :element-type 'list :adjustable t
                             :fill-pointer 0)))
    (labels ((index-region (region)
               (do ((band (floor (overlay-region-y region) 64) (1+ band))
                    (end (ceiling (overlay-region-bottom region) 64)))
                   ((>= band end))
                 (push region (gethash band bands))))
             (uncovered-p (x y right bottom)
               (do ((band (floor y 64) (1+ band)) (end (ceiling bottom 64)))
                   ((>= band end) t)
                 (dolist (other (gethash band bands))
                   (when (and (< x (overlay-region-right other))
                              (< (overlay-region-x other) right)
                              (< y (overlay-region-bottom other))
                              (< (overlay-region-y other) bottom))
                     (return-from uncovered-p nil)))))
             (region-visible-p (clip candidate)
               (let* ((x (box-x clip)) (y (box-y clip))
                      (right (+ x (box-width clip))) (bottom (+ y
                                                                (box-height
                                                                 clip)))
                      (old (pop previous)))
                 (cond ((and old (= x (overlay-region-x old))
                             (= y (overlay-region-y old))
                             (= right (overlay-region-right old))
                             (= bottom (overlay-region-bottom old))
                             (eq candidate (overlay-region-candidate old)))
                        (push old seen)
                        (overlay-region-visible old))
                       (t
                        (unless bands
                          (setf previous nil bands (make-hash-table))
                          (dolist (region seen) (index-region region)))
                        (let* ((visible
                                (and candidate
                                     (uncovered-p x y right bottom)))
                               (region
                                (make-overlay-region
                                 :x x :y y :right right :bottom bottom
                                 :candidate candidate :visible visible)))
                          (push region seen)
                          (index-region region) visible)))))
             (visit (node path interactive)
               (let ((key (if (element-id node)
                              (list :id (element-id node)) path))
                     (children (element-children node))
                     (clip (element-clip node))
                     (widget (element-content node)))
                 (let ((count (length children)))
                   (dotimes (offset count)
                     (let ((i (- count offset 1)))
                       (visit (aref children i) (cons i key)
                              (or interactive
                                  (element-interactive-p node))))))
                 (when (and (plusp (box-width clip)) (plusp (box-height clip))
                            (or (lui.widgets:widget-p widget)
                                (element-interactive-p node)))
                   (let ((kind (and (lui.widgets:widget-p widget)
                                    (lui.widgets:widget-kind widget))))
                     (when (region-visible-p clip
                            (and (member kind '(:cell :label :button :tab
                                                :list-item :checkbox :radio))
                                 (or (not (eq kind :label))
                                     (lui:toolkit-native-labels-p
                                      (lui.widgets:widget-style widget)))
                                 (not (lui.widgets:widget-painter widget))))
                       (vector-push-extend
                        (list node (cons kind key) interactive) entries)))))))
      (visit root nil nil))
    (setf (web-app-overlay-geometry app) (nreverse seen))
    (reverse entries)))

(fn (css-pixels t) ((n real))
  (invoke (invoke (global) "String" n) "concat" "px"))

(fn (position-dom-widget null) ((record dom-widget) (box box) (clip box))
  (let* ((x (box-x box)) (y (box-y box)) (w (box-width box)) (h (box-height
                                                                 box))
         (left (- (box-x clip) x)) (top (- (box-y clip) y))
         (right (- w left (box-width clip))) (bottom (- h top (box-height
                                                               clip)))
         (old (dom-widget-geometry record)))
    (destructuring-bind (&optional ox oy ow oh otop oright obottom oleft) old
      (unless (and (eql x ox) (eql y oy) (eql w ow) (eql h oh)
                   (eql top otop) (eql right oright) (eql bottom obottom)
                   (eql left oleft))
        (let ((style (property (dom-widget-element record) "style")))
          (unless (eql x ox) (setf (property style "left")
                                   (css-pixels x)))
          (unless (eql y oy) (setf (property style "top")
                                   (css-pixels y)))
          (unless (eql w ow) (setf (property style "width")
                                   (css-pixels w)))
          (unless (eql h oh) (setf (property style "height")
                                   (css-pixels h)))
          (unless (and (eql top otop) (eql right oright) (eql bottom
                                                              obottom) (eql
                                                              left oleft))
            (setf (property style "clipPath")
                  (if (= 0 top right bottom left) "none"
                      (invoke "inset(" "concat"
                              top "px " right "px " bottom "px "
                              left "px)"))))
          (setf (dom-widget-geometry record) (list x y w h top right bottom
                                                   left)))))) nil)

(fn (make-semantic-button t) ((app web-app) (node element) (kind symbol))
  ;; The canvas keeps pointer capture and toolkit keyboard navigation. Native
  ;; button activation also lets assistive technology invoke the same action.
  (let ((button (invoke (global "document") "createElement" "button"))
        (id (element-id node)))
    (setf (property button "type") "button"
          (property button "tabIndex") -1
          (property button "onclick")
          (lui.js:callback
           (lambda (event)
             (declare (ignore event))
             (queue-event app (make-event :kind :activate :id id)))))
    (when (member kind '(:checkbox :radio))
      (invoke button "setAttribute" "role"
              (string-downcase (symbol-name kind)))) button))

(fn (same-overlay-order-p boolean) ((records (vector dom-widget)) (entries
                                                                   (vector
                                                                    list)))
  (and (= (length records) (length entries))
       (loop :for record :across records :for entry :across entries
             :always (equal (dom-widget-key record) (second entry)))))

(fn (reconcile-overlay (vector dom-widget)) ((app web-app) (entries (vector
                                                                     list)))
  ;; Look up keyed nodes and inspect DOM order only when membership or order changes.
  (let ((order (web-app-overlay-order app)))
    (when (same-overlay-order-p order entries)
      (return-from reconcile-overlay order))
    (let ((old (make-hash-table :test 'equal)) (layer (web-app-overlay app))
          (next (make-array 0 :element-type 'dom-widget :adjustable t
                            :fill-pointer 0))
          (cache (web-app-overlay-cache app)) hidden)
      (loop :for record :across order
            :do (setf (gethash (dom-widget-key record) old) record))
      (dolist (record cache) (setf (gethash (dom-widget-key record) old)
                                   record))
      (loop :for entry :across entries :do
            (destructuring-bind (node key interactive) entry
              (declare (ignore interactive))
              (let* ((kind (car key))
                     (record (or (gethash key old)
                                 (make-dom-widget :key key :element
                                                  (if (eq kind :label)
                                                      (invoke
                                                       (global "document") "createElement" "span")
                                                      (make-semantic-button
                                                       app node kind))))))
                (remhash key old)
                (when (dom-widget-hidden-p record)
                  (setf (dom-widget-hidden-p record) nil
                        (property (dom-widget-element record)
                                  "style" "visibility") "visible"))
                (vector-push-extend record next))))
      ;; Prefer newly hidden nodes over older cached entries when evicting.
      (loop :for record :across order :do
            (when (gethash (dom-widget-key record) old)
              (setf (dom-widget-hidden-p record) t
                    (property (dom-widget-element record)
                              "style" "visibility") "hidden")
              (push record hidden)))
      (setf hidden
            (nconc hidden
                   (loop :for record :in cache
                         :when (gethash (dom-widget-key record) old)
                         :collect record)))
      (loop :for record :in (nthcdr *overlay-cache-limit* hidden)
            :do (invoke (dom-widget-element record) "remove"))
      (when (nthcdr *overlay-cache-limit* hidden)
        (setf (cdr (nthcdr (1- *overlay-cache-limit*) hidden)) nil))
      (setf (web-app-overlay-cache app) hidden)
      (setf order next)
      (let ((cursor (property layer "firstChild")))
        (loop :for record :across order :do
              (let ((element (dom-widget-element record)))
                (loop :while (and (not (same-p cursor lui.js:+null+))
                                  (equal (property cursor "style"
                                                   "visibility")
                                         "hidden"))
                      :do (setf cursor (property cursor "nextSibling")))
                (unless (same-p element cursor)
                  (invoke layer "insertBefore" element cursor))
                (setf cursor (property element "nextSibling")))))
      (setf (web-app-overlay-order app) order))))

(fn (sync-overlay hash-table) ((app web-app))
  (let* ((entries (overlay-candidates app (context-root (web-app-context
                                                         app))))
         (records (reconcile-overlay app entries))
         (external (make-hash-table :test 'eq)))
    (loop :for (node key interactive) :across entries
          :for record :across records :do
          (let* ((kind (car key)) (label (eq kind :label)) (widget
                                                            (element-content
                                                             node))
                 (element (dom-widget-element record))
                 (text (if label (lui.widgets:widget-text widget)
                           (or (lui.widgets:widget-accessible-name widget)
                               (lui.widgets:widget-text widget))))
                 (appearance (and label (list interactive
                                              (lui.widgets:widget-font-size
                                               widget)

                                              (lui.widgets:widget-font-family
                                               widget)

                                              (lui.widgets:widget-font-weight
                                               widget)

                                              (lui.widgets:widget-foreground
                                               widget)
                                              (geometry-center-x
                                               (widget-geometry widget))))))
            (unless (dom-widget-geometry record)
              (setf (property element "style" "cssText")
                    (if label
                        "position:absolute;display:block;margin:0;padding:0;border:0;white-space:pre-wrap;overflow:hidden;user-select:text;-webkit-user-select:text;cursor:text"
                        "position:absolute;display:block;margin:0;padding:0;border:0;opacity:0;pointer-events:none;user-select:none")))
            (position-dom-widget record
                                 (if label (lui.draw::selection-area
                                            (web-app-renderer app) node)
                                     (element-box node)) (element-clip node))
            (unless (equal appearance (dom-widget-style record))
              (let ((font (lui.draw::widget-font (web-app-renderer app)
                                                 widget))
                    (style (property element "style")))
                (setf (property style "pointerEvents") (if
                                                        interactive "none" "auto")
                      (property style "font") (lui.font:font-css font)
                      (property style "lineHeight")
                      (css-pixels (lui.font:line-height font))
                      (property style "color")
                      (lui.widgets:widget-foreground widget)
                      (property style "textAlign")
                      (if (and label (geometry-center-x (widget-geometry
                                                         widget))) "center" "left")
                      (dom-widget-style record) appearance)))
            (if label (setf (gethash node external) t)
                (let ((state (list (not (null (lui.widgets:widget-value
                                               widget)))
                                   (lui.widgets:widget-disabled-p widget))))
                  (unless (equal state (dom-widget-state record))
                    (setf (dom-widget-state record) state
                          (property element "disabled") (if (second state) t
                                                             nil))
                    (when (member kind '(:checkbox :radio :tab))
                      (invoke element "setAttribute"
                              (if (eq kind :tab)
                                  "aria-pressed" "aria-checked")
                              (if (first state) "true" "false"))))))
            (unless (equal text (dom-widget-text record))
              (if label (setf (property element "textContent") text)
                  (invoke element "setAttribute" "aria-label" text))
              (setf (dom-widget-text record) text)))) external))

(fn (queue-page-scroll t) ((app web-app) (delta real) &optional ((velocity
                                                                  real) 0))
  (incf (web-app-scroll-delta app) delta)
  (setf (web-app-velocity app) (max -4 (min 4 velocity))
        (web-app-scroll-time app) (invoke (global "performance") "now"))
  (refresh app))

(fn (frame-scroll-delta real) ((app web-app))
  (let ((delta (shiftf (web-app-scroll-delta app) 0))
        (speed (web-app-velocity app)))
    (unless (zerop speed)
      (let* ((now (invoke (global "performance") "now"))
             (elapsed (min 50 (- now (web-app-scroll-time app))))
             (decay (exp (/ (- elapsed) 190))))
        (incf delta (* speed 190 (- 1 decay)))
        (setf (web-app-scroll-time app) now
              (web-app-velocity app)
              (if (< (* (abs speed) decay) 0.02f0) 0 (* speed decay)))))
    delta))

(fn (draw-frame t) ((app web-app))
  (let* ((canvas (web-app-canvas app)) (g (web-app-graphics app))
         (context (web-app-context app)) (*unit* 8)
         (width (property canvas "clientWidth"))
         (port (web-app-scrollport app))
         (stage (web-app-stage app))
         (origin (if port (page-offset stage port) 0))
         (delta (if port (frame-scroll-delta app) 0))
         (height (if port (page-viewport-height port)
                     (property canvas "clientHeight")))
         (scale (property (global "window") "devicePixelRatio"))
         (events (nreverse (shiftf (web-app-events app) nil))))
    (let ((w (round (* width scale))) (h (round (* height scale))))
      (unless (= w (property canvas "width"))
        (setf (property canvas "width") w))
      (unless (= h (property canvas "height"))
        (setf (property canvas "height") h)))
    (setf (lui.frame::context-page-height-p context) (not (null port))
          (lui.frame::context-page-top context)
          (max 0 (min (- (context-height context) height) (+ origin delta))))
    (with-frame (context width height :events events)
      (funcall (web-app-callback app)))
    (when port
      (let ((page-height (context-height context))
            (requested (shiftf (lui.frame::context-requested-page-top context)
                               nil)))
        (when requested (setf delta (- requested origin)))
        (let ((offset (max 0 (min (- page-height height) (+ origin delta)))))
          (setf (web-app-viewport-offset app) offset
                (property canvas "luiViewportOffset") offset
                (property stage "style" "height") (css-pixels page-height)
                (property canvas "style" "height") (css-pixels height)))))
    (invoke g "setTransform" scale 0 0 scale 0 0)
    (setf (property g "fillStyle") "#202432")
    (invoke g "fillRect" 0 0 width height)
    (invoke g "translate" 0 (- (web-app-viewport-offset app)))
    (invoke g "save")
    (unwind-protect
         (paint-frame (web-app-renderer app) context (sync-overlay app)
                      (when port
                        (make-box :x 0 :y (web-app-viewport-offset app)
                                  :width width :height height)))
      (invoke g "restore"))
    ;; Commit the matching scroll position only after the pixels and DOM are ready.
    (when (and port (not (zerop delta)))
      (page-scroll-by port delta)
      (when (< (abs (- (page-offset stage port) origin)) 0.01f0)
        (setf (web-app-velocity app) 0)))
    (unless (zerop (web-app-velocity app)) (refresh app))
    (when (some (lambda (e) (not (eq :move (event-kind e)))) events)
      (refresh app))
    (lui.web.input:update-accessibility canvas context)
    (schedule-deadline app)))

(fn (refresh t) ((app web-app))
  "Request one redraw of a mounted application, coalescing pending requests."
  (when (and (web-app-alive-p app) (not (web-app-pending-p app)))
    (cancel-deadline app)
    (setf (web-app-pending-p app) t)
    (flet ((enqueue ()
             (setf (web-app-deadline-timer app) nil
                   (web-app-animation-frame app)
                   (invoke (global) "requestAnimationFrame"
                           (lui.js:callback
                            (lambda (time)
                              (declare (ignore time))
                              (setf (web-app-pending-p app) nil
                                    (web-app-animation-frame app) nil)
                              (when (web-app-alive-p app)
                                (draw-frame app))))))))
      (let* ((context (web-app-context app))
             (wait (if (context-root context)
                       (lui.frame::frame-wait context t) 0)))
        (if (zerop wait)
            (enqueue)
            (setf (web-app-deadline-timer app)
                  (invoke (global) "setTimeout"
                          (lui.js:callback #'enqueue)
                          (ceiling (* wait 1000)))))))))

(fn (default-scroll-mode symbol) ()
  (if (property (invoke (global "window") "matchMedia"
                        "(pointer: coarse)") "matches") :page :viewport))

(fn (mount web-app)
    (host (callback function) &key (min-fps lui.frame::*min-fps*)
          (max-fps lui.frame::*max-fps*)
          ((scroll-mode (member :page :viewport)) (default-scroll-mode)))
  "Mount a Canvas 2D app in HOST. SCROLL-MODE is :PAGE for content expansion or
:VIEWPORT for a fixed embedded view; the default is :PAGE on coarse pointers."
  (assert (< 0 min-fps)) (assert (<= min-fps max-fps))
  (let* ((page-scroll-p (eq scroll-mode :page))
         (port (and page-scroll-p (page-scrollport host)))
         (stage (invoke (global "document") "createElement" "div"))
         (overlay (invoke (global "document") "createElement" "div"))
         (canvas (invoke (global "document") "createElement" "canvas"))
         (g (invoke canvas "getContext" "2d"))
         (renderer (canvas-renderer canvas g))
         (context (make-context :min-fps min-fps :max-fps max-fps
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width))))
         (app (make-web-app :host host :stage stage :overlay overlay
                            :canvas canvas :graphics g
                            :renderer renderer :context context
                            :callback callback :scrollport port))
         (resize (lui.js:callback
                  (lambda (&rest ignored)
                    (declare (ignore ignored)) (refresh app)))))
    (setf (property canvas "style" "cssText")
          "display:block;width:100%;height:100%;touch-action:none"
          (property canvas "luiApp") t
          (property canvas "luiViewportOffset") 0)
    (setf (property stage "style" "cssText")
          "position:relative;width:100%;height:100%;overflow:hidden;-webkit-tap-highlight-color:transparent"
          (property overlay "style" "cssText")
          "position:absolute;inset:0;pointer-events:none")
    (when page-scroll-p
      (setf (property stage "style" "touchAction") "pinch-zoom"
            (property stage "style" "overflow") "clip"
            (property canvas "style" "position") "sticky"
            (property canvas "style" "top") "0"
            (property canvas "style" "height") (css-pixels
                                                (page-viewport-height port))
            (property stage "style" "height") (css-pixels
                                               (page-viewport-height port))))
    (invoke stage "appendChild" canvas)
    (invoke stage "appendChild" overlay)
    (invoke host "appendChild" stage)
    (setf (web-app-cleanup app)
          (lui.web.input:install-input
           stage canvas context (lambda (event) (queue-event app event))
           :page-scroll-p page-scroll-p
           :scroll-page (lambda (delta &optional (speed 0))
                          (queue-page-scroll app delta speed)))
          (web-app-resize app) resize
          (web-app-observer app) (new (global "ResizeObserver") resize))
    (invoke (web-app-observer app) "observe" host)
    (when (and port (not (same-p port (global "window")))
               (not (same-p port host)))
      (invoke (web-app-observer app) "observe" port))
    (invoke (global "window") "addEventListener" "resize" resize)
    (when port
      (setf (web-app-scroll-listener app)
            (lui.js:callback (lambda (&rest ignored)
                               (declare (ignore ignored))
                               ;; A committed, prepainted scroll needs no second frame. Native
                               ;; scrolling and clamping to a different offset still repaint.
                               (unless (< (abs (- (page-offset stage port)
                                                  (web-app-viewport-offset
                                                   app))) 0.01f0)
                                 (refresh app)))))
      (invoke port "addEventListener" "scroll"
              (web-app-scroll-listener app)))
    (push app *mounted-apps*)
    (refresh app) app))

(fn (unmount t) ((app web-app))
  "Cancel scheduled work and release the mounted canvas and input listeners."
  (when (web-app-alive-p app)
    (setf *mounted-apps* (remove app *mounted-apps*)
          (web-app-alive-p app) nil)
    (cancel-deadline app)
    (when (web-app-animation-frame app)
      (invoke (global) "cancelAnimationFrame"
              (web-app-animation-frame app)))
    (invoke (web-app-observer app) "disconnect")
    (invoke (global "window") "removeEventListener" "resize"
            (web-app-resize app))
    (when (web-app-scrollport app)
      (invoke (web-app-scrollport app) "removeEventListener"
              "scroll" (web-app-scroll-listener app)))
    (funcall (web-app-cleanup app))
    (lui.font:close-font (renderer-font (web-app-renderer app)))
    (setf (web-app-overlay-order app) #()
          (web-app-overlay-cache app) nil
          (web-app-overlay-geometry app) nil)
    (invoke (web-app-stage app) "remove")))

(fn (css-size t) (value fallback)
  (if value (invoke (invoke (global) "String" value) "concat" "px") fallback))

(fn (run-web web-app) ((draw function) &key title width height (interactive
                                                                t))
  (declare (ignore interactive))
  (setf (property (global "document") "title") title)
  (let ((scroll-mode (if height :viewport (default-scroll-mode)))
        (host (invoke (global "document") "createElement" "main")))
    (invoke host "setAttribute" "aria-label" title)
    (setf (property host "style" "width")
          (css-size width "100%")
          (property host "style" "height")
          (css-size height (if (eq scroll-mode :page) "auto" "100vh")))
    (invoke (property (global "document") "body") "appendChild" host)
    (mount host draw :scroll-mode scroll-mode)))

(register-backend :web #'run-web)
