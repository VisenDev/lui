(defpackage #:lui.motif.web
  (:use #:cl #:lui.fn #:lui.layout #:lui.widgets #:lui.web.style))
(in-package #:lui.motif.web)

(fn apply-style (dom (widget widget) (node element))
  (declare (ignore node))
  (let ((kind (widget-kind widget)))
    (when (framed-p widget)
      (style dom "border-radius" "0")
      (style dom "border"
             (if (eq kind :text-field)
                 "2px inset #dddddd" "2px outset #dddddd")))
    (when (framed-p widget)
      (when (member kind '(:button :tab :text-field :checkbox))
        (style dom "padding" "4px 10px"))
      (style dom "background" (widget-background widget))
      (style dom "backdrop-filter" "none")
      (style dom "box-shadow" "none"))
    (when (eq kind :text-field)
      (attribute dom "class" "lui-motif-field"))
    (when (eq kind :checkbox)
      (attribute dom "class" "lui-check lui-motif-check")
      (style dom "padding" "6px 12px")
      (style dom "border" "none")
      (style dom "background" "transparent"))
    (when (eq kind :slider) (style dom "--lui-thumb-radius" "0"))
    (tab-underline dom widget)))

(add-sheet :motif
 #j".lui-motif-check input{appearance:none;background:#b8b8b8;border:2px outset #ddd;border-radius:0;display:grid;place-content:center}.lui-motif-check input:checked{border-style:inset}.lui-motif-check input:checked::after{content:\"\";width:8px;height:4px;border-left:2px solid currentColor;border-bottom:2px solid currentColor;transform:rotate(-45deg);margin-top:-3px}")
(setf (lui:toolkit-web-style :motif) #'apply-style)

(add-sheet :motif-fields
 #j".lui-motif-field{cursor:text}.lui-motif-field:focus-visible{outline:1px solid var(--lui-accent);outline-offset:-3px}.lui-motif-field:disabled{cursor:not-allowed}")
