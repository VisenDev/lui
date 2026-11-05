(defpackage #:lui.layout
  (:use #:cl #:lui.fn)
  (:export #:sizing #:fit #:grow #:fixed #:percent #:box #:box-x #:box-y
    #:box-width #:box-height #:make-box #:element #:make-element
    #:element-id #:element-children #:element-box #:element-content
    #:element-measure #:element-width #:element-height #:element-padding
    #:element-direction #:element-gap #:element-align #:element-cross-align
    #:element-interactive-p #:append-child #:solve #:walk-elements
    #:element-clip #:element-clip-p #:element-scroll-p #:element-scroll-x
    #:element-scroll-y #:element-floating-p #:element-offset-x
    #:element-offset-y #:intersect-boxes #:visible-elements))

(in-package #:lui.layout)

(defstruct (sizing (:constructor %sizing (kind value minimum maximum)))
  (kind :fit :type (member :fit :grow :fixed :percent))
  (value 0 :type real)
  (minimum 0 :type real)
  (maximum nil :type (or null real)))

(fn (checked-size sizing) ((kind symbol) (value real) (minimum real) maximum)
  (assert (and (>= minimum 0) (or (null maximum) (>= maximum minimum))))
  (%sizing kind value minimum maximum))

(fn (fit sizing) (&optional ((minimum real) 0) maximum)
  (checked-size :fit 0 minimum maximum))

(fn (grow sizing) (&optional ((minimum real) 0) maximum)
  (checked-size :grow 0 minimum maximum))

(fn (fixed sizing) ((value real)) (checked-size :fixed value value value))

(fn (percent sizing) ((fraction real))
  (assert (<= 0 fraction 1))
  (checked-size :percent fraction 0 nil))

(defstruct box
  (x 0 :type real)
  (y 0 :type real)
  (width 0 :type real)
  (height 0 :type real))

(defstruct element
  id
  content
  (children (make-array 0 :adjustable t :fill-pointer 0) :type vector)
  (box (make-box) :type box)
  (width (fit) :type sizing)
  (height (fit) :type sizing)
  (direction :column :type (member :row :column))
  (gap 0 :type real)
  (padding 0 :type real)
  (align :start :type (member :start :center :end))
  (cross-align :start :type (member :start :center :end))
  ;; Callback returns intrinsic width and height; width is NIL before sizing.
  (measure nil :type (or null function))
  (interactive-p nil :type boolean)
  (clip-p nil :type boolean)
  (clip (make-box) :type box)
  (scroll-p nil :type boolean)
  (scroll-x 0 :type real)
  (scroll-y 0 :type real)
  (floating-p nil :type boolean)
  (offset-x 0 :type real)
  (offset-y 0 :type real))

(fn (append-child element) ((parent element) (child element))
  (vector-push-extend child (element-children parent))
  child)

(fn walk-elements ((root element) (function function))
  (funcall function root)
  (map nil (lambda (child) (walk-elements child function))
    (element-children root)))

(fn (axis-size real) ((node element) (axis symbol))
  (if (eq axis :x) (box-width (element-box node))
    (box-height (element-box node))))

(fn set-axis-size ((node element) (axis symbol) (value real))
  (if (eq axis :x) (setf (box-width (element-box node)) value)
    (setf (box-height (element-box node)) value)))

(fn (axis-rule sizing) ((node element) (axis symbol))
  (if (eq axis :x) (element-width node) (element-height node)))

(fn (along-p boolean) ((node element) (axis symbol))
  (eq (element-direction node) (if (eq axis :x) :row :column)))

(fn (bounded real) ((rule sizing) (value real))
  (max (sizing-minimum rule) (min (or (sizing-maximum rule) value) value)))

(fn (flow-children list) ((node element))
  (remove-if #'element-floating-p (coerce (element-children node) 'list)))

(fn (gaps real) ((node element))
  (* (element-gap node) (max 0 (1- (length (flow-children node))))))

(fn intrinsic ((node element) (axis symbol))
  (assert (and (>= (element-gap node) 0) (>= (element-padding node) 0)))
  (assert
    (not (and (element-measure node) (plusp (length (flow-children node))))))
  (map nil (lambda (child) (intrinsic child axis)) (element-children node))
  (let*
    ((rule (axis-rule node axis)) (children (flow-children node))
      (content
        (if (element-measure node)
          (multiple-value-bind (width height)
            (funcall (element-measure node)
              (when (eq axis :y)
                (max 0
                  (- (axis-size node :x)
                    (* 2 (element-padding node))))))
            (assert
              (and (realp width) (>= width 0) (realp height)
                (>= height 0))) (if (eq axis :x) width height))
          (if (along-p node axis)
            (+ (gaps node)
              (loop :for child :in children :sum
                (axis-size child axis)))
            (loop :for child :in children :maximize
              (axis-size child axis) :into size :finally
              (return (or size 0)))))))
    (set-axis-size node axis
      (case (sizing-kind rule)
        (:fixed (sizing-value rule))
        (:percent 0)
        (otherwise
          (bounded rule (+ content (* 2 (element-padding node)))))))))

(fn distribute
  ((children list) (axis symbol) (amount real) (growing boolean))
  "Water-fill the smallest growing or largest shrinking elements, respecting bounds."
  (loop :while (and children (> (abs amount) 0.0001)) :do
    (let*
      ((level
          (reduce (if growing #'min #'max) children :key
            (lambda (child) (axis-size child axis))))
        (group
          (remove-if-not
            (lambda (child) (= (axis-size child axis) level)) children))
        (others (set-difference children group))
        (step (/ (abs amount) (length group))))
      (dolist (child others)
        (setf step (min step (abs (- (axis-size child axis) level)))))
      (dolist (child group)
        (let*
          ((rule (axis-rule child axis))
            (limit
              (if growing (sizing-maximum rule) (sizing-minimum rule))))
          (when limit (setf step (min step (abs (- limit level)))))))
      (dolist (child group)
        (set-axis-size child axis (+ level (if growing step (- step)))))
      (incf amount (* (if growing -1 1) step (length group)))
      (setf children
        (remove-if
          (lambda (child)
            (let ((rule (axis-rule child axis)))
              (if growing
                (and (sizing-maximum rule)
                  (>= (axis-size child axis) (sizing-maximum rule)))
                (<= (axis-size child axis) (sizing-minimum rule)))))
          children)))))

(fn resolve-axis ((node element) (axis symbol))
  (let*
    ((children (flow-children node)) (along (along-p node axis))
      (available
        (max 0
          (- (axis-size node axis) (* 2 (element-padding node))
            (if along (gaps node) 0)))))
    (dolist (child children)
      (let ((rule (axis-rule child axis)))
        (case (sizing-kind rule)
          (:percent
            (set-axis-size child axis (* available (sizing-value rule))))
          ((:fit :grow)
            (unless along
              (set-axis-size child axis
                (bounded rule
                  (if (eq (sizing-kind rule) :grow) available
                    (min available (axis-size child axis)))))))
          (otherwise nil))))
    (when (and along (not (element-scroll-p node)))
      (let*
        ((remaining
            (- available
              (loop :for child :in children :sum
                (axis-size child axis)))) (growing (plusp remaining)))
        (distribute
          (remove-if-not
            (lambda (child)
              (member (sizing-kind (axis-rule child axis))
                (if growing '(:grow) '(:fit :grow)))) children) axis
          remaining growing)))
    (loop :for child :across (element-children node) :do
      (when (element-floating-p child)
        (let ((rule (axis-rule child axis)))
          (case (sizing-kind rule)
            (:percent
              (set-axis-size child axis
                (* available (sizing-value rule))))
            (:grow (set-axis-size child axis (bounded rule available)))
            (otherwise nil)))) (resolve-axis child axis))))

(fn (alignment-offset real) ((alignment symbol) (space real))
  (* (max 0 space) (ecase alignment (:start 0) (:center 0.5) (:end 1))))

(fn position-elements ((node element))
  (let*
    ((bounds (element-box node)) (row (eq (element-direction node) :row))
      (axis (if row :x :y)) (cross (if row :y :x))
      (padding (element-padding node))
      (inner (- (axis-size node axis) (* 2 padding)))
      (used
        (+ (gaps node)
          (loop :for child :in (flow-children node) :sum
            (axis-size child axis))))
      (cursor
        (+ padding (alignment-offset (element-align node) (- inner used)))))
    (loop :for child :across (element-children node) :do
      (let
        ((box (element-box child))
          (offset
            (+ padding
              (alignment-offset (element-cross-align node)
                (- (axis-size node cross) (* 2 padding)
                  (axis-size child cross))))))
        (setf (box-x box)
          (+ (box-x bounds) (element-offset-x child)
            (if (element-floating-p child) padding
              (if row cursor offset))) (box-y box)
          (+ (box-y bounds) (element-offset-y child)
            (if (element-floating-p child) padding
              (if row offset cursor))))
        (unless (element-floating-p child)
          (incf cursor (+ (axis-size child axis) (element-gap node))))
        (position-elements child)))))

(fn (solve element) ((root element) (width real) (height real))
  (assert (and (>= width 0) (>= height 0)))
  (intrinsic root :x)
  (set-axis-size root :x width)
  (resolve-axis root :x)
  (intrinsic root :y)
  (set-axis-size root :y height)
  (resolve-axis root :y)
  (setf (box-x (element-box root)) 0 (box-y (element-box root)) 0)
  (position-elements root)
  (clip-elements root (element-box root) 0 0)
  root)

(fn (intersect-boxes box) ((a box) (b box))
  (let ((x (max (box-x a) (box-x b))) (y (max (box-y a) (box-y b))))
    (make-box :x x :y y :width
      (max 0
        (- (min (+ (box-x a) (box-width a)) (+ (box-x b) (box-width b)))
          x)) :height
      (max 0
        (-
          (min (+ (box-y a) (box-height a)) (+ (box-y b) (box-height b)))
          y)))))

(fn clip-elements ((node element) (clip box) (dx real) (dy real))
  (let ((box (element-box node)))
    (decf (box-x box) dx)
    (decf (box-y box) dy)
    (setf (element-clip node) (intersect-boxes clip box))
    (when (element-scroll-p node)
      (let
        ((right (+ (box-x box) (box-width box)))
          (bottom (+ (box-y box) (box-height box))))
        (loop :for child :across (element-children node) :do
          (setf right
            (max right
              (-
                (+ (box-x (element-box child))
                  (box-width (element-box child))) dx)) bottom
            (max bottom
              (-
                (+ (box-y (element-box child))
                  (box-height (element-box child))) dy))))
        (setf (element-scroll-x node)
          (min (max 0 (element-scroll-x node))
            (- right (+ (box-x box) (box-width box))))
          (element-scroll-y node)
          (min (max 0 (element-scroll-y node))
            (- bottom (+ (box-y box) (box-height box)))))))
    (loop :for child :across (element-children node) :do
      (clip-elements child
        (if (or (element-scroll-p node) (element-clip-p node))
          (element-clip node) clip) (+ dx (element-scroll-x node))
        (+ dy (element-scroll-y node))))))

(fn visible-elements ((root element) (function function))
  (walk-elements root
    (lambda (node)
      (when
        (and (plusp (box-width (element-clip node)))
          (plusp (box-height (element-clip node))))
        (funcall function node)))))
