(defpackage #:lui.tests.support
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets)
  (:export #:make-test-context #:test-lines #:has-text-p #:visible-text-p
           #:visible-widget-count))
(in-package #:lui.tests.support)

(fn (test-lines (vector string)) ((text string) width)
  (lui.text:wrap-lines text width
                       (lambda (text start end)
                         (declare (ignore text)) (- end start))))

(fn make-test-context ()
  "Create a compact layout fixture with deterministic character-count metrics.
This fixture measures declarations; it does not draw or emulate a terminal."
  (make-context
   :text-mode-p t
   :measure (lambda (widget width)
              (let ((lines (test-lines (widget-terminal-text widget) width)))
                (values (max (if (eq (widget-kind widget) :slider) 12 0)
                             (loop for line across lines maximize (length
                  line)))
                        (length lines))))))

(fn visible-node-p ((node element))
  (let ((box (element-box node)) (clip (element-clip node)))
    (and (plusp (box-width box)) (plusp (box-height box))
         (plusp (box-width clip)) (plusp (box-height clip))
         (< (max (box-x box) (box-x clip))
            (min (+ (box-x box) (box-width box))
                 (+ (box-x clip) (box-width clip))))
         (< (max (box-y box) (box-y clip))
            (min (+ (box-y box) (box-height box))
                 (+ (box-y clip) (box-height clip)))))))

(fn has-text-p ((context context) (text string) &key visible)
  "Inspect widget text in the solved tree, optionally requiring a visible clip.
This checks content and geometry, without asserting any backend's pixel output."
  (let ((found nil))
    (when (context-root context)
      (walk-elements
       (context-root context)
       (lambda (node)
         (let ((widget (element-content node)))
           (when (and (widget-p widget)
                      (or (not visible) (visible-node-p node))
                      (search text (widget-terminal-text widget)))
             (setf found t))))))
    found))

(fn visible-text-p ((context context) (text string))
  (has-text-p context text :visible t))

(fn visible-widget-count ((context context))
  (let ((count 0))
    (when (context-root context)
      (walk-elements (context-root context)
                     (lambda (node)
                       (when (and (widget-p (element-content node))
                                  (visible-node-p node))
                         (incf count)))))
    count))

;; Reuse a declaration site across frames spelled out separately in fixtures.
(defun draw-button (text &optional options)
  (lui:button text options))
(defun draw-tab (text &optional options)
  (lui:tab text options))
(defun draw-cell (text &optional options)
  (lui:cell text options))
(defun draw-list-item (text &optional options)
  (lui:list-item text options))
(defun draw-checkbox (text &optional options)
  (lui:checkbox text options))
(defun draw-radio (choice text &optional options)
  (lui:radio choice text options))
(defun draw-slider (&optional options)
  (lui:slider options))
(defun draw-text-field (&optional options)
  (lui:text-field options))
(defun draw-gauge (fraction &optional options)
  (lui:gauge fraction options))
(defun draw-canvas (commands &optional options)
  (lui:canvas commands options))
(defun draw-searchable-combobox (choices &optional options)
  (lui:searchable-combobox choices options))
(defun draw-date-picker (&optional options)
  (lui:date-picker options))
