(defpackage #:lui.qt
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:import-from #:lui
                #:*qt-defaults*)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel
           #:tab
           #:canvas #:gauge #:list-item #:cell #:*qt-defaults*))

(in-package #:lui.qt)

(defvar *qt-defaults*
  '(:palette (:background "#efefef" :foreground "#202020" :accent "#308cc6")
    :terminal-border "++++-|" :opacity 1 :radius 2 :frost 0)
  "Qt Fusion-inspired neutral controls with fine raised edges and blue focus.
Bind this plist to customize the surface, ink, and selection colors.")

(define-toolkit :qt *qt-defaults* panel
                label button tab checkbox radio slider text-field cell
                list-item gauge canvas)
