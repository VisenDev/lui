(defpackage #:lui.glass
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*defaults*))

(in-package #:lui.glass)

(defvar *defaults*
  '(:palette (:window-background "#202430" :background "#303040" :foreground "#ffffff" :accent "#258bff") :opacity 0.35
    :radius 12 :frost 12 :terminal-border "╭╮╰╯─│")
  "Glass uses rounded, translucent surfaces. Bind this plist to change their
tint, corner radius, opacity, or frost for a group of controls.")

(define-toolkit :glass *defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)
