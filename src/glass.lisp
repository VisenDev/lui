(defpackage #:lui.glass
  (:use #:cl #:lui.fn #:lui.widgets #:lui.frame)
  (:export #:label #:button #:checkbox #:slider #:text-field #:panel #:*defaults*))

(in-package #:lui.glass)

(defvar *defaults*
  '(:background "#303040" :foreground "#ffffff" :opacity 0.35
    :radius 12 :frost 12 :accent "#258bff")
  "Collection defaults; bind this plist to customize a group of widgets.")

(fn label ((text string) &rest options)
  (apply #'declare-widget :label :glass nil text (append options *defaults*)))

(fn button (id (text string) &rest options)
  (apply #'declare-widget :button :glass id text
         (append options *defaults*)))

(fn checkbox (id value (text string) &rest options)
  (value-widget :checkbox :glass id value text (append options *defaults*)))

(fn slider (id (value real) &rest options)
  (value-widget :slider :glass id value (getf options :text "")
                (loop :for (key val) :on (append options *defaults*) :by #'cddr
                      :unless (eq key :text)
                        :append (list key val))))

(fn text-field (id (value string) &rest options)
  (value-widget :text-field :glass id value "" (append options *defaults*)))

(defmacro panel ((&rest options) &body body)
  `(let ((*parent* (declare-panel :glass
                    (append (list ,@options) *defaults*))))
     ,@body))
