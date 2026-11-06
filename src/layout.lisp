(defpackage #:lui.layout
  (:use #:cl #:lui.fn)
  (:export #:sizing #:fit #:grow #:fixed #:percent #:box #:box-x #:box-y
           #:box-width #:box-height #:make-box #:element #:make-element
           #:element-id #:element-children #:element-box #:element-content
           #:element-measure #:element-width #:element-height
           #:element-padding
           #:element-popup-anchor #:element-popup-reveal #:element-direction #:element-gap #:element-align
           #:element-cross-align #:element-pointer-focus-p
           #:element-interactive-p #:element-keyboard-focus-p
           #:append-child #:solve #:walk-elements
           #:do-children
           #:element-clip #:element-clip-p #:element-scroll-p
           #:element-scrollbar-p #:element-scrollbar-width #:scroll-gutter
           #:element-scroll-x
           #:element-scroll-y #:element-scroll-limit-y
           #:element-floating-p #:element-offset-x
           #:element-offset-y #:intersect-boxes #:visible-elements))

(in-package #:lui.layout)

(defstruct* (sizing (:constructor %sizing (kind value minimum maximum)))
  "Axis sizing policy with a kind, value, minimum, and optional maximum."
  (kind :fit :type (member :fit :grow :fixed :percent))
  (value 0 :type real)
  (minimum 0 :type real)
  (maximum nil :type (or null real)))

(fn (checked-size sizing) ((kind symbol) (value real) (minimum real) maximum)
  (assert (and (>= minimum 0) (or (null maximum) (>= maximum minimum))))
  (%sizing kind value minimum maximum))

(fn (fit sizing) (&optional ((minimum real) 0) maximum)
  "Size to measured content, bounded by MINIMUM and optional MAXIMUM."
  (checked-size :fit 0 minimum maximum))

(fn (grow sizing) (&optional ((minimum real) 0) maximum)
  "Share the remaining space with grow siblings, respecting size bounds."
  (checked-size :grow 0 minimum maximum))

(fn (fixed sizing) ((value real))
  "Reserve exactly VALUE backend coordinates on this axis."
  (checked-size :fixed value value value))

(fn (percent sizing) ((fraction real))
  "Use FRACTION of the available parent space after padding and gaps."
  (assert (<= 0 fraction 1))
  (checked-size :percent fraction 0 nil))

(defstruct* box
  "Axis-aligned bounds in backend coordinates: X, Y, WIDTH, and HEIGHT."
  (x 0 :type real)
  (y 0 :type real)
  (width 0 :type real)
  (height 0 :type real))

(defstruct* element
  "One layout declaration with children, sizing, solved geometry, and clip state.
Floating children use offsets; interactive nodes participate in input routing."
  id
  content
  (children (make-array 0 :adjustable t :fill-pointer 0) :type vector)
  (box (make-box) :type box)
  (width (fit) :type sizing)
  (height (fit) :type sizing)
  (direction :column :type (member :row :column))
  (table-p nil :type boolean)
  (column-span 1 :type (integer 1 *))
  (column-gap 0 :type real)
  tracks
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
  (floating-p nil :type boolean)
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

(fn walk-elements ((root element) (function function))
  "Call FUNCTION on ROOT and every descendant in declaration order."
  (funcall function root)
  (do-children (child root)
    (walk-elements child function)))

(fn (axis-size real) ((node element) (axis symbol))
  (if (eq axis :x)
      (box-width (element-box node))
      (box-height (element-box node))))

(fn set-axis-size ((node element) (axis symbol) (value real))
  (if (eq axis :x)
      (setf (box-width (element-box node)) value)
      (setf (box-height (element-box node)) value)))

(fn (axis-rule sizing) ((node element) (axis symbol))
  (if (eq axis :x) (element-width node) (element-height node)))

(fn (along-p boolean) ((node element) (axis symbol))
  (eq (element-direction node) (if (eq axis :x) :row :column)))

(fn (bounded real) ((rule sizing) (value real))
  (max (sizing-minimum rule) (min (or (sizing-maximum rule) value) value)))

(fn (flow-children list) ((node element))
  (let ((children nil))
    (do-children (child node (nreverse children))
      (unless (element-floating-p child) (push child children)))))

(fn (gaps real) ((node element))
  (let ((count 0))
    (do-children (child node)
      (unless (element-floating-p child) (incf count)))
    (* (element-gap node) (max 0 (1- count)))))

(defun measure-table-columns (table)
  ;; Track widths start with single-column cells. Spanning cells then add
  ;; any missing width equally to the columns they cover.
  (let ((count 0) (gap (element-column-gap table)) spans)
    (assert (>= gap 0))
    (do-children (row table)
      (assert (eq (element-direction row) :row))
      (setf (element-gap row) gap)
      (setf count (max count (loop for cell across (element-children row)
                                   sum (element-column-span cell)))))
    (let ((tracks (make-array count :initial-element 0)))
      (do-children (row table)
        (loop with start = 0 for cell across (element-children row)
              for span = (element-column-span cell)
              for width = (axis-size cell :x)
              do (if (= span 1)
                     (setf (aref tracks start) (max (aref tracks start) width))
                     (push (list start span width) spans))
                 (incf start span)))
      (dolist (entry (stable-sort spans #'< :key #'second))
        (destructuring-bind (start span width) entry
          (let* ((end (+ start span))
                 (used (+ (* gap (1- span)) (reduce #'+ tracks :start start :end end)))
                 (extra (/ (max 0 (- width used)) span)))
            (loop for i from start below end do (incf (aref tracks i) extra)))))
      (setf (element-tracks table) tracks)
      (+ (reduce #'+ tracks :initial-value 0) (* gap (max 0 (1- count)))))))

(fn intrinsic ((node element) (axis symbol))
  (assert (and (>= (element-gap node) 0) (>= (element-padding node) 0)))
  (assert (or (zerop (length (element-children node)))
              (not (and (element-measure node) (flow-children node)))))
  (do-children (child node)
    (intrinsic child axis))
  (let ((rule (axis-rule node axis))
        (table-width (when (and (element-table-p node) (eq axis :x))
                       (measure-table-columns node))))
    ;; Only fit and grow use intrinsic content on this axis.
    (case (sizing-kind rule)
      (:fixed (return-from intrinsic
                (set-axis-size node axis (sizing-value rule))))
      (:percent (return-from intrinsic (set-axis-size node axis 0))))
    (let ((content 0) (count 0) (along (along-p node axis)))
      (if (element-measure node)
          (multiple-value-bind (width height)
              (funcall (element-measure node)
                       (when (eq axis :y)
                         (max 0 (- (axis-size node :x)
                                   (* 2 (element-padding node))))))
            (assert (and (realp width) (>= width 0)
                         (realp height) (>= height 0)))
            (setf content (if (eq axis :x) width height)))
          (do-children (child node)
            (unless (element-floating-p child)
              (incf count)
              (let ((size (axis-size child axis)))
                (setf content (if along (+ content size)
                                  (max content size)))))))
      (set-axis-size
       node axis
       (bounded rule
                (+ (or table-width content) (* 2 (element-padding node))
                   (if along (* (max 0 (1- count)) (element-gap node)) 0)
                   (if (and (eq axis :x) (element-scroll-p node)
                            (element-scrollbar-p node))
                       (max 0 (element-scrollbar-width node)) 0)))))))

(fn distribute ((children list) (axis symbol) (amount real) (growing boolean))
  "Water-fill the smallest growing or largest shrinking elements, respecting bounds."
  (loop :while (and children (> (abs amount) 0.0001))
        :do (let* ((level (reduce (if growing #'min #'max) children
                                 :key (lambda (child)
                                        (axis-size child axis))))
                   (group (remove-if-not
                           (lambda (child) (= (axis-size child axis) level))
                           children))
                   (others (set-difference children group))
                   (step (/ (abs amount) (length group))))
              (dolist (child others)
                (setf step (min step (abs (- (axis-size child axis) level)))))
              (dolist (child group)
                (let* ((rule (axis-rule child axis))
                       (limit (if growing
                                  (sizing-maximum rule)
                                  (sizing-minimum rule))))
                  (when limit
                    (setf step (min step (abs (- limit level)))))))
              (dolist (child group)
                (set-axis-size child axis
                               (+ level (if growing step (- step)))))
              (incf amount (* (if growing -1 1) step (length group)))
              (setf children
                    (remove-if
                     (lambda (child)
                       (let ((rule (axis-rule child axis)))
                         (if growing
                             (and (sizing-maximum rule)
                                  (>= (axis-size child axis)
                                      (sizing-maximum rule)))
                             (<= (axis-size child axis)
                                 (sizing-minimum rule)))))
                     children)))))

(fn resolve-axis ((node element) (axis symbol))
  (when (zerop (length (element-children node)))
    (return-from resolve-axis nil))
  (when (and (element-table-p node) (eq axis :x))
    (let* ((tracks (element-tracks node)) (count (length tracks))
           (gap (element-column-gap node))
           (width (max 0 (- (axis-size node :x) (* 2 (element-padding node))
                            (scroll-gutter node))))
           (space (max 0 (- width (* gap (max 0 (1- count))))))
           (natural (reduce #'+ tracks :initial-value 0))
           (scale (if (plusp natural) (min 1 (/ space natural)) 1))
           (extra (/ (max 0 (- space natural)) (max 1 count))))
      (do-children (row node)
        (set-axis-size row :x width)
        (loop with start = 0 for cell across (element-children row)
              for span = (element-column-span cell)
              for end = (+ start span)
              do (set-axis-size cell :x
                                (+ (* gap (1- span)) (* extra span)
                                   (* scale (reduce #'+ tracks :start start :end end))))
                 (resolve-axis cell :x)
                 (setf start end))))
    (return-from resolve-axis nil))
  (let* ((children (flow-children node))
         (along (along-p node axis))
         (available (max 0 (- (axis-size node axis)
                              (* 2 (element-padding node))
                              (if along (gaps node) 0)
                              (if (eq axis :x) (scroll-gutter node) 0)))))
    (dolist (child children)
      (let ((rule (axis-rule child axis)))
        (case (sizing-kind rule)
          (:percent
           (set-axis-size child axis (* available (sizing-value rule))))
          ((:fit :grow)
           (unless along
             (set-axis-size
              child axis
              (bounded rule (if (eq (sizing-kind rule) :grow)
                                available
                                (min available (axis-size child axis)))))))
          (otherwise nil))))
    (when (and along (not (element-scroll-p node)))
      (let* ((remaining (- available
                           (loop :for child :in children
                                 :sum (axis-size child axis))))
             (growing (plusp remaining)))
        (distribute (remove-if-not
                     (lambda (child)
                       (member (sizing-kind (axis-rule child axis))
                               (if growing '(:grow) '(:fit :grow))))
                     children)
                    axis remaining growing)))
    (do-children (child node)
      (when (element-floating-p child)
        (let ((rule (axis-rule child axis)))
          (case (sizing-kind rule)
            (:percent
             (set-axis-size child axis
                            (* available (sizing-value rule))))
            (:grow
             (set-axis-size child axis (bounded rule available)))
            (otherwise nil))))
      (when (and (element-popup-anchor child) (eq axis :x))
        (set-axis-size child :x (min available
                     (if (eq :fixed (sizing-kind (element-width child)))
                         (sizing-value (element-width child))
                         (axis-size (element-popup-anchor child) :x)))))
      (resolve-axis child axis))))

(fn (alignment-offset real) ((alignment symbol) (space real))
  (* (max 0 space) (ecase alignment (:start 0) (:center 0.5) (:end 1))))

(fn position-elements ((node element))
  (when (zerop (length (element-children node)))
    (return-from position-elements nil))
  (let* ((bounds (element-box node))
         (row (eq (element-direction node) :row))
         (axis (if row :x :y))
         (cross (if row :y :x))
         (padding (element-padding node))
         (inner (- (axis-size node axis) (* 2 padding)
                   (if (eq axis :x) (scroll-gutter node) 0)))
         (used (+ (gaps node)
                  (loop :for child :in (flow-children node)
                        :sum (axis-size child axis))))
         (cursor (+ padding
                    (alignment-offset (element-align node) (- inner used)))))
    (do-children (child node)
      (let ((box (element-box child))
            (offset (+ padding
                       (alignment-offset
                        (element-cross-align node)
                        (- (axis-size node cross) (* 2 padding)
                           (if (eq cross :x) (scroll-gutter node) 0)
                           (axis-size child cross))))))
        (setf (box-x box)
              (+ (box-x bounds) (element-offset-x child)
                 (if (element-floating-p child)
                     padding
                     (if row cursor offset)))
              (box-y box)
              (+ (box-y bounds) (element-offset-y child)
                 (if (element-floating-p child)
                     padding
                     (if row offset cursor))))
        (unless (element-floating-p child)
          (incf cursor (+ (axis-size child axis) (element-gap node))))
        (position-elements child)))))

(fn (solve element) ((root element) (width real) (height real))
  "Measure and position ROOT and its descendants within WIDTH and HEIGHT.
Update boxes, padded clipping rectangles, and bounded scroll offsets in place.
Return ROOT; all dimensions use the active backend coordinates."
  (assert (and (>= width 0) (>= height 0)))
  (intrinsic root :x)
  (set-axis-size root :x width)
  (resolve-axis root :x)
  (intrinsic root :y)
  (set-axis-size root :y height)
  (resolve-axis root :y)
  (setf (box-x (element-box root)) 0
        (box-y (element-box root)) 0)
  (position-elements root)
  (clip-elements root (element-box root) 0 0)
  root)

(fn (intersect-boxes box) ((a box) (b box))
  "Return the axis-aligned intersection of A and B; disjoint boxes have zero size."
  (let ((x (max (box-x a) (box-x b)))
        (y (max (box-y a) (box-y b))))
    (make-box :x x :y y
              :width (max 0 (- (min (+ (box-x a) (box-width a))
                                    (+ (box-x b) (box-width b)))
                               x))
              :height (max 0 (- (min (+ (box-y a) (box-height a))
                                     (+ (box-y b) (box-height b)))
                                y)))))

(defun position-popup (popup viewport)
  ;; The anchor has already been positioned and clipped by its scroll parents.
  (let* ((anchor (element-clip (element-popup-anchor popup)))
         (box (element-box popup))
         (above (box-y anchor))
         (top (+ above (box-height anchor)))
         (below (max 0 (- (box-height viewport) top)))
         (up (and (> (box-height box) below) (> above below))))
    (setf (box-height box)
          (if (and (plusp (box-height anchor)) (plusp (box-width anchor)))
              (min (box-height box) (if up above below)) 0)
          (box-x box) (min (box-x anchor) (- (box-width viewport) (box-width box)))
          (box-y box) (if up (- above (box-height box)) top))
    (position-elements popup)
    (when (element-popup-reveal popup)
      (let* ((row (element-box (element-popup-reveal popup)))
             (top (- (box-y row) (box-y box) (element-padding popup)))
             (page (- (box-height box) (* 2 (element-padding popup)))))
        (setf (element-scroll-y popup)
              (max 0 (min top (max (element-scroll-y popup)
                                    (- (+ top (box-height row)) page)))))))))

(fn clip-elements ((node element) (clip box) (dx real) (dy real))
  (let* ((box (element-box node))
         (padding (element-padding node)))
    (when (element-popup-anchor node) (position-popup node clip))
    (decf (box-x box) dx)
    (decf (box-y box) dy)
    (setf (element-clip node) (intersect-boxes clip box))
    (let* ((clipping (or (element-scroll-p node) (element-clip-p node)))
           (content
             (if (and clipping (or (plusp padding)
                                      (plusp (scroll-gutter node))))
                 (make-box :x (+ (box-x box) padding)
                           :y (+ (box-y box) padding)
                           :width (max 0 (- (box-width box) (* 2 padding)
                                          (scroll-gutter node)))
                           :height (max 0 (- (box-height box) (* 2 padding))))
                 box))
           (child-clip (cond ((not clipping) clip)
                            ((eq content box) (element-clip node))
                            (t (intersect-boxes clip content)))))
      (when (element-scroll-p node)
        (let* ((right (+ (box-x content) (box-width content)))
               (bottom (+ (box-y content) (box-height content)))
               (extent-x right) (extent-y bottom))
          (do-children (child node)
            (setf extent-x
                  (max extent-x (- (+ (box-x (element-box child))
                                      (box-width (element-box child)))
                                   dx))
                  extent-y
                  (max extent-y (- (+ (box-y (element-box child))
                                      (box-height (element-box child)))
                                   dy))))
          (setf (element-scroll-limit-y node) (- extent-y bottom)
                (element-scroll-x node)
                (min (max 0 (element-scroll-x node)) (- extent-x right))
                (element-scroll-y node)
                (min (max 0 (element-scroll-y node))
                     (element-scroll-limit-y node)))))
      (do-children (child node)
        (clip-elements child child-clip
                       (+ dx (element-scroll-x node))
                       (+ dy (element-scroll-y node)))))))

(fn visible-elements ((root element) (function function))
  "Call FUNCTION in tree order for every node with a nonempty solved clip."
  (walk-elements root
                 (lambda (node)
                   (when (and (plusp (box-width (element-clip node)))
                              (plusp (box-height (element-clip node))))
                     (funcall function node)))))
