(defpackage #:lui.paint-macos
  (:use #:cl #:lui.fn #:lui.layout #:lui.frame #:lui.widgets #:lui.draw))
(in-package #:lui.paint-macos)

(fn (macos-bevel t)
    ((renderer renderer) (widget widget) (box box) &optional
     ((recessed boolean) nil) ((disabled boolean) nil))
  "Paint the macOS surface treatment with rounded fill and edge accents."
  (declare (ignore recessed))
  (outline renderer box (min 6 (widget-radius widget))
           (widget-color widget (if disabled :disabled-surface :border))
           0.65f0 1))

(fn (paint-macos-scrollbar t) ((renderer renderer) (node element))
  "Paint the macOS scrollbar track and thumb."
  (shape renderer (inset-box (scrollbar-thumb node) 2) 4
         (widget-color (element-content node) :track) 0.8f0))

(register-standard-painter :macos 6 #'paint-macos-scrollbar #'macos-bevel
                           :flat t)
