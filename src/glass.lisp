(defpackage #:lui.glass
  (:use #:cl #:lui.fn #:lui.widgets)
  (:export #:label #:button #:checkbox #:slider #:text-field))

(in-package #:lui.glass)

(fn label ((text string) &rest options)
  (apply #'declare-widget :label :glass nil text options))

(fn button (id (text string) &rest options)
  (apply #'declare-widget :button :glass id text options))

(fn checkbox (id value (text string) &rest options)
  (value-widget :checkbox :glass id value text options))

(fn slider (id (value real) &rest options)
  (value-widget :slider :glass id value (getf options :text "")
                (loop :for (key val) :on options :by #'cddr
                      :unless (eq key :text)
                        :append (list key val))))

(fn text-field (id (value string) &rest options)
  (value-widget :text-field :glass id value "" options))
