(defpackage #:lui.tests.docs
  (:use #:cl #:lui.layout #:lui.frame #:lui.widgets #:lui.terminal)
  (:export #:run-tests))
(in-package #:lui.tests.docs)

(defun nodes (context predicate)
  (let ((result nil))
    (walk-elements
     (context-root context)
     (lambda (node) (when (funcall predicate node) (push node result))))
    (nreverse result)))

(defun has-label (context text)
  (nodes context
         (lambda (node)
           (let ((widget (element-content node)))
             (and (widget-p widget) (eq (widget-kind widget) :label)
                  (string= text (widget-text widget)))))))

(defun frame (context draw &rest events)
  (with-frame (context 100 40 :events events) (funcall draw)))

(defun node-with-id (context id)
  (first (nodes context (lambda (node) (equal id (element-id node))))))

(defun test-live-widgets ()
  (let* ((lui:*unit* 1) (context (make-terminal-context))
         (draw (lui.docs:make-docs)) (other (lui.docs:make-docs))
         (second (make-terminal-context)))
    (labels ((widget (id)
               (element-content (node-with-id context id)))
             (activate (id)
               (frame context draw (make-event :kind :activate :id id))))
      (frame context draw)
      (assert (has-label context "Terminal: event-driven rendering"))
      ;; Symbols and details each retain an independent tall viewport.
      (let ((list (element-box (node-with-id context :docs-entries)))
            (detail (element-box (node-with-id context :docs-detail))))
        (assert (> (box-height list) 20))
        (assert (>= (box-x detail) (+ (box-x list) (box-width list)))))
      (activate '(:docs-guide :previews))
      (dolist (kind '(:label :button :tab :checkbox :slider :text-field
                     :cell :list-item :gauge :canvas :panel))
        (assert (nodes context
                       (lambda (node)
                         (let ((widget (element-content node)))
                           (and (widget-p widget)
                                (eq kind (widget-kind widget))))))))
      (assert (has-label context "First child"))
      (assert (has-label context "Center"))
      (activate :docs-preview-button)
      (assert (has-label context "Button clicks: 1"))
      (activate :docs-preview-checkbox)
      (assert (null (widget-value (widget :docs-preview-checkbox))))
      (frame context draw (make-event :kind :change :id :docs-preview-slider
                                      :value 0.8))
      (assert (< (abs (- 0.8 (widget-value (widget :docs-preview-gauge))))
                 0.00001))
      (frame context draw (make-event :kind :change :id :docs-preview-text
                                      :value "Changed"))
      (assert (equal "Changed" (widget-value (widget :docs-preview-text))))
      (activate '(:docs-preview-tab :two))
      (frame context draw)
      (assert (widget-value (widget '(:docs-preview-tab :two))))
      (activate :docs-preview-cell)
      (frame context draw)
      (assert (widget-value (widget :docs-preview-cell)))
      (activate '(:docs-preview-item :two))
      (frame context draw)
      (assert (widget-value (widget '(:docs-preview-item :two))))
      (activate :docs-preview-panel)
      (assert (has-label context "Panel actions: 1"))
      ;; The same live declarations follow every selected toolkit.
      (dolist (style '(:motif :garnet :glass))
        (activate :docs-toolkit)
        (frame context draw)
        (assert (eq style (widget-style (widget :docs-preview-checkbox)))))
      (frame second other (make-event :kind :activate
                                      :id '(:docs-guide :previews)))
      (assert (has-label second "Button clicks: 0"))
      (assert (string= "Edit this example"
                       (widget-value
                        (element-content
                         (node-with-id second :docs-preview-text))))))))

(defun test-narrow-reference ()
  (let* ((lui:*unit* 1) (context (make-terminal-context))
         (draw (lui.docs:make-docs
                :entries '((:package "lui" :name "BUTTON" :kind :function
                            :signature "(button id text &optional options)"
                            :documentation "Return activation.")))))
    (labels ((narrow (&rest events)
               (with-frame (context 60 40 :events events) (funcall draw))))
      (narrow)
      (assert (node-with-id context :docs-search))
      (assert (node-with-id context :docs-detail))
      (narrow (make-event :kind :activate :id '(:docs-package "lui")))
      (assert (null (node-with-id context :docs-detail)))
      (assert (> (box-height
                  (element-box (node-with-id context :docs-entries))) 20))
      (narrow (make-event :kind :activate :id '(:docs-entry 0)))
      (assert (node-with-id context :docs-preview-button))
      (narrow)
      (assert (null (node-with-id context :docs-entries)))
      (assert (node-with-id context :docs-preview-button))
      (narrow (make-event :kind :activate :id :docs-preview-button))
      (assert (has-label context "Button clicks: 1"))
      (narrow (make-event :kind :change :id :docs-search :value "button"))
      (assert (node-with-id context :docs-entries))
      (assert (null (node-with-id context :docs-detail))))))

(defun test-symbol-wrapping ()
  (assert (equal (format nil "lui:AVAILABLE-~%BACKENDS")
                 (lui.docs::wrap-symbol "lui:AVAILABLE-BACKENDS" 18)))
  (assert (equal (format nil "abcdef~%ghij")
                 (lui.docs::wrap-symbol "abcdefghij" 6)))
  (let* ((lui:*unit* 8)
         (title "lui:AN-EXCEPTIONALLY-LONG-PUBLIC-SYMBOL-WITHOUT-TRUNCATION")
         (draw (lui.docs:make-docs
                :entries (list (list :package "lui" :name (subseq title 4)
                                     :kind :function :signature "()"
                                     :documentation "A long entry."))))
         (context
           (make-context
            :measure
            (lambda (widget width)
              (let* ((extra (if (eq (widget-kind widget) :label) 0 24))
                     (lines (text-lines (widget-text widget)
                                        (when width
                                          (/ (max 1 (- width extra)) 8)))))
                (values (+ extra (* 8 (reduce #'max lines :key #'length)))
                        (+ extra (* 16 (length lines))))))))
         (previous nil))
    (dolist (width '(720 1000 520 720))
      (with-frame (context width 600) (funcall draw))
      (when (< width 640)
        (with-frame (context width 600
                             :events (list (make-event
                                            :kind :activate
                                            :id '(:docs-package nil))))
          (funcall draw)))
      (let* ((row (node-with-id context '(:docs-entry 0)))
             (caption (widget-text (element-content row)))
             (lines (text-lines caption nil)))
        (assert (string= title (remove #\Newline caption)))
        (assert (> (length lines) 1))
        ;; Include both DOM padding and the narrower native text insets.
        (assert (<= (+ 24 (* 8 (reduce #'max lines :key #'length)))
                    (+ 0.001 (box-width (element-box row)))))
        (assert (>= (box-height (element-box row))
                    (+ 12 (* 16 (length lines)))))
      (let ((pane (node-with-id context :docs-entries)))
        (when (and previous (= width 1000))
          (assert (> (box-width (element-box pane)) previous)))
        (setf previous (box-width (element-box pane))))))))

(defun test-scrolled-selection ()
  (let* ((lui:*unit* 1) (context (make-terminal-context))
         (draw (lui.docs:make-docs
                :entries
                (loop :for i :below 100
                      :collect (list :package "lui" :name (format nil "ROW~D" i)
                                     :kind :function :signature "()"
                                     :documentation "An entry.")))))
    (frame context draw)
    (frame context draw)
    ;; Input order, rather than row order, decides the latest selection.
    (frame context draw
           (make-event :kind :activate :id '(:docs-entry 7))
           (make-event :kind :activate :id '(:docs-entry 2)))
    (assert (has-label context "lui:ROW2"))
    (let ((box (element-box (node-with-id context :docs-entries))))
      ;; A wheel event batched after a click can virtualize its old row away.
      (frame context draw
             (make-event :kind :activate :id '(:docs-entry 1))
             (make-event :kind :scroll :x (+ (box-x box) 1)
                         :y (+ (box-y box) 1) :value 100 :scroll-mode :immediate)))
    (assert (null (node-with-id context '(:docs-entry 1))))
    (assert (has-label context "lui:ROW1"))
    (frame context draw (make-event :kind :move :x 99 :y 39))
    (assert (has-label context "lui:ROW1"))))

(defun test-debugger-guide ()
  (let* ((lui:*unit* 1) (context (make-terminal-context))
         (other (make-terminal-context))
         (draw (lui.docs:make-docs)) (second (lui.docs:make-docs)))
    (frame context draw)
    (assert (string= "Show debugger"
                     (widget-text
                      (element-content (node-with-id context :docs-debug)))))
    (frame context draw
           (make-event :kind :activate :id '(:docs-guide :debug)))
    (assert (has-label context "Debugger"))
    (assert (node-with-id context :docs-open-debug))
    (assert (not (lui.debug:enabled-p context)))
    (frame context draw (make-event :kind :activate :id :docs-open-debug))
    (assert (lui.debug:enabled-p context))
    (assert (node-with-id context '(:lui.debug :debugger nil)))
    (frame other second)
    (assert (not (lui.debug:enabled-p other)))
    (frame context draw
           (make-event :kind :activate :id '(:lui.debug :close nil)))
    (assert (not (lui.debug:enabled-p context)))
    (frame context draw (make-event :kind :activate :id :docs-debug))
    (assert (lui.debug:enabled-p context))
    (frame context draw (make-event :kind :activate :id :docs-debug))
    (assert (lui.debug:enabled-p context))))

(defun run-tests ()
  (test-debugger-guide)
  (test-scrolled-selection)
  (test-symbol-wrapping)
  (test-live-widgets)
  (test-narrow-reference)
  (let* ((lui:*unit* 1)
         (entries
           (loop :for index :below 400
                 :collect
                 (list :package (if (evenp index) "alpha" "beta")
                       :name (format nil "ENTRY~D" index) :kind :function
                       :signature (format nil "(entry~D value)" index)
                       :documentation
                       (if (zerop index)
                           (format nil "~{~A ~}"
                                   (make-list 1000 :initial-element "Long"))
                           (format nil "Documentation ~D" index)))))
         (draw (lui.docs:make-docs :entries entries))
         (other (lui.docs:make-docs :entries entries))
         (context (make-terminal-context))
         (second (make-terminal-context)))
    (frame context draw)
    (frame second other)
    (assert (has-label context "Getting started"))
    (frame context draw
           (make-event :kind :activate :id '(:docs-package "alpha")))
    (assert (has-label context "200 API entries"))
    (assert (has-label context "alpha:ENTRY0"))
    (assert (plusp (element-scroll-limit-y
                   (first (nodes context
                                 (lambda (node)
                                   (eq :docs-detail (element-id node))))))))
    (let ((rows (nodes context
                       (lambda (node)
                         (let ((id (element-id node)))
                           (and (consp id) (eq (first id) :docs-entry)))))))
      ;; A large reference declares only a viewport of actual control rows.
      (assert (< 0 (length rows) 20))
      (assert (every (lambda (node) (evenp (second (element-id node))))
                     rows)))
    (frame context draw (make-event :kind :change :id :docs-search
                                    :value "Documentation 198"))
    (assert (has-label context "1 API entries"))
    (assert (has-label context "alpha:ENTRY198"))
    (frame context draw
           (make-event :kind :change :id :docs-search :value "absent"))
    (assert (has-label context "No matching entries."))
    (frame second other)
    (assert (has-label second "Getting started"))
    (assert (not (has-label second "No matching entries."))))
  (let ((lui:*unit* 1) (context (make-terminal-context))
        (draw (lui.docs:make-docs :entries nil)))
    (frame context draw (make-event :kind :activate
                                    :id '(:docs-package nil)))
    (assert (has-label context "0 API entries"))
    (assert (has-label context "No matching entries."))
    (assert (has-label context "Choose an API entry from the list.")))
  (format t "Documentation browser tests passed.~%"))
