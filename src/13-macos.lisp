(defpackage #:lui.macos
  (:use #:cl)
  (:import-from #:lui.toolkit #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel
           #:tab
           #:canvas #:gauge #:list-item #:cell #:*macos-defaults*))

(in-package #:lui.macos)

(defvar *macos-defaults*
  '(:palette (:window-background "#f5f2ef" :background "#f0edeb"
              :control-background "#ffffff" :foreground "#303030" :accent "#007aff" :selection "#dbeaff"
              :border "#c7c4c1" :track "#b6b4b2" :light "#ffffff"
              :disabled "#969390" :disabled-surface "#e3e0dd")
    :terminal-border "++++-|" :opacity 1 :radius 6 :frost 0)
  "Ventura-inspired warm surfaces, rounded controls, subtle borders, and blue accents.
Bind this plist to customize the surface, ink, and selection colors.")

(define-toolkit :macos *macos-defaults* panel
                label button tab checkbox radio slider text-field cell
                list-item gauge canvas)
