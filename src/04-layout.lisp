(defpackage #:lui.layout
  (:use #:cl #:lui.fn)
  (:export #:sizing-kind #:sizing-value #:sizing-minimum
           #:sizing-maximum
           #:make-point #:position-spec #:element-position
           #:object-id #:point #:contour #:contours #:sizing #:fit #:grow
           #:fixed #:percent #:box #:box-x #:box-y
           #:box-width #:box-height #:box-right #:box-bottom #:make-box
           #:element #:make-element
           #:element-id #:element-children #:element-box #:element-content
           #:element-measure #:element-width #:element-height
           #:element-padding
           #:element-popup-anchor #:element-popup-reveal #:element-direction
           #:element-gap #:element-align
           #:element-cross-align #:element-pointer-focus-p
           #:element-interactive-p #:element-keyboard-focus-p
           #:append-child #:solve #:walk-elements
           #:do-children
           #:element-clip #:element-clip-p #:element-scroll-p
           #:element-scrollbar-p #:element-scrollbar-width #:scroll-gutter
           #:element-scroll-x
           #:element-scroll-y #:element-scroll-limit-y
           #:element-offset-x
           #:element-offset-y #:intersect-boxes #:visible-elements))

(in-package #:lui.layout)

(deftype object-id ()
  "An application-defined identity compared with EQUAL. Any Lisp object is valid;
keep compound IDs stable and do not mutate them after declaration."
  't)

(deftype point () "An X/Y coordinate pair." '(cons real real))
(deftype position-spec ()
  "Automatic flow, parent-relative absolute placement, or a fixed surface X/Y pair."
  '(or (member :automatic :absolute) point))

(fn (make-point point) (&key ((x real) 0) ((y real) 0))
  "Return an X/Y pair in logical window/client-surface coordinates."
  (cons x y))

(deftype contour () "A vector of ordered polygon points." '(vector point))
(deftype contours () "A vector of polygon contours." '(vector contour))

(defstruct sizing
  "Axis sizing policy with a kind, value, minimum, and optional maximum."
  ;; :FIT measures content; :GROW shares remaining space; :FIXED and :PERCENT
  ;; use VALUE. The FIT, GROW, FIXED, and PERCENT helpers check their inputs.
  (kind :fit :type (member :fit :grow :fixed :percent))
  ;; Backend coordinates for :FIXED, a fraction in [0, 1] for :PERCENT,
  ;; and unused (conventionally zero) for :FIT and :GROW.
  (value 0 :type real)
  ;; Nonnegative lower bound in backend coordinates. For :FIXED, both bounds
  ;; equal VALUE so the requested size cannot shrink or grow.
  (minimum 0 :type real)
  ;; NIL means no upper bound; otherwise this must be at least MINIMUM.
  (maximum nil :type (or null real)))

(fn (make-checked-sizing sizing)
    ((kind symbol) (value real) (minimum real) (maximum (or null real)))
  "Create a sizing policy after checking its minimum and maximum bounds."
  (assert (and (>= minimum 0) (or (null maximum) (>= maximum minimum))))
  (make-sizing :kind kind :value value
               :minimum minimum :maximum maximum))

(fn (fit sizing) (&optional ((minimum real) 0) ((maximum (or null real)) nil))
  "Size to measured content, bounded by MINIMUM and optional MAXIMUM."
  (make-checked-sizing :fit 0 minimum maximum))

(fn (grow sizing)
    (&optional ((minimum real) 0) ((maximum (or null real)) nil))
  "Share the remaining space with grow siblings, respecting size bounds."
  (make-checked-sizing :grow 0 minimum maximum))

(fn (fixed sizing) ((value real))
  "Reserve exactly VALUE backend coordinates on this axis."
  (make-checked-sizing :fixed value value value))

(fn (percent sizing) ((fraction real))
  "Use FRACTION of the available parent space after padding and gaps."
  (assert (<= 0 fraction 1))
  (make-checked-sizing :percent fraction 0 nil))

(defstruct box
  "Axis-aligned bounds in backend coordinates: X, Y, WIDTH, and HEIGHT."
  (x 0 :type real)
  (y 0 :type real)
  (width 0 :type real)
  (height 0 :type real))

(declaim (inline box-right box-bottom))

(fn (box-right real) ((box box))
  "Return the exclusive right edge of BOX."
  (+ (box-x box) (box-width box)))

(fn (box-bottom real) ((box box))
  "Return the exclusive bottom edge of BOX."
  (+ (box-y box) (box-height box)))

(defstruct element
  "One layout declaration with children, sizing, solved geometry, and clip state.
Point positions are fixed surface coordinates. :ABSOLUTE uses parent-relative offsets."
  (id nil :type object-id)
  content
  (children (make-array 0 :element-type 'element :adjustable t :fill-pointer
                        0) :type (vector element))
  (box (make-box) :type box)
  (width (fit) :type sizing)
  (height (fit) :type sizing)
  (direction :column :type (member :row :column))
  (table-p nil :type boolean)
  (column-span 1 :type (integer 1 *))
  (column-gap 0 :type real)
  ;; Intrinsic column widths shared by every row of a table.
  (tracks nil :type (or null (vector real)))
  (gap 0 :type real)
  (padding 0 :type real)
  (align :start :type (member :start :center :end))
  (cross-align :start :type (member :start :center :end))
  ;; Callback returns intrinsic width and height; width is NIL before sizing.
  (measure nil :type (or null function))
  (interactive-p nil :type boolean)
  (keyboard-focus-p t :type boolean)
  (pointer-focus-p nil :type boolean)
  (clip-p nil :type boolean)
  (clip (make-box) :type box)
  (scroll-p nil :type boolean)
  (scrollbar-p nil :type boolean)
  (scrollbar-width 0 :type real)
  (scroll-x 0 :type real)
  (scroll-y 0 :type real)
  (scroll-limit-y 0 :type real)
  popup-anchor popup-reveal
  ;; Point positions stay fixed; :ABSOLUTE offsets scroll with the parent.
  (position :automatic :type position-spec)
  (offset-x 0 :type real)
  (offset-y 0 :type real))

(fn (scroll-gutter real) ((node element))
  "Return the horizontal space reserved for a visible vertical scrollbar."
  (if (and (element-scroll-p node) (element-scrollbar-p node))
      (min (max 0 (element-scrollbar-width node))
           (max 0 (- (box-width (element-box node))
                     (* 2 (element-padding node)))))
      0))

(fn (append-child element) ((parent element) (child element))
  "Append CHILD to PARENT in declaration order and return CHILD."
  (vector-push-extend child (element-children parent))
  child)

(defmacro do-children ((child node &optional result) &body body)
  "Evaluate BODY for each direct CHILD of NODE, then return RESULT."
  (let ((children (gensym "CHILDREN")) (index (gensym "INDEX")))
    `(let ((,children (element-children ,node)))
       (dotimes (,index (length ,children) ,result)
         (let ((,child (aref ,children ,index))) ,@body)))))

(fn (walk-elements (values)) ((root element) (function function))
  "Call FUNCTION on ROOT and every descendant in declaration order."
  (funcall function root)
  (do-children (child root)
    (walk-elements child function))
  (values))

(fn (element-size-on-axis real) ((node element) (axis symbol))
  "Return NODE's calculated box width for :X or height for :Y."
  (if (eq axis :x)
      (box-width (element-box node))
      (box-height (element-box node))))

(fn ((setf element-size-on-axis) real)
    ((value real) (node element) (axis symbol))
  "Set NODE's calculated box width for :X or height for :Y; return VALUE.
This changes the solved dimension, not the sizing policy."
  (if (eq axis :x)
      (setf (box-width (element-box node)) value)
      (setf (box-height (element-box node)) value)))

(fn (element-sizing-on-axis sizing) ((node element) (axis symbol))
  "Return NODE's width policy for :X or height policy for :Y."
  (if (eq axis :x) (element-width node) (element-height node)))

(fn (main-axis-p boolean) ((node element) (axis symbol))
  "Return true when AXIS follows NODE's child flow: :X for rows, :Y for columns."
  (eq (element-direction node) (if (eq axis :x) :row :column)))

(fn (clamp-size-to-bounds real) ((rule sizing) (value real))
  "Clamp VALUE to RULE's minimum and optional maximum size."
  (max (sizing-minimum rule) (min (or (sizing-maximum rule) value) value)))

(fn (flow-element-p boolean) ((node element))
  "Whether NODE consumes an automatic row/column slot."
  (eq (element-position node) :automatic))

(fn (flow-children (vector element)) ((node element))
  "Return NODE's automatic children in declaration order."
  (remove-if-not #'flow-element-p (element-children node)))

(fn (content-size real) ((node element) (axis symbol))
  "Return solved space inside NODE's padding and horizontal scrollbar gutter."
  (- (element-size-on-axis node axis) (* 2 (element-padding node))
     (if (eq axis :x) (scroll-gutter node) 0)))

(fn (total-child-gap real) ((node element))
  "Return the total gap space between NODE's automatic children."
  (* (element-gap node)
     (max 0 (1- (count-if #'flow-element-p
                              (element-children node))))))

(fn (measure-table-columns real) ((table element))
  "Store shared column widths on TABLE and return their total width, including gaps.
Measure single-column cells first, then spread spanning cells' deficits equally."
  ;; Track widths start with single-column cells. Spanning cells then add
  ;; any missing width equally to the columns they cover.
  (let ((count 0) (gap (element-column-gap table)))
    (assert (>= gap 0))
    (do-children (row table)
      (assert (eq (element-direction row) :row))
      (setf (element-gap row) gap)
      (setf count (max count (loop :for cell :across (element-children row)
                                   :sum (element-column-span cell)))))
    (let ((tracks (make-array count :element-type 'real :initial-element 0))
          (spans (make-array (1+ count) :element-type 'list
                             :initial-element nil)))
      (do-children (row table)
        (loop :with start := 0 :for cell :across (element-children row)
              :for span := (element-column-span cell)
              :for width := (element-size-on-axis cell :x)
              :do (if (= span 1)
                      (setf (aref tracks start)
                            (max (aref tracks start) width))
                      (push (cons start width) (aref spans span)))
              (incf start span)))
      (loop :for span :from 2 :to count :do
            (dolist (entry (aref spans span))
              (let* ((start (car entry)) (end (+ start span))
                     (used (+ (* gap (1- span))
                              (reduce #'+ tracks :start start :end end)))
                     (extra (/ (max 0 (- (cdr entry) used)) span)))
                (loop :for i :from start :below end
                      :do (incf (aref tracks i) extra)))))
      (setf (element-tracks table) tracks)
      (+ (reduce #'+ tracks :initial-value 0) (* gap (max 0 (1- count)))))))

(fn (measure-leaf-size real) ((node element) (axis symbol))
  "Measure a leaf on AXIS, validating both dimensions returned by its callback."
  (multiple-value-bind (width height)
      (funcall (element-measure node)
               (when (eq axis :y)
                 (max 0 (- (element-size-on-axis node :x)
                           (* 2 (element-padding node))))))
    (assert (and (realp width) (>= width 0)
                 (realp height) (>= height 0)))
    (if (eq axis :x) width height)))

(fn (measure-intrinsic-size real) ((node element) (axis symbol))
  "Measure descendants before NODE and store their initial sizes on AXIS.
Use content for fit/grow policies, fixed values for fixed policies, and zero
for percentages until the parent size is known. Height measurement uses the
already resolved content width."
  (assert (and (>= (element-gap node) 0) (>= (element-padding node) 0)))
  (assert (or (not (element-measure node))
              (notany #'flow-element-p (element-children node))))
  (do-children (child node)
    (measure-intrinsic-size child axis))
  (let ((rule (element-sizing-on-axis node axis))
        (table-width (when (and (element-table-p node) (eq axis :x))
                       (measure-table-columns node))))
    ;; Only fit and grow use intrinsic content on this axis.
    (cond
      ((eq (sizing-kind rule) :fixed)
       (setf (element-size-on-axis node axis)
             (sizing-value rule)))
      ((eq (sizing-kind rule) :percent)
       (setf (element-size-on-axis node axis)
             0))
      (t
       (let ((content 0) (count 0) (along (main-axis-p node axis)))
         (if (element-measure node)
             (setf content (measure-leaf-size node axis))
             (do-children (child node)
               (when (flow-element-p child)
                 (incf count)
                 (let ((size (element-size-on-axis child axis)))
                   (setf content (if along (+ content size)
                                     (max content size)))))))
         (setf (element-size-on-axis node axis)
               (clamp-size-to-bounds
                rule
                (+ (or table-width content) (* 2 (element-padding node))
                   (if along (* (max 0 (1- count)) (element-gap node)) 0)
                   (if (and (eq axis :x) (element-scroll-p node)
                            (element-scrollbar-p node))
                       (max 0 (element-scrollbar-width node)) 0)))))))))

(fn (distribute-space (values))
    ((children (vector element)) (axis symbol)
     (amount real) (growing boolean))
  "Add positive AMOUNT to the smallest children or remove a negative AMOUNT
from the largest, respecting each child's size bounds. GROWING selects which
case applies. Update solved dimensions on AXIS in place."
  (loop :while (and (plusp (length children)) (> (abs amount) 0.0001f0))
        :do (let* ((level (reduce (if growing #'min #'max) children
                                  :key (lambda (child)
                                         (element-size-on-axis child axis))))
                   (group (remove-if-not
                           (lambda (child)
                             (= (element-size-on-axis child axis) level))
                           children))
                   (others (remove-if
                            (lambda (child)
                              (= (element-size-on-axis child axis) level))
                            children))
                   (step (/ (abs amount) (length group))))
              (loop :for child :across others :do
                    (setf step
                          (min step
                               (abs (- (element-size-on-axis child axis)
                                       level)))))
              (loop :for child :across group :do
                    (let* ((rule (element-sizing-on-axis child axis))
                           (limit (if growing
                                      (sizing-maximum rule)
                                      (sizing-minimum rule))))
                      (when limit
                        (setf step (min step (abs (- limit level)))))))
              (loop :for child :across group :do
                    (setf (element-size-on-axis child axis)
                          (+ level (if growing step (- step)))))
              (incf amount (* (if growing -1 1) step (length group)))
              (setf children
                    (remove-if
                     (lambda (child)
                       (let ((rule (element-sizing-on-axis child axis)))
                         (if growing
                             (and (sizing-maximum rule)
                                  (>= (element-size-on-axis child axis)
                                      (sizing-maximum rule)))
                             (<= (element-size-on-axis child axis)
                                 (sizing-minimum rule)))))
                     children))))
  (values))

(fn (resolve-table-widths (values)) ((node element))
  "Fit shared column tracks to NODE and resolve the widths of spanning cells."
  (let* ((tracks (element-tracks node)) (count (length tracks))
         (gap (element-column-gap node))
         (width (max 0 (content-size node :x)))
         (space (max 0 (- width (* gap (max 0 (1- count))))))
         (natural (reduce #'+ tracks :initial-value 0))
         (scale (if (plusp natural) (min 1 (/ space natural)) 1))
         (extra (/ (max 0 (- space natural)) (max 1 count))))
    (do-children (row node)
      (setf (element-size-on-axis row :x) width)
      (loop :with start := 0 :for cell :across (element-children row)
            :for span := (element-column-span cell)
            :for end := (+ start span)
            :do (setf (element-size-on-axis cell :x)
                      (+ (* gap (1- span)) (* extra span)
                         (* scale (reduce #'+ tracks
                                          :start start :end end))))
            (resolve-child-sizes cell :x)
            (setf start end))))
  (values))

(fn (resolve-independent-size (values))
    ((child element) (axis symbol) (available real))
  "Size independently positioned CHILD and constrain popup width to its anchor and available space."
  (unless (flow-element-p child)
    (let ((rule (element-sizing-on-axis child axis)))
      (case (sizing-kind rule)
        (:percent
         (setf (element-size-on-axis child axis)
               (* available (sizing-value rule))))
        (:grow
         (setf (element-size-on-axis child axis)
               (clamp-size-to-bounds rule available)))
        (otherwise nil))))
  (when (and (element-popup-anchor child) (eq axis :x))
    (setf (element-size-on-axis child :x)
          (min available
               (if (eq :fixed (sizing-kind (element-width child)))
                   (sizing-value (element-width child))
                   (element-size-on-axis (element-popup-anchor child)
                                         :x)))))
  (values))

(fn (resolve-child-sizes (values)) ((node element) (axis symbol))
  "Resolve descendant sizes on AXIS from NODE's already assigned size.
Apply percentages, distribute remaining flow space, and size independently positioned children.
Horizontal table layout uses the shared column widths measured earlier."
  (cond
    ((zerop (length (element-children node))) nil)
    ((and (element-table-p node) (eq axis :x))
     (resolve-table-widths node))
    (t
     (let* ((children (flow-children node))
            (along (main-axis-p node axis))
            (available (max 0 (- (content-size node axis)
                                 (if along (total-child-gap node) 0)))))
       (loop :for child :across children :do
             (let ((rule (element-sizing-on-axis child axis)))
               (case (sizing-kind rule)
                 (:percent
                  (setf (element-size-on-axis child axis)
                        (* available (sizing-value rule))))
                 ((:fit :grow)
                  (unless along
                    (setf (element-size-on-axis child axis)
                          (clamp-size-to-bounds
                           rule (if (eq (sizing-kind rule) :grow)
                                    available
                                    (min available (element-size-on-axis
                                                    child axis)))))))
                 (otherwise nil))))
       (when (and along (not (element-scroll-p node)))
         (let* ((remaining (- available
                              (loop :for child :across children
                                    :sum (element-size-on-axis child axis))))
                (growing (plusp remaining)))
           (distribute-space
            (remove-if-not
             (lambda (child)
               (let ((kind (sizing-kind (element-sizing-on-axis child axis))))
                 (or (eq kind :grow)
                     (and (not growing) (eq kind :fit)))))
             children)
            axis remaining growing)))
       (do-children (child node)
         (resolve-independent-size child axis available)
         (unless (zerop (length (element-children child)))
           (resolve-child-sizes child axis))))))
  (values))

(fn (alignment-offset real) ((alignment symbol) (space real))
  "Return the start, center, or end offset within nonnegative spare SPACE."
  (* (max 0 space) (ecase alignment (:start 0) (:center 0.5f0) (:end 1))))

(fn (position-elements (values)) ((node element))
  "Position descendants using solved sizes and alignment; manual children do not advance flow."
  (let* ((bounds (element-box node))
         (padding (element-padding node))
         (row (eq (element-direction node) :row))
         (axis (if row :x :y))
         (cross (if row :y :x))
         (available (content-size node cross))
         (used (let ((size 0) (count 0))
                 (do-children (child node)
                   (when (flow-element-p child)
                     (incf size (element-size-on-axis child axis))
                     (incf count)))
                 (+ size (* (element-gap node) (max 0 (1- count))))))
         (cursor (alignment-offset (element-align node)
                                   (- (content-size node axis) used))))
    (do-children (child node)
      (let ((box (element-box child))
            (x (+ (box-x bounds) padding (element-offset-x child)))
            (y (+ (box-y bounds) padding (element-offset-y child))))
        (when (flow-element-p child)
          (let ((offset (alignment-offset (element-cross-align node)
                                          (- available
                                             (element-size-on-axis child
                                                                   cross)))))
            (incf x (if row cursor offset))
            (incf y (if row offset cursor)))
          (incf cursor (+ (element-size-on-axis child axis)
                          (element-gap node))))
        (let ((position (element-position child)))
          (setf (box-x box) (if (consp position) (car position) x)
                (box-y box) (if (consp position) (cdr position) y)))
        (unless (zerop (length (element-children child)))
          (position-elements child)))))
  (values))

(defvar *popup-viewport* nil
  "Visible page bounds used to constrain popups during SOLVE; NIL otherwise.")

(fn (solve element)
    ((root element) (width real) (height real) &optional
     ((page-top (or null real)) nil))
  "Measure and position ROOT and its descendants within WIDTH and HEIGHT.
Update boxes, padded clipping rectangles, and bounded scroll offsets in place.
With PAGE-TOP, HEIGHT is the minimum page height and popups stay in the viewport."
  (assert (and (>= width 0) (>= height 0)))
  (measure-intrinsic-size root :x)
  (setf (element-size-on-axis root :x) width)
  (resolve-child-sizes root :x)
  (measure-intrinsic-size root :y)
  (setf (element-size-on-axis root :y)
        (if page-top (max height (element-size-on-axis root :y)) height))
  (resolve-child-sizes root :y)
  (setf (box-x (element-box root)) 0
        (box-y (element-box root)) 0)
  (position-elements root)
  (let ((*popup-viewport* (when page-top
                            (make-box
                             :y (min page-top
                                     (- (element-size-on-axis root :y)
                                        height))
                             :width width :height height))))
    (clip-elements root (element-box root) 0 0))
  root)

(fn (intersect-boxes box) ((a box) (b box))
  "Return the axis-aligned intersection of A and B; disjoint boxes have zero size."
  (let ((x (max (box-x a) (box-x b)))
        (y (max (box-y a) (box-y b))))
    (make-box :x x :y y
              :width (max 0 (- (min (box-right a)
                                    (box-right b))
                               x))
              :height (max 0 (- (min (box-bottom a)
                                     (box-bottom b))
                                y)))))

(fn (position-popup (or null real)) ((popup element) (viewport box))
  "Position and constrain POPUP around its clipped anchor within VIEWPORT.
Prefer below the anchor unless above has more room; reveal the requested row
by adjusting the popup scroll offset when necessary."
  ;; The anchor has already been positioned and clipped by its scroll parents.
  (let* ((anchor-clip (element-clip (element-popup-anchor popup)))
         (anchor (if *popup-viewport* (intersect-boxes anchor-clip viewport)
                     anchor-clip))
         (box (element-box popup))
         (above (max 0 (- (box-y anchor) (box-y viewport))))
         (top (box-bottom anchor))
         (below (max 0 (- (box-bottom viewport) top)))
         (up (and (> (box-height box) below) (> above below))))
    (setf (box-height box)
          (if (and (plusp (box-height anchor)) (plusp (box-width anchor)))
              (min (box-height box) (if up above below)) 0)
          (box-x box) (min (box-x anchor) (- (box-width viewport) (box-width
                                                                   box)))
          (box-y box) (if up (- (box-y anchor) (box-height box)) top))
    (position-elements popup)
    (when (element-popup-reveal popup)
      (let* ((row (element-box (element-popup-reveal popup)))
             (top (- (box-y row) (box-y box) (element-padding popup)))
             (page (- (box-height box) (* 2 (element-padding popup)))))
        (setf (element-scroll-y popup)
              (max 0 (min top (max (element-scroll-y popup)
                                   (- (+ top (box-height row)) page)))))))))

(fn (clip-elements (values)) ((node element) (clip box) (dx real) (dy real))
  "Apply ancestor scroll offsets DX/DY and intersect NODE's box with CLIP.
Position anchored popups, clamp scroll offsets to content extents, and recurse
with the appropriate child clip and accumulated scroll offsets."
  (when (consp (element-position node)) (setf dx 0 dy 0))
  (let ((box (element-box node))
        (padding (element-padding node)))
    (when (element-popup-anchor node) (position-popup node (or
                                                            *popup-viewport*
                                                            clip)))
    (decf (box-x box) dx)
    (decf (box-y box) dy)
    (setf (element-clip node) (intersect-boxes clip box))
    ;; Leaves have no content extent or descendants to clip. Scroll leaves
    ;; still pass through the normal path to reset their scroll limits.
    (unless (and (zerop (length (element-children node)))
                 (not (element-scroll-p node)))
      (let* ((clipping (or (element-scroll-p node) (element-clip-p node)))
             (content
              (if (and clipping (or (plusp padding)
                                    (plusp (scroll-gutter node))))
                  (make-box :x (+ (box-x box) padding)
                            :y (+ (box-y box) padding)
                            :width (max 0 (- (box-width box) (* 2 padding)
                                             (scroll-gutter node)))
                            :height (max 0 (- (box-height box) (* 2
                                                                  padding))))
                  box))
             (child-clip (cond ((not clipping) clip)
                               ((eq content box) (element-clip node))
                               (t (intersect-boxes clip content)))))
        (when (element-scroll-p node)
          (let* ((right (box-right content))
                 (bottom (box-bottom content))
                 (extent-x right) (extent-y bottom))
            (do-children (child node)
              (unless (consp (element-position child))
                (setf extent-x
                    (max extent-x (- (box-right (element-box child))
                                     dx))
                    extent-y
                    (max extent-y (- (box-bottom (element-box child))
                                     dy)))))
            ;; Fractional line heights can put the last edge a few ULPs
            ;; beyond its container after repeated additions.
            (setf (element-scroll-limit-y node)
                  (if (< (- extent-y bottom) 1d-7) 0 (- extent-y bottom))
                  (element-scroll-x node)
                  (min (max 0 (element-scroll-x node)) (- extent-x right))
                  (element-scroll-y node)
                  (min (max 0 (element-scroll-y node))
                       (element-scroll-limit-y node)))))
        (do-children (child node)
          (clip-elements child child-clip
                         (+ dx (element-scroll-x node))
                         (+ dy (element-scroll-y node)))))))
  (values))

(fn (visible-elements (values)) ((root element) (function function))
  "Call FUNCTION in tree order for every node with a nonempty solved clip."
  (walk-elements root
                 (lambda (node)
                   (when (and (plusp (box-width (element-clip node)))
                              (plusp (box-height (element-clip node))))
                     (funcall function node))))
  (values))
