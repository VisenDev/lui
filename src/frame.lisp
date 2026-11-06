(defpackage #:lui.frame
  (:use #:cl #:lui.fn #:lui.layout)
  (:export #:context #:make-context #:context-root #:context-focus
           #:context-focus-input #:context-active #:context-measure
           #:*context* #:*parent*
           #:with-frame
           #:row #:column #:event #:event-kind #:event-x #:event-y #:event-id
           #:event-value #:event-key #:event-button #:event-clicks
           #:event-dragging-p #:context-events #:events-for
           #:previous-box
           #:context-state #:context-width #:context-height #:emit
           #:activated-p
           #:make-event #:begin-frame #:end-frame #:context-hover #:hovered-p
           #:context-previous-root #:context-activated
           #:context-focus-visible-p #:frame-time #:request-frame
           #:context-next-frame #:scroll-position #:scroll-to
           #:pending-input-context #:context-overlay #:context-overlay-state
           #:context-tabs-handled-p #:context-text-mode-p
           #:context-copy #:context-input-handler #:context-selection))

(in-package #:lui.frame)

(defstruct* event
  (kind :move :type
        (member :move :press :release :tab :activate :change
                :key :text :scroll))
  (button :primary :type (member :primary :secondary))
  (clicks 1 :type integer)
  (dragging-p nil :type boolean)
  id
  value
  key
  (x 0 :type real)
  (y 0 :type real))

(defstruct* context
  (root nil :type (or null element))
  (text-mode-p nil :type boolean)
  overlay-state
  (overlay nil :type (or null function))
  (tabs-handled-p nil :type boolean)
  (previous-root nil :type (or null element))
  (width 0 :type real)
  (height 0 :type real)
  (copy nil :type (or null function))
  (input-handler nil :type (or null function))
  selection
  focus-input
  last-click
  (time 0 :type real)
  (next-frame nil :type (or null real))
  focus
  (focus-visible-p nil :type boolean)
  hover
  active
  (state (make-hash-table :test 'equal) :type hash-table)
  (regions (make-hash-table :test 'equal) :type hash-table)
  (events (make-hash-table :test 'equal) :type hash-table)
  (scroll (make-hash-table :test 'equal) :type hash-table)
  (activated (make-hash-table :test 'equal) :type hash-table)
  (ids (make-hash-table :test 'equal) :type hash-table)
  (building-p nil :type boolean)
  ;; Supplied by the output backend: (widget available-width) -> width, height.
  (measure nil :type (or null function)))

(defvar *context*)

(defvar *parent*)

(fn (frame-time real) ()
  "Monotonic seconds sampled once for the current frame."
  (context-time *context*))

(fn request-frame (&optional ((delay real) 0))
  "Request another frame after DELAY seconds; earliest request wins."
  (assert (>= delay 0))
  ;; Some implementations return epoch-sized clocks. Single-float addition
  ;; would discard sub-minute delays there, so compute deadlines in doubles.
  (let ((deadline #+jscl (+ (frame-time) delay)
                  #-jscl (+ (coerce (frame-time) 'double-float)
                            (coerce delay 'double-float))))
    (setf (context-next-frame *context*)
          (if (context-next-frame *context*)
              (min deadline (context-next-frame *context*))
              deadline))))

(fn (contains-p boolean) ((bounds box) (x real) (y real))
  (and (<= (box-x bounds) x) (< x (+ (box-x bounds) (box-width bounds)))
       (<= (box-y bounds) y) (< y (+ (box-y bounds) (box-height bounds)))))

(fn hit ((context context) (x real) (y real))
  (let ((found nil))
    (when (and (context-root context) (<= 0 x) (< x (context-width context))
               (<= 0 y) (< y (context-height context)))
      (walk-elements (context-root context)
                     (lambda (node)
                       (when (and (element-interactive-p node)
                                  (contains-p (element-clip node) x y))
                         (setf found (element-id node))))))
    found))

(fn focus-next ((context context) &optional backward)
  (let ((ids nil))
    (when (context-root context)
      (walk-elements (context-root context)
                     (lambda (node)
                       (when (and (element-interactive-p node)
                                  (element-keyboard-focus-p node))
                         (push (element-id node) ids)))))
    (setf ids (if backward ids (nreverse ids))
          (context-focus context)
          (or (second (member (context-focus context) ids :test #'equal))
              (first ids)))))

(fn (pending-input-context context)
    ((context context) (events list)
     &optional ((width (or null real)) nil) ((height (or null real)) nil))
  ;; Translate keys against earlier pointer/Tab events in the same input batch.
  ;; The completed frame remains untouched until BEGIN-FRAME consumes them.
  (if (and (or (null width) (= width (context-width context)))
           (or (null height) (= height (context-height context)))
           (some (lambda (event)
                   (member (event-kind event) '(:press :tab))) events))
      (let ((predicted (copy-context context)))
        (dolist (event (reverse events))
          (case (event-kind event)
            (:tab (focus-next
                   predicted (eq (event-key event) :backward)))
            (:press
             (let* ((id (hit predicted (event-x event) (event-y event)))
                    (node (gethash id (context-ids predicted))))
               (when (and node (element-pointer-focus-p node))
                 (setf (context-focus predicted) id))))))
        predicted)
      context))

(fn scroll-at ((context context) (x real) (y real) (amount real))
  ;; Follow the painted hit path, then bubble unused wheel motion outward.
  (let ((scrollers nil))
    (labels ((visit (node parents)
               (when (contains-p (element-clip node) x y)
                 (let ((path (if (element-scroll-p node)
                                 (cons node parents) parents)))
                   (setf scrollers path)
                   (do-children (child node)
                     (visit child path))))))
      (when (context-root context) (visit (context-root context) nil)))
    (dolist (node scrollers)
      (let* ((old (element-scroll-y node))
             (new (min (element-scroll-limit-y node) (max 0 (+ old amount)))))
        (decf amount (- new old))
        (setf (element-scroll-y node) new
              (gethash (element-id node) (context-scroll context))
              (cons (element-scroll-x node) new))))))

(fn begin-frame ((context context) (width real) (height real) (events list))
  (assert (not (context-building-p context)))
  (assert (and (>= width 0) (>= height 0)))
  (setf (context-time context)
        (/ (get-internal-real-time) internal-time-units-per-second)
        (context-next-frame context) nil)
  (when (context-input-handler context)
    (if (and (= width (context-width context))
             (= height (context-height context)))
        (funcall (context-input-handler context) context events)
        (setf (context-selection context) nil)))
  (clrhash (context-activated context))
  (clrhash (context-events context))
  ;; Old hit regions are invalid after resizing. Establish new geometry first.
  (let ((resized (or (/= width (context-width context))
                     (/= height (context-height context)))))
    (when resized
      (setf (context-active context) nil (context-hover context) nil))
    (dolist (event events)
      (let ((target (unless resized
                      (hit context (event-x event) (event-y event))))
            (captured (context-active context)))
        (setf (event-dragging-p event) (not (null captured)))
        (when (member (event-kind event) '(:move :press :release))
          (setf (context-hover context) target))
        (case (event-kind event)
          (:scroll
           (unless resized
             (scroll-at context (event-x event) (event-y event)
                        (event-value event))))
          (:press
           (let ((previous (context-last-click context)))
             (when (and previous (equal target (second previous))
                        (eq (event-button event) (third previous))
                        (<= (- (context-time context) (first previous)) 0.4)
                        (< (abs (- (event-x event) (fourth previous))) 4)
                        (< (abs (- (event-y event) (fifth previous))) 4))
               (setf (event-clicks event) 2))
             (setf (context-last-click context)
                   (unless (= (event-clicks event) 2)
                     (list (context-time context) target (event-button event)
                           (event-x event) (event-y event)))))
           (when (eq (event-button event) :primary)
             (setf (context-active context) target
                   (context-focus-visible-p context) nil))
           (let ((node (gethash target (context-ids context))))
             (when (and node (element-pointer-focus-p node))
               (setf (context-focus context) target))))
          (:release
           (when (and (eq (event-button event) :primary)
                      target (equal target (context-active context)))
             (setf (gethash target (context-activated context)) t))
           (when (eq (event-button event) :primary)
             (setf (context-active context) nil)))
          (:tab
           (setf (context-focus-visible-p context) t)
           (focus-next context (eq (event-key event) :backward)))
          (:key (setf (context-focus-visible-p context) t))
          (:activate
           (let ((id (or (event-id event) (context-focus context))))
             (when id
               (setf (gethash id (context-activated context)) t))))
          (otherwise nil))
        (let ((id (or (event-id event)
                      (if (member (event-kind event) '(:press :move :release))
                          (or (context-active context) captured target)
                          (context-focus context)))))
          (when id (push event (gethash id (context-events context))))))))
  ;; Native selection still needs the focused input after a composite editor
  ;; consumes its events. Share the immutable event list with the observer.
  (setf (context-focus-input context)
        (when (context-selection context)
          (let* ((id (context-focus context))
                 (input (gethash id (context-events context))))
            (when input (cons id input)))))
  (clrhash (context-regions context))
  (when (context-root context)
    (walk-elements
     (context-root context)
     (lambda (node)
       (when (element-id node)
         (setf (gethash (element-id node) (context-regions context))
               (element-box node))))))
  (clrhash (context-ids context))
  (setf (context-tabs-handled-p context) nil
        (context-previous-root context) (context-root context)
        (context-width context) width
        (context-height context) height
        (context-root context) (make-element :width (grow) :height (grow))
        (context-building-p context) t))

(fn (emit element) ((node element))
  (assert (context-building-p *context*))
  (when (element-interactive-p node) (assert (element-id node)))
  (when (element-id node)
    (assert (not (gethash (element-id node) (context-ids *context*))) ()
            "Duplicate UI ID: ~S" (element-id node))
    (setf (gethash (element-id node) (context-ids *context*)) node))
  (when (element-scroll-p node)
    (assert (element-id node))
    (let ((offset (gethash (element-id node) (context-scroll *context*))))
      (when offset
        (setf (element-scroll-x node) (car offset)
              (element-scroll-y node) (cdr offset)))))
  (append-child *parent* node))

(fn scroll-position (id)
  "Return the retained horizontal and vertical scroll offsets."
  (let ((offset (gethash id (context-scroll *context*))))
    (values (or (car offset) 0) (or (cdr offset) 0))))

(fn scroll-to (id (x real) (y real))
  "Set scroll offsets; layout clamps them to the content extent."
  (let ((offset (cons (max 0 x) (max 0 y))))
    (setf (gethash id (context-scroll *context*)) offset)
    (let ((node (gethash id (context-ids *context*))))
      (when node
        (setf (element-scroll-x node) (car offset)
              (element-scroll-y node) (cdr offset))))))

(fn previous-box (id)
  (gethash id (context-regions *context*)))

(fn (events-for list) (id)
  (reverse (gethash id (context-events *context*))))

(fn (hovered-p boolean) (id)
  (and id (equal id (context-hover *context*))))

(fn (activated-p boolean) (id)
  (not (null (gethash id (context-activated *context*)))))

(fn (end-frame element) ((context context))
  (assert (context-building-p context))
  (when (context-overlay context)
    (let ((*context* context) (*parent* (context-root context)))
      (funcall (context-overlay context) (context-previous-root context))))
  (solve (context-root context) (context-width context)
         (context-height context))
  (flet ((interactive-p (id)
           (let ((node (gethash id (context-ids context))))
             (and node (element-interactive-p node)))))
    (unless (interactive-p (context-focus context))
      (setf (context-focus context) nil
            (context-focus-visible-p context) nil))
    (unless (interactive-p (context-hover context))
      (setf (context-hover context) nil))
    (unless (interactive-p (context-active context))
      (setf (context-active context) nil)))
  (let ((removed nil))
    (maphash
     (lambda (id value)
       (declare (ignore value))
       (unless (gethash id (context-ids context)) (push id removed)))
     (context-state context))
    (dolist (id removed) (remhash id (context-state context))))
  (clrhash (context-scroll context))
  (walk-elements
   (context-root context)
   (lambda (node)
     (when (and (element-id node) (element-scroll-p node))
       (setf (gethash (element-id node) (context-scroll context))
             (cons (element-scroll-x node) (element-scroll-y node))))))
  (setf (context-building-p context) nil
        (context-previous-root context) nil)
  (context-root context))

(defmacro with-frame ((context width height &key events) &body body)
  "Dispatch input, build and solve one frame, and return its root element."
  `(let ((*context* ,context))
     (begin-frame *context* ,width ,height ,events)
     (let ((*parent* (context-root *context*))
           (complete nil))
       (unwind-protect
            (progn
              ,@body
              (end-frame *context*)
              (setf complete t)
              (context-root *context*))
         (unless complete
           (setf (context-root *context*) nil
                 (context-building-p *context*) nil
                 (context-previous-root *context*) nil
                 (context-hover *context*) nil
                 (context-focus-visible-p *context*) nil
                 (context-active *context*) nil
                 (context-focus *context*) nil))))))

(defmacro row ((&rest options) &body body)
  "Lay out children declared by BODY horizontally, using element options."
  `(let ((*parent* (emit (make-element :direction :row ,@options))))
     ,@body))

(defmacro column ((&rest options) &body body)
  "Lay out children declared by BODY vertically, using element options."
  `(let ((*parent* (emit (make-element :direction :column ,@options))))
     ,@body))
