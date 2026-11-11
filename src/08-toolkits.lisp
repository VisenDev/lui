(defpackage #:lui.glass
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:import-from #:lui
    #:*glass-defaults*)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*glass-defaults*))

(in-package #:lui.glass)

(defvar *glass-defaults*
  '(:palette (:window-background "#202430" :background "#303040" :foreground
              "#ffffff" :accent "#258bff") :opacity 0.35f0
    :radius 12 :frost 12 :terminal-border "╭╮╰╯─│")
  "Glass uses rounded, translucent surfaces. Bind this plist to change their
tint, corner radius, opacity, or frost for a group of controls.")

(define-toolkit :glass *glass-defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)

(defpackage #:lui.motif
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:import-from #:lui
    #:*motif-defaults*)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*motif-defaults*))

(in-package #:lui.motif)

(defvar *motif-defaults*
  '(:palette (:background "#b8b8b8" :foreground "#101010" :accent "#4050a0") :terminal-border "++++-|" :opacity 1
    :radius 0 :frost 0 )
  "Motif uses opaque gray surfaces with raised buttons and recessed fields.
Bind this plist to adjust the surface, text, or selection accent colors.")

(define-toolkit :motif *motif-defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)

(defpackage #:lui.macos
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:import-from #:lui
    #:*macos-defaults*)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
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
  label button tab checkbox radio slider text-field cell list-item gauge canvas)

(defpackage #:lui.qt
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:import-from #:lui
    #:*qt-defaults*)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell #:*qt-defaults*))

(in-package #:lui.qt)

(defvar *qt-defaults*
  '(:palette (:background "#efefef" :foreground "#202020" :accent "#308cc6")
    :terminal-border "++++-|" :opacity 1 :radius 2 :frost 0)
  "Qt Fusion-inspired neutral controls with fine raised edges and blue focus.
Bind this plist to customize the surface, ink, and selection colors.")

(define-toolkit :qt *qt-defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)

(defpackage #:lui.garnet
  (:use #:cl)
  (:import-from #:lui #:define-toolkit)
  (:import-from #:lui
    #:*garnet-defaults*)
  (:export #:label #:button #:checkbox #:radio #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item #:cell
           #:*garnet-defaults*))

(in-package #:lui.garnet)

(defvar *garnet-defaults*
  '(:palette (:background "#ffffff" :foreground "#000000" :accent "#000000") :terminal-border "++++-|" :opacity 1
    :radius 0 :frost 0
    :font-family :monospace :font-weight :bold)
  "Garnet uses black outlines, offset shadows, and bold monospace labels.
Bind this plist to change its colors or typography for a group of controls.")

(define-toolkit :garnet *garnet-defaults* panel
  label button tab checkbox radio slider text-field cell list-item gauge canvas)
