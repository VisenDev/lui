(defpackage #:lui.motif
  (:use #:cl #:lui.fn #:lui.widgets #:lui.frame)
  (:export #:label #:button #:checkbox #:slider #:text-field #:panel #:*defaults*))

(in-package #:lui.motif)

(defvar *defaults*
  '(:background "#b8b8b8" :foreground "#101010" :opacity 1
    :radius 0 :frost 0 :accent "#4050a0")
  "Collection defaults; bind this plist to customize a group of widgets.")

(fn label ((text string) &rest options)
  (apply #'declare-widget :label :motif nil text (append options *defaults*)))

(fn button (id (text string) &rest options)
  (apply #'declare-widget :button :motif id text
         (append options *defaults*)))

(fn checkbox (id value (text string) &rest options)
  (value-widget :checkbox :motif id value text (append options *defaults*)))

(fn slider (id (value real) &rest options)
  (value-widget :slider :motif id value (getf options :text "")
                (loop :for (key val) :on (append options *defaults*) :by #'cddr
                      :unless (eq key :text)
                        :append (list key val))))

(fn text-field (id (value string) &rest options)
  (value-widget :text-field :motif id value "" (append options *defaults*)))

(defmacro panel ((&rest options) &body body)
  `(let ((*parent* (declare-panel :motif
                    (append (list ,@options) *defaults*))))
     ,@body))
