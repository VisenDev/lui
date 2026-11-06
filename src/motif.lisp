(defpackage #:lui.motif
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*defaults*))

(in-package #:lui.motif)

(defvar *defaults*
  '(:background "#b8b8b8" :foreground "#101010" :opacity 1
    :radius 0 :frost 0 :accent "#4050a0")
  "Toolkit defaults; bind this plist to customize a group of widgets.")

(define-toolkit :motif *defaults* panel
  label button tab checkbox slider text-field cell list-item gauge canvas)
