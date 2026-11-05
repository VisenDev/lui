(defpackage #:lui.garnet
  (:use #:cl #:lui.fn #:lui.widgets #:lui.frame)
  (:export #:label #:button #:checkbox #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item
           #:*defaults*))

(in-package #:lui.garnet)

(defvar *defaults*
  '(:background "#ffffff" :foreground "#000000" :opacity 1
    :radius 0 :frost 0 :accent "#000000"
    :font-family :monospace :font-weight :bold)
  "Collection defaults; bind this plist to customize a group of widgets.")

(fn label ((text string) &rest options)
  (apply #'declare-widget :label :garnet nil text
         (append options *defaults*)))

(fn button (id (text string) &rest options)
  (apply #'declare-widget :button :garnet id text
         (append options *defaults*)))

(fn tab (id (text string) &rest options)
  (apply #'declare-widget :tab :garnet id text
         :value (not (null (getf options :selected-p)))
         (loop :for (key value) :on (append options *defaults*) :by #'cddr
               :unless (eq key :selected-p) :append (list key value))))

(fn checkbox (id value (text string) &rest options)
  (value-widget :checkbox :garnet id value text (append options *defaults*)))

(fn slider (id (value real) &rest options)
  (value-widget :slider :garnet id value (getf options :text "")
                (loop :for (key val) :on (append options *defaults*)
                      :by #'cddr
                      :unless (eq key :text)
                        :append (list key val))))

(fn text-field (id (value string) &rest options)
  (value-widget :text-field :garnet id value "" (append options *defaults*)))

(fn list-item (id (text string) &rest options)
  (apply #'declare-widget :list-item :garnet id text
         :value (not (null (getf options :selected-p)))
         (loop :for (key value) :on (append options *defaults*) :by #'cddr
               :unless (eq key :selected-p) :append (list key value))))

(fn gauge (id (fraction real) &rest options)
  (apply #'declare-widget :gauge :garnet id ""
         :value (max 0 (min 1 fraction)) (append options *defaults*)))

(fn canvas (id (commands list) &rest options)
  (apply #'declare-widget :canvas :garnet id ""
         :value commands (append options *defaults*)))

(defmacro panel ((&rest options) &body body)
  `(let ((*parent* (declare-panel :garnet
                    (append (list ,@options) *defaults*))))
     ,@body))
