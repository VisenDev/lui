(defpackage #:lui.motif
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*defaults*))

(in-package #:lui.motif)

(defvar *defaults*
  '(:palette (:background "#b8b8b8" :foreground "#101010" :accent "#4050a0") :terminal-border "++++-|" :opacity 1
    :radius 0 :frost 0 )
  "Motif uses opaque gray surfaces with raised buttons and recessed fields.
Bind this plist to adjust the surface, text, or selection accent colors.")

(define-toolkit :motif *defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)
