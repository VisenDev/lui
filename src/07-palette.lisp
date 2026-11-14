(defpackage #:lui.palette
  (:use #:cl #:%lui.fn)
  (:export
           #:palette #:palette-p #:make-palette #:available-palettes
           #:call-with-palette #:with-palette #:+palette-default+
           #:+palette-light+ #:+palette-dark+ #:+palette-ocean+
           #:+palette-forest+ #:palette-thumb #:palette-control-background
           #:palette-background #:palette-foreground #:palette-accent
           #:palette-window-background #:palette-selection #:palette-border
           #:palette-disabled #:palette-disabled-accent
           #:palette-disabled-surface #:palette-disabled-bevel-light
           #:palette-disabled-bevel-dark #:palette-outline #:palette-light
           #:palette-shadow #:palette-bevel-light #:palette-bevel-dark
           #:palette-track #:palette-cell-background
           #:palette-cell-foreground #:palette-on-accent #:%resolve-palette))
(in-package #:lui.palette)

(defvar *palette* nil)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct palette
    "Semantic color overrides. NIL roles inherit the enclosing scope."
    (control-background nil :type (or null string) :read-only t)
    (background nil :type (or null string) :read-only t)
    (foreground nil :type (or null string) :read-only t)
    (accent nil :type (or null string) :read-only t)
    (window-background nil :type (or null string) :read-only t)
    (selection nil :type (or null string) :read-only t)
    (border nil :type (or null string) :read-only t)
    (disabled nil :type (or null string) :read-only t)
    (disabled-accent nil :type (or null string) :read-only t)
    (disabled-surface nil :type (or null string) :read-only t)
    (disabled-bevel-light nil :type (or null string) :read-only t)
    (disabled-bevel-dark nil :type (or null string) :read-only t)
    (outline nil :type (or null string) :read-only t)
    (light nil :type (or null string) :read-only t)
    (shadow nil :type (or null string) :read-only t)
    (bevel-light nil :type (or null string) :read-only t)
    (bevel-dark nil :type (or null string) :read-only t)
    (track nil :type (or null string) :read-only t)
    (cell-background nil :type (or null string) :read-only t)
    (cell-foreground nil :type (or null string) :read-only t)
    (on-accent nil :type (or null string) :read-only t)
    (thumb nil :type (or null string) :read-only t)))

;; Preserve non-scalar constant identity when a source file or FASL is reloaded.
(defconstant +palette-default+
  (if (boundp '+palette-default+) (symbol-value '+palette-default+)
      ;; else
      (make-palette))
  "Built-in immutable palette for WITH-PALETTE.")
(defconstant +palette-light+
  (if (boundp '+palette-light+) (symbol-value '+palette-light+)
      ;; else
      (make-palette :control-background "#ffffff" :background "#eeeeee"
                    :foreground "#202124" :accent "#2563eb"
                    :window-background "#e4e7eb" :selection "#dbeafe" :border
                    "#808891"))
  "Built-in immutable palette for WITH-PALETTE.")
(defconstant +palette-dark+
  (if (boundp '+palette-dark+) (symbol-value '+palette-dark+)
      ;; else
      (make-palette :control-background "#424954" :background "#292d35"
                    :foreground "#eeeeee" :accent "#79b8ff"
                    :disabled "#89919d" :disabled-accent "#626c7a"
                    :disabled-surface
                    "#343a44"
                    :disabled-bevel-light "#424954" :disabled-bevel-dark
                    "#242830"
                    :window-background "#1d2026" :selection "#34465e" :border
                    "#78818f"
                    :outline "#aab4c3" :light "#424954" :shadow "#111318"
                    :bevel-light "#505866" :bevel-dark "#171a20" :track
                    "#626c7a"
                    :cell-background "#23272e" :cell-foreground "#eeeeee"
                    :on-accent
                    "#101820"))
  "Built-in immutable palette for WITH-PALETTE.")
(defconstant +palette-ocean+
  (if (boundp '+palette-ocean+) (symbol-value '+palette-ocean+)
      ;; else
      (make-palette :control-background "#f1fbfd" :background "#dceef3"
                    :foreground "#123544" :accent "#087e9a"
                    :window-background "#bfdce5" :selection "#b7e5ef" :border
                    "#4c8696"
                    :cell-background "#f1fbfd" :cell-foreground "#123544"))
  "Built-in immutable palette for WITH-PALETTE.")
(defconstant +palette-forest+
  (if (boundp '+palette-forest+) (symbol-value '+palette-forest+)
      ;; else
      (make-palette :control-background "#f5faf1" :background "#e4ecdf"
                    :foreground "#243b28" :accent "#387348"
                    :window-background "#cbdac4" :selection "#c5dfbd" :border
                    "#6b8762"
                    :cell-background "#f5faf1" :cell-foreground "#243b28"))
  "Built-in immutable palette for WITH-PALETTE.")


(defparameter *named-palettes*
  (list (cons :default +palette-default+)
        (cons :light +palette-light+)
        (cons :dark +palette-dark+)
        (cons :ocean +palette-ocean+)
        (cons :forest +palette-forest+)))

(fn (available-palettes (vector symbol)) ()
  "Return the names accepted by WITH-PALETTE."
  (map '(vector symbol) #'car *named-palettes*))

(defparameter *palette-readers*
  '((:control-background . palette-control-background)
    (:background . palette-background)
    (:foreground . palette-foreground) (:accent . palette-accent)
    (:window-background . palette-window-background)
    (:selection . palette-selection)
    (:border . palette-border) (:disabled . palette-disabled)
    (:disabled-accent . palette-disabled-accent)
    (:disabled-surface . palette-disabled-surface)
    (:disabled-bevel-light . palette-disabled-bevel-light)
    (:disabled-bevel-dark . palette-disabled-bevel-dark)
    (:outline . palette-outline)
    (:light . palette-light) (:shadow . palette-shadow)
    (:bevel-light . palette-bevel-light) (:bevel-dark . palette-bevel-dark)
    (:track . palette-track) (:cell-background . palette-cell-background)
    (:cell-foreground . palette-cell-foreground)
    (:on-accent . palette-on-accent) (:thumb . palette-thumb))
  "Palette roles and their standard structure readers.")

(fn (palette-options list) ((palette palette))
  "Translate non-NIL palette fields into widget options for the current toolkit."
  (loop :for (role . reader) :in *palette-readers*
        :for color := (funcall reader palette)
        :when color :append (list role color)))

(fn (call-with-palette (values &rest t))
    ((palette (or palette symbol)) (draw function))
  "Call DRAW with a resolved palette dynamically bound for declarations."
  (let* ((value (etypecase palette
                  (symbol (or (cdr (assoc palette *named-palettes*))
                              (error '%lui.conditions:configuration-error
                                     :setting :palette :value palette
                                     :operation :call-with-palette
                                     :format-control "Unknown palette ~S."
                                     :format-arguments (list palette))))
                  (palette palette)))
         (*palette* (append (palette-options value) *palette*)))
    (funcall draw)))

(defmacro with-palette ((palette) &body body)
  "Draw BODY with a PALETTE instance or a built-in name such as :DARK.
NIL roles inherit enclosing colors; the parent scope is restored on exit."
  `(call-with-palette ,palette (lambda () ,@body)))

(fn (%resolve-palette list) ((defaults list))
  "Resolve a palette object, provider, or registered palette name."
  (labels ((colors (tail)
             (cond ((null tail) %lui.widgets:*base-palette*)
                   ((eq (car tail) :palette) (append (cadr tail) (colors
                                                                  (cddr
                                                                   tail))))
                   ((member (car tail) '(:foreground :background :accent))
                    (list* (car tail) (cadr tail) (colors (cddr tail))))
                   (t (colors (cddr tail))))))
    (append *palette* (colors defaults))))
