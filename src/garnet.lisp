(defpackage #:lui.garnet
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*garnet-defaults*))

(in-package #:lui.garnet)

(lui::expose-api *garnet-defaults*)

(defvar *garnet-defaults*
  '(:palette (:background "#ffffff" :foreground "#000000" :accent "#000000") :terminal-border "++++-|" :opacity 1
    :radius 0 :frost 0
    :font-family :monospace :font-weight :bold)
  "Garnet uses black outlines, offset shadows, and bold monospace labels.
Bind this plist to change its colors or typography for a group of controls.")

(define-toolkit :garnet *garnet-defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)
