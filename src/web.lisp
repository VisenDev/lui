(defpackage #:lui.web
  (:use #:cl #:lui.fn #:lui #:lui.layout #:lui.frame #:lui.draw)
  (:export #:mount #:unmount #:refresh))
(in-package #:lui.web)

(defstruct web-app
  host stage overlay canvas graphics renderer context callback cleanup observer resize
  scrollport (viewport-offset 0) (scroll-delta 0) (velocity 0) (scroll-time 0)
  (overlay-order #() :type vector) overlay-geometry overlay-cache
  animation-frame deadline-timer events pending-p (alive-p t))

(fn (page-scrollport t) (host)
  (do ((element host (jscl/ffi:oget element "parentElement")))
      ((eq element #j:null) #j:window)
    (let ((overflow (jscl/ffi:oget
                     (#j:window:getComputedStyle element) "overflowY")))
      (when (or (equal overflow #j"auto") (equal overflow #j"scroll"))
        (return element)))))

(fn (page-viewport-height real) (port)
  (if (eq port #j:window)
      #j:window:innerHeight
      (jscl/ffi:oget port "clientHeight")))

(fn (page-offset real) (stage port)
  (let ((top (jscl/ffi:oget
              ((jscl/ffi:oget stage "getBoundingClientRect")) "top")))
    (if (eq port #j:window)
        (- top)
        (- (+ (jscl/ffi:oget
               ((jscl/ffi:oget port "getBoundingClientRect")) "top")
              (jscl/ffi:oget port "clientTop"))
           top))))

(fn (page-scroll-by t) (port delta)
  (let ((options (jscl/ffi:new #j:Object)))
    (setf (jscl/ffi:oget options "top") delta
          (jscl/ffi:oget options "behavior") #j"instant")
    ((jscl/ffi:oget port "scrollBy") options)))

(fn (rounded-path t) (g (box box) radius &optional (inset 0))
  ((jscl/ffi:oget g "beginPath"))
  ((jscl/ffi:oget g "roundRect")
   (+ inset (box-x box)) (+ inset (box-y box))
   (max 0 (- (box-width box) (* 2 inset)))
   (max 0 (- (box-height box) (* 2 inset))) (max 0 (- radius inset))))

(fn (canvas-renderer renderer) (canvas g)
  (let* ((tile (#j:document:createElement #j"canvas"))
         (ink ((jscl/ffi:oget tile "getContext") #j"2d"))
         (sample (#j:document:createElement #j"canvas"))
         (blur ((jscl/ffi:oget sample "getContext") #j"2d")))
    (setf (jscl/ffi:oget tile "width") 2 (jscl/ffi:oget tile "height") 2)
    (let ((patterns (make-hash-table :test 'equal)))
      (make-renderer
       :font (lui.font:open-font)
       :surface
       (lambda (box radius color alpha &optional stroke)
         (setf (jscl/ffi:oget g "globalAlpha") alpha)
         (if stroke
             (setf (jscl/ffi:oget g "lineWidth") stroke
                   (jscl/ffi:oget g "strokeStyle") (jscl/ffi:jsstring color))
             (setf (jscl/ffi:oget g "fillStyle") (jscl/ffi:jsstring color)))
         (if (zerop radius)
             (if stroke
                 ((jscl/ffi:oget g "strokeRect")
                  (+ (box-x box) (/ stroke 2))
                  (+ (box-y box) (/ stroke 2))
                  (max 0 (- (box-width box) stroke))
                  (max 0 (- (box-height box) stroke)))
                 ((jscl/ffi:oget g "fillRect") (box-x box) (box-y box)
                  (box-width box) (box-height box)))
             (progn
               (rounded-path g box radius (if stroke (/ stroke 2) 0))
               (if stroke
                   ((jscl/ffi:oget g "stroke"))
                   ((jscl/ffi:oget g "fill"))))))
       :polygons
       (lambda (paths color alpha)
         (setf (jscl/ffi:oget g "fillStyle") (jscl/ffi:jsstring color)
               (jscl/ffi:oget g "globalAlpha") alpha)
         ((jscl/ffi:oget g "beginPath"))
         (loop :for path :across paths :do
           (when (plusp (length path))
             ((jscl/ffi:oget g "moveTo") (car (aref path 0)) (cdr (aref path 0)))
             (loop :for i :from 1 :below (length path) :for p := (aref path i) :do
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
       (lambda (box border color)
         (let ((pattern (gethash color patterns)))
           (unless pattern
             ((jscl/ffi:oget ink "clearRect") 0 0 2 2)
             (setf (jscl/ffi:oget ink "fillStyle") (jscl/ffi:jsstring color))
             ((jscl/ffi:oget ink "fillRect") 0 0 1 1)
             ((jscl/ffi:oget ink "fillRect") 1 1 1 1)
             (setf pattern ((jscl/ffi:oget g "createPattern") tile #j"repeat")
                   (gethash color patterns) pattern))
           (setf (jscl/ffi:oget g "globalAlpha") 1
                 (jscl/ffi:oget g "fillStyle") pattern))
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
                  (offset (jscl/ffi:oget canvas "luiViewportOffset"))
                  (x (max 0 (box-x box)))
                  (y (max offset (box-y box)))
                  (w (max 0 (- (min (+ (box-x box) (box-width box))
                                        (/ (jscl/ffi:oget canvas "width") scale)) x)))
                  (h (max 0 (- (min (+ (box-y box) (box-height box))
                                        (+ offset (/ (jscl/ffi:oget canvas "height") scale))) y)))
                  (step (max 1 (/ frost 2)))
                  (sw (max 1 (ceiling (/ w step))))
                  (sh (max 1 (ceiling (/ h step)))))
             ;; Restrict the scratch bitmap to the visible artwork. The original
             ;; rounded surface still supplies the destination clip.
             (when (and (plusp w) (plusp h))
               (when (> sw (jscl/ffi:oget sample "width"))
                 (setf (jscl/ffi:oget sample "width") sw))
               (when (> sh (jscl/ffi:oget sample "height"))
                 (setf (jscl/ffi:oget sample "height") sh))
               ((jscl/ffi:oget blur "clearRect") 0 0 sw sh)
               ((jscl/ffi:oget blur "drawImage") canvas
                (* scale x) (* scale (- y offset)) (* scale w) (* scale h) 0 0 sw sh)
               ((jscl/ffi:oget g "save"))
               (rounded-path g box radius)
               ((jscl/ffi:oget g "clip"))
               (setf (jscl/ffi:oget g "globalAlpha") 1)
               ((jscl/ffi:oget g "drawImage") sample 0 0 sw sh x y w h)
               ((jscl/ffi:oget g "restore"))))))))))

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
    (#j:clearTimeout (web-app-deadline-timer app))
    (setf (web-app-deadline-timer app) nil)))

(fn (schedule-deadline t) ((app web-app))
  (unless (web-app-pending-p app)
    (cancel-deadline app)
    (let ((delay (lui.frame::frame-wait (web-app-context app))))
      (if (zerop delay)
          (refresh app)
          (setf (web-app-deadline-timer app)
                (#j:setTimeout (lambda () (refresh app))
                               (ceiling (* delay 1000))))))))

(defstruct dom-widget key element text style state geometry hidden-p)

(defparameter *overlay-cache-limit* 32)

(defstruct overlay-region x y right bottom candidate visible)

(fn (overlay-candidates (vector list)) ((app web-app) (root element))
  ;; Earlier regions in this walk paint in front of later ones. An unchanged
  ;; prefix therefore has exactly the same occlusion as on the previous frame.
  (let ((previous (web-app-overlay-geometry app)) seen bands
        (entries (make-array 0 :element-type 'list :adjustable t :fill-pointer 0)))
    (labels ((index-region (region)
               (do ((band (floor (overlay-region-y region) 64) (1+ band))
                    (end (ceiling (overlay-region-bottom region) 64)))
                   ((>= band end))
                 (push region (gethash band bands))))
             (uncovered-p (x y right bottom)
               (do ((band (floor y 64) (1+ band)) (end (ceiling bottom 64)))
                   ((>= band end) t)
                 (dolist (other (gethash band bands))
                   (when (and (< x (overlay-region-right other)) (< (overlay-region-x other) right)
                              (< y (overlay-region-bottom other)) (< (overlay-region-y other) bottom))
                     (return-from uncovered-p nil)))))
             (region-visible-p (clip candidate)
               (let* ((x (box-x clip)) (y (box-y clip))
                      (right (+ x (box-width clip))) (bottom (+ y (box-height clip)))
                      (old (pop previous)))
                 (if (and old (= x (overlay-region-x old)) (= y (overlay-region-y old))
                          (= right (overlay-region-right old)) (= bottom (overlay-region-bottom old))
                          (eq candidate (overlay-region-candidate old)))
                     (progn (push old seen) (overlay-region-visible old))
                     (progn
                       (unless bands
                         (setf previous nil bands (make-hash-table))
                         (dolist (region seen) (index-region region)))
                       (let* ((visible (and candidate (uncovered-p x y right bottom)))
                              (region (make-overlay-region :x x :y y :right right :bottom bottom
                                                           :candidate candidate :visible visible)))
                         (push region seen)
                         (index-region region)
                         visible)))))
             (visit (node path interactive)
               (let* ((key (if (element-id node) (list :id (element-id node)) path))
                      (children (element-children node)) (clip (element-clip node))
                      (widget (element-content node)))
                 (let ((count (length children)))
                   (dotimes (offset count)
                     (let ((i (- count offset 1)))
                       (visit (aref children i) (cons i key)
                              (or interactive (element-interactive-p node))))))
                 (when (and (plusp (box-width clip)) (plusp (box-height clip))
                            (or (lui.widgets:widget-p widget) (element-interactive-p node)))
                   (let ((kind (and (lui.widgets:widget-p widget) (lui.widgets:widget-kind widget))))
                     (when (region-visible-p clip
                             (and (case kind ((:cell :label :button :tab :list-item :checkbox :radio) t))
                                  (or (not (eq kind :label))
                                      (lui:toolkit-native-labels-p (lui.widgets:widget-style widget)))
                                  (not (lui.widgets:widget-painter widget))))
                       (vector-push-extend (list node (cons kind key) interactive) entries)))))))
      (visit root nil nil))
    (setf (web-app-overlay-geometry app) (nreverse seen))
    (reverse entries)))

(fn (css-pixels t) ((n real))
  ((jscl/ffi:oget (#j:String n) "concat") #j"px"))

(fn (position-dom-widget null) ((record dom-widget) (box box) (clip box))
  (let* ((x (box-x box)) (y (box-y box)) (w (box-width box)) (h (box-height box))
         (left (- (box-x clip) x)) (top (- (box-y clip) y))
         (right (- w left (box-width clip))) (bottom (- h top (box-height clip)))
         (old (dom-widget-geometry record)))
    (destructuring-bind (&optional ox oy ow oh otop oright obottom oleft) old
      (unless (and (eql x ox) (eql y oy) (eql w ow) (eql h oh)
                   (eql top otop) (eql right oright) (eql bottom obottom) (eql left oleft))
        (let ((style (jscl/ffi:oget (dom-widget-element record) "style")))
          (unless (eql x ox) (setf (jscl/ffi:oget style "left") (css-pixels x)))
          (unless (eql y oy) (setf (jscl/ffi:oget style "top") (css-pixels y)))
          (unless (eql w ow) (setf (jscl/ffi:oget style "width") (css-pixels w)))
          (unless (eql h oh) (setf (jscl/ffi:oget style "height") (css-pixels h)))
          (unless (and (eql top otop) (eql right oright) (eql bottom obottom) (eql left oleft))
            (setf (jscl/ffi:oget style "clipPath")
                  (if (= 0 top right bottom left) #j"none"
                      ((jscl/ffi:oget #j"inset(" "concat")
                       top #j"px " right #j"px " bottom #j"px " left #j"px)"))))
          (setf (dom-widget-geometry record) (list x y w h top right bottom left))))))
  nil)

(fn (make-semantic-button t) ((app web-app) (node element) (kind symbol))
  ;; The canvas keeps pointer capture and toolkit keyboard navigation. Native
  ;; button activation also lets assistive technology invoke the same action.
  (let ((button (#j:document:createElement #j"button")) (id (element-id node)))
    (setf (jscl/ffi:oget button "type") #j"button"
          (jscl/ffi:oget button "tabIndex") -1
          (jscl/ffi:oget button "onclick")
          (lambda (event)
            (declare (ignore event))
            (queue-event app (make-event :kind :activate :id id))))
    (when (member kind '(:checkbox :radio))
      ((jscl/ffi:oget button "setAttribute") #j"role"
       (jscl/ffi:jsstring (string-downcase (symbol-name kind)))))
    button))

(fn (same-overlay-order-p boolean) ((records (vector dom-widget)) (entries (vector list)))
  (and (= (length records) (length entries))
       (loop for record across records for entry across entries
             always (equal (dom-widget-key record) (second entry)))))

(fn (reconcile-overlay (vector dom-widget)) ((app web-app) (entries (vector list)))
  ;; Look up keyed nodes and inspect DOM order only when membership or order changes.
  (let ((order (web-app-overlay-order app)))
    (when (same-overlay-order-p order entries)
      (return-from reconcile-overlay order))
    (let ((old (make-hash-table :test 'equal)) (layer (web-app-overlay app))
          (next (make-array 0 :element-type 'dom-widget :adjustable t :fill-pointer 0))
          (cache (web-app-overlay-cache app)) hidden)
      (loop for record across order do (setf (gethash (dom-widget-key record) old) record))
      (dolist (record cache) (setf (gethash (dom-widget-key record) old) record))
      (loop for entry across entries do
        (destructuring-bind (node key interactive) entry
          (declare (ignore interactive))
          (let* ((kind (car key))
                 (record (or (gethash key old)
                             (make-dom-widget :key key :element
                               (if (eq kind :label) (#j:document:createElement #j"span")
                                   (make-semantic-button app node kind))))))
            (remhash key old)
            (when (dom-widget-hidden-p record)
              (setf (dom-widget-hidden-p record) nil
                    (jscl/ffi:oget (dom-widget-element record) "style" "visibility") #j"visible"))
            (vector-push-extend record next))))
      ;; Prefer newly hidden nodes over older cached entries when evicting.
      (loop for record across order do
        (when (gethash (dom-widget-key record) old)
          (setf (dom-widget-hidden-p record) t
                (jscl/ffi:oget (dom-widget-element record) "style" "visibility") #j"hidden")
          (push record hidden)))
      (setf hidden (nconc hidden (loop for record in cache
                                       when (gethash (dom-widget-key record) old) collect record)))
      (loop for record in (nthcdr *overlay-cache-limit* hidden)
            do ((jscl/ffi:oget (dom-widget-element record) "remove")))
      (when (nthcdr *overlay-cache-limit* hidden)
        (setf (cdr (nthcdr (1- *overlay-cache-limit*) hidden)) nil))
      (setf (web-app-overlay-cache app) hidden)
      (setf order next)
      (let ((cursor (jscl/ffi:oget layer "firstChild")))
        (loop for record across order do
          (let ((element (dom-widget-element record)))
            (loop while (and (not (eq cursor #j:null))
                             (equal (jscl/ffi:oget cursor "style" "visibility") #j"hidden"))
                  do (setf cursor (jscl/ffi:oget cursor "nextSibling")))
            (unless (eq element cursor) ((jscl/ffi:oget layer "insertBefore") element cursor))
            (setf cursor (jscl/ffi:oget element "nextSibling")))))
      (setf (web-app-overlay-order app) order))))

(fn (sync-overlay hash-table) ((app web-app))
  (let* ((entries (overlay-candidates app (context-root (web-app-context app))))
         (records (reconcile-overlay app entries))
         (external (make-hash-table :test 'eq)))
    (loop for (node key interactive) across entries for record across records do
      (let* ((kind (car key)) (label (eq kind :label)) (widget (element-content node))
             (element (dom-widget-element record))
             (text (if label (lui.widgets:widget-text widget)
                       (or (lui.widgets:widget-accessible-name widget) (lui.widgets:widget-text widget))))
             (appearance (and label (list interactive (lui.widgets:widget-font-size widget)
                                          (lui.widgets:widget-font-family widget)
                                          (lui.widgets:widget-font-weight widget)
                                          (lui.widgets:widget-foreground widget)
                                          (geometry-center-x (widget-geometry widget))))))
        (unless (dom-widget-geometry record)
          (setf (jscl/ffi:oget element "style" "cssText")
                (if label
                    #j"position:absolute;display:block;margin:0;padding:0;border:0;white-space:pre-wrap;overflow:hidden;user-select:text;-webkit-user-select:text;cursor:text"
                    #j"position:absolute;display:block;margin:0;padding:0;border:0;opacity:0;pointer-events:none;user-select:none")))
        (position-dom-widget record
                             (if label (lui.draw::selection-area (web-app-renderer app) node)
                                 (element-box node)) (element-clip node))
        (unless (equal appearance (dom-widget-style record))
          (let ((font (lui.draw::widget-font (web-app-renderer app) widget))
                (style (jscl/ffi:oget element "style")))
            (setf (jscl/ffi:oget style "pointerEvents") (if interactive #j"none" #j"auto")
                  (jscl/ffi:oget style "font") (jscl/ffi:jsstring (lui.font:font-css font))
                  (jscl/ffi:oget style "lineHeight") (css-pixels (lui.font:line-height font))
                  (jscl/ffi:oget style "color") (jscl/ffi:jsstring (lui.widgets:widget-foreground widget))
                  (jscl/ffi:oget style "textAlign")
                  (if (and label (geometry-center-x (widget-geometry widget))) #j"center" #j"left")
                  (dom-widget-style record) appearance)))
        (if label (setf (gethash node external) t)
            (let ((state (list (not (null (lui.widgets:widget-value widget)))
                               (lui.widgets:widget-disabled-p widget))))
              (unless (equal state (dom-widget-state record))
                (setf (dom-widget-state record) state
                      (jscl/ffi:oget element "disabled") (if (second state) #j:true #j:false))
                (when (member kind '(:checkbox :radio :tab))
                  ((jscl/ffi:oget element "setAttribute")
                   (if (eq kind :tab) #j"aria-pressed" #j"aria-checked")
                   (if (first state) #j"true" #j"false"))))))
        (unless (equal text (dom-widget-text record))
          (if label (setf (jscl/ffi:oget element "textContent") (jscl/ffi:jsstring text))
              ((jscl/ffi:oget element "setAttribute") #j"aria-label" (jscl/ffi:jsstring text)))
          (setf (dom-widget-text record) text))))
    external))

(fn (queue-page-scroll t) ((app web-app) (delta real) &optional ((velocity real) 0))
  (incf (web-app-scroll-delta app) delta)
  (setf (web-app-velocity app) (max -4 (min 4 velocity))
        (web-app-scroll-time app) (#j:performance:now))
  (refresh app))

(fn (frame-scroll-delta real) ((app web-app))
  (let ((delta (shiftf (web-app-scroll-delta app) 0))
        (speed (web-app-velocity app)))
    (unless (zerop speed)
      (let* ((now (#j:performance:now))
             (elapsed (min 50 (- now (web-app-scroll-time app))))
             (decay (exp (/ (- elapsed) 190))))
        (incf delta (* speed 190 (- 1 decay)))
        (setf (web-app-scroll-time app) now
              (web-app-velocity app) (if (< (* (abs speed) decay) 0.02) 0 (* speed decay)))))
    delta))

(fn (draw-frame t) ((app web-app))
  (let* ((canvas (web-app-canvas app)) (g (web-app-graphics app))
         (context (web-app-context app)) (*unit* 8)
         (width (jscl/ffi:oget canvas "clientWidth"))
         (port (web-app-scrollport app))
         (stage (web-app-stage app))
         (origin (if port (page-offset stage port) 0))
         (delta (if port (frame-scroll-delta app) 0))
         (height (if port (page-viewport-height port)
                     (jscl/ffi:oget canvas "clientHeight")))
         (scale #j:window:devicePixelRatio)
         (events (nreverse (shiftf (web-app-events app) nil))))
    (let ((w (round (* width scale))) (h (round (* height scale))))
      (unless (= w (jscl/ffi:oget canvas "width"))
        (setf (jscl/ffi:oget canvas "width") w))
      (unless (= h (jscl/ffi:oget canvas "height"))
        (setf (jscl/ffi:oget canvas "height") h)))
    (setf (lui.frame::context-page-height-p context) (not (null port))
          (lui.frame::context-page-top context)
          (max 0 (min (- (context-height context) height) (+ origin delta))))
    (with-frame (context width height :events events)
      (funcall (web-app-callback app)))
    (when port
      (let* ((page-height (context-height context))
             (requested (shiftf (lui.frame::context-requested-page-top context) nil)))
        (when requested (setf delta (- requested origin)))
        (let ((offset (max 0 (min (- page-height height) (+ origin delta)))))
          (setf (web-app-viewport-offset app) offset
                (jscl/ffi:oget canvas "luiViewportOffset") offset
                (jscl/ffi:oget stage "style" "height") (css-pixels page-height)
                (jscl/ffi:oget canvas "style" "height") (css-pixels height)))))
    ((jscl/ffi:oget g "setTransform") scale 0 0 scale 0 0)
    (setf (jscl/ffi:oget g "fillStyle") #j"#202432")
    ((jscl/ffi:oget g "fillRect") 0 0 width height)
    ((jscl/ffi:oget g "translate") 0 (- (web-app-viewport-offset app)))
    ((jscl/ffi:oget g "save"))
    (unwind-protect
         (paint-frame (web-app-renderer app) context (sync-overlay app)
                      (when port
                        (make-box :x 0 :y (web-app-viewport-offset app)
                                  :width width :height height)))
      ((jscl/ffi:oget g "restore")))
    ;; Commit the matching scroll position only after the pixels and DOM are ready.
    (when (and port (not (zerop delta)))
      (page-scroll-by port delta)
      (when (< (abs (- (page-offset stage port) origin)) 0.01)
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

(fn (default-scroll-mode symbol) ()
  (if (jscl/ffi:clbool
       (jscl/ffi:oget (#j:window:matchMedia #j"(pointer: coarse)") "matches"))
      :page :viewport))

(fn (mount web-app) (host (callback function) &key (min-fps lui.frame::*min-fps*)
           (max-fps lui.frame::*max-fps*)
           ((scroll-mode (member :page :viewport)) (default-scroll-mode)))
  "Mount a Canvas 2D app in HOST. SCROLL-MODE is :PAGE for content expansion or
:VIEWPORT for a fixed embedded view; the default is :PAGE on coarse pointers."
  (assert (< 0 min-fps)) (assert (<= min-fps max-fps))
  (let* ((page-scroll-p (eq scroll-mode :page))
         (port (and page-scroll-p (page-scrollport host)))
         (stage (#j:document:createElement #j"div"))
         (labels (#j:document:createElement #j"div"))
         (canvas (#j:document:createElement #j"canvas"))
         (g ((jscl/ffi:oget canvas "getContext") #j"2d"))
         (renderer (canvas-renderer canvas g))
         (context (make-context
                   :min-fps min-fps :max-fps max-fps
                   :measure (lambda (widget width)
                              (measure-widget renderer widget width))))
         (app (make-web-app :host host :stage stage :overlay labels :canvas canvas :graphics g
                            :renderer renderer :context context
                            :callback callback :scrollport port))
         (resize (lambda (&rest ignored)
                   (declare (ignore ignored)) (refresh app))))
    (setf (jscl/ffi:oget canvas "style" "cssText")
          #j"display:block;width:100%;height:100%;touch-action:none"
          (jscl/ffi:oget canvas "luiApp") app
          (jscl/ffi:oget canvas "luiViewportOffset") 0)
    (setf (jscl/ffi:oget stage "style" "cssText")
          #j"position:relative;width:100%;height:100%;overflow:hidden;-webkit-tap-highlight-color:transparent"
          (jscl/ffi:oget labels "style" "cssText")
          #j"position:absolute;inset:0;pointer-events:none")
    (when page-scroll-p
      (setf (jscl/ffi:oget stage "style" "touchAction") #j"pinch-zoom"
            (jscl/ffi:oget stage "style" "overflow") #j"clip"
            (jscl/ffi:oget canvas "style" "position") #j"sticky"
            (jscl/ffi:oget canvas "style" "top") #j"0"
            (jscl/ffi:oget canvas "style" "height") (css-pixels (page-viewport-height port))
            (jscl/ffi:oget stage "style" "height") (css-pixels (page-viewport-height port))))
    ((jscl/ffi:oget stage "appendChild") canvas)
    ((jscl/ffi:oget stage "appendChild") labels)
    ((jscl/ffi:oget host "appendChild") stage)
    (setf (web-app-cleanup app)
          (lui.web.input:install-input
           stage canvas context (lambda (event) (queue-event app event))
           :page-scroll-p page-scroll-p
           :scroll-page (lambda (delta &optional (speed 0)) (queue-page-scroll app delta speed)))
          (web-app-resize app) resize
          (web-app-observer app) (jscl/ffi:new #j:ResizeObserver resize))
    ((jscl/ffi:oget (web-app-observer app) "observe") host)
    (when (and port (not (eq port #j:window)) (not (eq port host)))
      ((jscl/ffi:oget (web-app-observer app) "observe") port))
    (#j:window:addEventListener #j"resize" resize)
    (when port ((jscl/ffi:oget port "addEventListener") #j"scroll" resize))
    (refresh app)
    app))

(fn (unmount t) ((app web-app))
  "Cancel scheduled work and release the mounted canvas and input listeners."
  (when (web-app-alive-p app)
    (setf (web-app-alive-p app) nil)
    (cancel-deadline app)
    (when (web-app-animation-frame app)
      (#j:cancelAnimationFrame (web-app-animation-frame app)))
    ((jscl/ffi:oget (web-app-observer app) "disconnect"))
    (#j:window:removeEventListener #j"resize" (web-app-resize app))
    (when (web-app-scrollport app)
      ((jscl/ffi:oget (web-app-scrollport app) "removeEventListener") #j"scroll" (web-app-resize app)))
    (funcall (web-app-cleanup app))
    (lui.font:close-font (renderer-font (web-app-renderer app)))
    (setf (web-app-overlay-order app) #()
          (web-app-overlay-cache app) nil
          (web-app-overlay-geometry app) nil)
    ((jscl/ffi:oget (web-app-stage app) "remove"))))

(fn (css-size t) (value fallback)
  (if value ((jscl/ffi:oget (#j:String value) "concat") #j"px") fallback))

(fn (run-web web-app) ((draw function) &key title width height (interactive t))
  (declare (ignore interactive))
  (setf (jscl/ffi:oget #j:document "title") (jscl/ffi:jsstring title))
  (let* ((scroll-mode (if height :viewport (default-scroll-mode)))
         (host (#j:document:createElement #j"main")))
    ((jscl/ffi:oget host "setAttribute") #j"aria-label"
     (jscl/ffi:jsstring title))
    (setf (jscl/ffi:oget host "style" "width")
          (css-size width #j"100%")
          (jscl/ffi:oget host "style" "height")
          (css-size height (if (eq scroll-mode :page) #j"auto" #j"100vh")))
    (#j:document:body:appendChild host)
    (mount host draw :scroll-mode scroll-mode)))

(register-backend :web #'run-web)
