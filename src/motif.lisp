(defpackage #:lui.motif
  (:use #:cl #:lui.fn #:lui.widgets)
  (:export #:label #:button #:checkbox #:slider #:text-field))

(in-package #:lui.motif)

(fn label ((text string) &rest options)
  (apply #'declare-widget :label :motif nil text options))

(fn button (id (text string) &rest options)
  (apply #'declare-widget :button :motif id text
    (append options '(:radius 0 :frost 0))))

(fn checkbox (id value (text string) &rest options)
  (value-widget :checkbox :motif id value text options))

(fn slider (id (value real) &rest options)
  (value-widget :slider :motif id value (getf options :text "")
    (loop :for (key val) :on options :by #'cddr :unless (eq key :text)
      :append (list key val))))

(fn text-field (id (value string) &rest options)
  (value-widget :text-field :motif id value "" options))
