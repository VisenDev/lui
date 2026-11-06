(defpackage #:lui.glass.web
  (:use #:cl #:lui.fn #:lui.layout #:lui.widgets #:lui.web.style))
(in-package #:lui.glass.web)

(fn apply-style (dom (widget widget) (node element))
  (declare (ignore node))
  (let ((kind (widget-kind widget)))
    (when (framed-p widget)
      (style dom "border-radius" (px (widget-radius widget)))
      (style dom "border" (if (widget-disabled-p widget)
                            "1px solid #ffffff26" "1px solid #ffffff66")))
    (when (framed-p widget)
      (when (member kind '(:button :tab :text-field :checkbox))
        (style dom "padding" "5px 11px"))
      (style dom "background"
             (format nil "color-mix(in srgb, ~A ~D%, transparent)"
                     (widget-background widget)
                     (round (* 100 (widget-opacity widget)))))
      (style dom "backdrop-filter"
             (if (< (widget-opacity widget) 1)
                 (format nil "blur(~A) saturate(150%)"
                         (px (widget-frost widget))) "none"))
      (style dom "box-shadow"
             "inset 0 1px 1px #ffffff88, 0 3px 12px #00000044"))
    (when (eq kind :gauge)
      (style dom "border-radius" (px (widget-radius widget))))
    (when (eq kind :slider) (style dom "--lui-thumb-radius" "7px"))
    (tab-underline dom widget)))

(setf (lui:toolkit-web-style :glass) #'apply-style)
