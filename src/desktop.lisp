(defpackage #:lui.macos
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell #:*macos-defaults*))

(in-package #:lui.macos)

(lui::expose-api *macos-defaults*)

(defvar *macos-defaults*
  '(:palette (:window-background "#f5f2ef" :background "#f0edeb"
               :control-background "#ffffff" :foreground "#303030" :accent "#007aff" :selection "#dbeaff"
               :border "#c7c4c1" :track "#b6b4b2" :light "#ffffff"
               :disabled "#969390" :disabled-surface "#e3e0dd")
    :terminal-border "++++-|" :opacity 1 :radius 6 :frost 0)
  "Ventura-inspired warm surfaces, rounded controls, subtle borders, and blue accents.
Bind this plist to customize the surface, ink, and selection colors.")

(define-toolkit :macos *macos-defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)

(defpackage #:lui.qt
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell #:*qt-defaults*))

(in-package #:lui.qt)

(lui::expose-api *qt-defaults*)

(defvar *qt-defaults*
  '(:palette (:background "#efefef" :foreground "#202020" :accent "#308cc6")
    :terminal-border "++++-|" :opacity 1 :radius 2 :frost 0)
  "Qt Fusion-inspired neutral controls with fine raised edges and blue focus.
Bind this plist to customize the surface, ink, and selection colors.")

(define-toolkit :qt *qt-defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)
