(defpackage #:lui.glass.web
  (:use #:cl #:lui.fn #:lui.layout #:lui.widgets #:lui.web.style))
(in-package #:lui.glass.web)

(fn apply-style (dom (widget widget) (node element))
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
    (when (eq kind :scrollbar)
      (let* ((width (box-width (element-box node)))
             (bounds (scrollbar-thumb node))
             (inset (min 2 (/ (min width (box-height bounds)) 4)))
             (foreground (widget-foreground widget))
             (thumb (jscl/ffi:oget dom "firstElementChild")))
        (style dom "background"
               (format nil "color-mix(in srgb, ~A 8%, transparent)"
                       foreground))
        (style dom "border-radius" (px (/ width 2)))
        (style dom "--lui-scroll-base"
               (format nil "color-mix(in srgb, ~A 32%, transparent)"
                       foreground))
        (style dom "--lui-scroll-hover"
               (format nil "color-mix(in srgb, ~A 50%, transparent)"
                       foreground))
        (style thumb "left" (px inset))
        (style thumb "top"
               (px (+ (- (box-y bounds) (box-y (element-box node))) inset)))
        (style thumb "height"
               (px (max 0 (- (box-height bounds) (* 2 inset)))))
        (style thumb "width" (px (- width (* 2 inset))))
        (style thumb "background"
               "var(--lui-scroll-fill, var(--lui-scroll-base))")
        (style thumb "border"
               (format nil "1px solid color-mix(in srgb, ~A 40%, transparent)"
                       foreground))
        (style thumb "border-radius" (px (/ (- width (* 2 inset)) 2)))))
    (when (eq kind :gauge)
      (style dom "border-radius" (px (widget-radius widget))))
    (when (eq kind :slider) (style dom "--lui-thumb-radius" "7px"))
    (tab-underline dom widget)))

(setf (lui:toolkit-web-style :glass) #'apply-style)

(add-sheet :glass-scrollbars
 #j"[data-lui-surface=glass].lui-scrollbar:hover,[data-lui-surface=glass].lui-scrollbar:active{--lui-scroll-fill:var(--lui-scroll-hover)}")
