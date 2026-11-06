(defpackage #:lui.glass
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*defaults*))

(in-package #:lui.glass)

(defvar *defaults*
  '(:background "#303040" :foreground "#ffffff" :opacity 0.35
    :radius 12 :frost 12 :accent "#258bff")
  "Toolkit defaults; bind this plist to customize a group of widgets.")

(define-toolkit :glass *defaults* panel
  label button tab checkbox slider text-field cell list-item gauge canvas)
