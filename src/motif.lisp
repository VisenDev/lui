(defpackage #:lui.motif
  (:use #:cl #:lui.fn #:lui.widgets #:lui.frame)
  (:export #:label #:button #:checkbox #:slider #:text-field #:panel #:tab
           #:canvas #:gauge #:list-item
           #:*defaults*))

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

(fn tab (id (text string) &rest options)
  (apply #'declare-widget :tab :motif id text
         :value (not (null (getf options :selected-p)))
         (loop :for (key value) :on (append options *defaults*) :by #'cddr
               :unless (eq key :selected-p) :append (list key value))))

(fn checkbox (id value (text string) &rest options)
  (value-widget :checkbox :motif id value text (append options *defaults*)))

(fn slider (id (value real) &rest options)
  (value-widget :slider :motif id value (getf options :text "")
                (loop :for (key val) :on (append options *defaults*)
                      :by #'cddr
                      :unless (eq key :text)
                        :append (list key val))))

(fn text-field (id (value string) &rest options)
  (value-widget :text-field :motif id value "" (append options *defaults*)))

(fn list-item (id (text string) &rest options)
  (apply #'declare-widget :list-item :motif id text
         :value (not (null (getf options :selected-p)))
         (loop :for (key value) :on (append options *defaults*) :by #'cddr
               :unless (eq key :selected-p) :append (list key value))))

(fn gauge (id (fraction real) &rest options)
  (apply #'declare-widget :gauge :motif id ""
         :value (max 0 (min 1 fraction)) (append options *defaults*)))

(fn canvas (id (commands list) &rest options)
  (apply #'declare-widget :canvas :motif id ""
         :value commands (append options *defaults*)))

(defmacro panel ((&rest options) &body body)
  `(let ((*parent* (declare-panel :motif
                    (append (list ,@options) *defaults*))))
     ,@body))
