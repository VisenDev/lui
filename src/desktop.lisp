(defpackage #:lui.macos
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell #:*defaults*))

(in-package #:lui.macos)

(defvar *defaults*
  '(:palette (:background "#dddddd" :foreground "#000000" :accent "#000000")
    :terminal-border "++++-|" :opacity 1 :radius 4 :frost 0)
  "Classic Macintosh gray controls with crisp double outlines.
Bind this plist to customize the surface, ink, and selection colors.")

(define-toolkit :macos *defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)

(defpackage #:lui.qt
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell #:*defaults*))

(in-package #:lui.qt)

(defvar *defaults*
  '(:palette (:background "#efefef" :foreground "#202020" :accent "#308cc6")
    :terminal-border "++++-|" :opacity 1 :radius 2 :frost 0)
  "Qt Fusion-inspired neutral controls with fine raised edges and blue focus.
Bind this plist to customize the surface, ink, and selection colors.")

(define-toolkit :qt *defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)
