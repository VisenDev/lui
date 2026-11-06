(defpackage #:lui.garnet
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*defaults*))

(in-package #:lui.garnet)

(defvar *defaults*
  '(:background "#ffffff" :foreground "#000000" :opacity 1
    :radius 0 :frost 0 :accent "#000000"
    :font-family :monospace :font-weight :bold)
  "Toolkit defaults; bind this plist to customize a group of widgets.")

(define-toolkit :garnet *defaults* panel
  label button tab checkbox slider text-field cell list-item gauge canvas)
