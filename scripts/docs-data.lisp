(defpackage #:lui.docs.generator
  (:use #:cl)
  (:export #:collect-entries #:write-data #:main))
(in-package #:lui.docs.generator)

;; Read syntax, never evaluate application forms or load foreign libraries.
(defun token-end-p (character)
  (or (null character)
      (find character '(#\Space #\Tab #\Newline #\Return #\Page
                        #\( #\) #\' #\` #\, #\" #\;))))

(defun neutral-source (text)
  "Escape package markers without changing strings, comments or characters."
  (with-input-from-string (input text)
    (with-output-to-string (output)
      (labels ((copy-quoted (delimiter)
                 (write-char delimiter output)
                 (loop :for c := (read-char input nil) :while c
                       :do (write-char c output)
                           (cond ((char= c #\\)
                                  (let ((next (read-char input nil)))
                                    (when next (write-char next output))))
                                 ((char= c delimiter) (return)))))
               (copy-block ()
                 (write-string "#|" output)
                 (loop :with depth := 1
                       :for c := (read-char input nil) :while c
                       :for next := (peek-char nil input nil)
                       :do (write-char c output)
                           (cond ((and (char= c #\#) (eql next #\|))
                                  (write-char (read-char input) output)
                                  (incf depth))
                                 ((and (char= c #\|) (eql next #\#))
                                  (write-char (read-char input) output)
                                  (when (zerop (decf depth)) (return))))))
               (copy-token (first)
                 (let ((token
                         (with-output-to-string (part)
                           (write-char first part)
                           (loop :for c := (peek-char nil input nil)
                                 :until (token-end-p c)
                                 :do (write-char (read-char input) part)))))
                   (loop :for c :across token :for i :from 0
                         :do (when (and (char= c #\:) (> i 0)
                                        (not (char= (char token 0) #\:))
                                        (not (and (= i 1)
                                                  (char= first #\#))))
                               (write-char #\\ output))
                             (write-char c output)))))
        (loop :for c := (read-char input nil) :while c
              :do (cond
                    ((or (char= c #\") (char= c #\|)) (copy-quoted c))
                    ((char= c #\;)
                     (write-char c output)
                     (loop :for next := (read-char input nil) :while next
                           :do (write-char next output)
                           :when (char= next #\Newline) :do (return)))
                    ((and (char= c #\#)
                          (eql (peek-char nil input nil) #\|))
                     (read-char input) (copy-block))
                    ((and (char= c #\#)
                          (eql (peek-char nil input nil) #\\))
                     (write-string "#\\" output) (read-char input)
                     (let ((next (read-char input nil)))
                       (when next (write-char next output)))
                     (loop :for next := (peek-char nil input nil)
                           :until (token-end-p next)
                           :do (write-char (read-char input) output)))
                    ((token-end-p c) (write-char c output))
                    (t (copy-token c))))))))

(defun source-readtable ()
  (let ((table (copy-readtable nil)))
    (flet ((conditional (stream character argument)
             (declare (ignore character argument))
             (read stream t nil t)
             (read stream t nil t))
           (javascript (stream character argument)
             (declare (ignore character argument))
             (if (eql (peek-char nil stream nil) #\")
                 (read stream t nil t)
                 (loop :until (token-end-p (peek-char nil stream nil))
                       :do (read-char stream)))
             :javascript))
      ;; Retain every conditional branch: this is a cross-platform reference.
      (set-dispatch-macro-character #\# #\+ #'conditional table)
      (set-dispatch-macro-character #\# #\- #'conditional table)
      (set-dispatch-macro-character #\# #\j #'javascript table))
    table))

(defun local-name (symbol)
  (let* ((name (string symbol)) (colon (position #\: name :from-end t)))
    (if colon (subseq name (1+ colon)) name)))

(defun named-p (symbol name)
  (and (symbolp symbol) (string= (local-name symbol) name)))

(defun plain-form (form)
  (cond ((keywordp form) form)
        ((symbolp form) (intern (local-name form) :cl-user))
        ((consp form) (cons (plain-form (car form))
                            (plain-form (cdr form))))
        (t form)))

(defun signature (name args)
  (let ((*package* (find-package :cl-user)) (*print-case* :downcase)
        (*print-pretty* nil) (*print-circle* nil))
    (write-to-string (cons (plain-form name) (plain-form args)))))

(defun typed-arguments (arguments)
  (let ((state :required))
    (mapcar (lambda (argument)
              (cond
                ((member argument '(&optional &rest &key &aux))
                 (setf state argument) argument)
                ((atom argument) argument)
                ((eq state :required) (first argument))
                ((consp (first argument))
                 (cons (caar argument) (cdr argument)))
                (t argument)))
            arguments)))

(defun collect-entries (&optional (paths (directory "src/*.lisp")))
  "Extract exported source APIs, including conditional and generated forms."
  (let ((packages (make-hash-table :test 'equal))
        (definitions (make-hash-table :test 'equal))
        (setters (make-hash-table :test 'equal))
        (current "cl-user") (source ""))
    (labels
        ((key (package name) (list package (local-name name)))
         (record (name kind args documentation)
           (when (consp name)
             (setf (gethash (key current (second name)) setters)
                   (signature name args))
             (return-from record nil))
           (let ((base name))
             (setf (gethash (key current base) definitions)
                   (list :package current :name (local-name base) :kind kind
                         :signature (if (member kind '(:variable :constant
                                                       :structure :type))
                                        (string-downcase (local-name base))
                                        (signature name args))
                         :documentation (or documentation "")
                         :source source))))
         (structure (form)
           (let* ((spec (second form))
                  (name (if (consp spec) (car spec) spec))
                  (options (when (consp spec) (cdr spec)))
                  (slots (cddr form))
                  (doc (when (stringp (car slots)) (pop slots)))
                  (prefix (concatenate 'string (local-name name) "-")))
             (record name :structure nil doc)
             (let ((constructors
                     (remove-if-not (lambda (x) (eq (car x) :constructor))
                                    options)))
               (dolist (constructor
                        (or constructors
                            (list (list :constructor
                                        (intern (concatenate 'string "MAKE-"
                                                 (string name)))))))
                 (when (second constructor)
                   (record
                    (second constructor) :function
                    (if (cddr constructor) (third constructor)
                        (cons '&key
                              (mapcar (lambda (slot)
                                        (if (consp slot)
                                            (list (first slot) (second slot))
                                            slot)) slots)))
                    (format nil "Construct a ~A." name)))))
             (dolist (pair `((:predicate ,(concatenate 'string (string name)
                                                       "-P") (object))
                            (:copier ,(concatenate 'string "COPY-"
                                                   (string name))
                             (instance))))
               (let* ((option (assoc (first pair) options))
                      (symbol (if option (second option)
                                  (intern (second pair)))))
                 (when symbol
                   (record symbol :function (third pair)
                           (format nil "~A for ~A." (first pair) name)))))
             (let ((option (assoc :conc-name options)))
               (when option (setf prefix (or (second option) ""))))
             (dolist (slot slots)
               (let ((slot-name (if (consp slot) (car slot) slot)))
                 (record (intern (concatenate 'string (string prefix)
                                              (string slot-name)))
                         :function '(instance)
                         (format nil "Read~A the ~A slot of ~A."
                                 (if (and (consp slot)
                                          (getf (cddr slot) :read-only))
                                     "" " or set")
                                 slot-name name))))))
         (walk (form)
           (when (consp form)
             (let ((head (local-name (car form))))
               (cond
                 ((string= head "DEFPACKAGE")
                  (let ((package (string-downcase (string (second form)))))
                    (setf (gethash package packages) (cddr form))))
                 ((string= head "IN-PACKAGE")
                  (setf current (string-downcase (string (second form)))))
                 ((member head '("PROGN" "EVAL-WHEN") :test #'string=)
                  (mapc #'walk (if (string= head "PROGN") (cdr form)
                                  (cddr form))))
                 ((member head '("DEFUN" "DEFMACRO" "FN" "DEFINE-CONTROL")
                          :test #'string=)
                  (let* ((name (second form)) (args (third form))
                         (kind (if (string= head "DEFMACRO") :macro
                                   :function)))
                    (when (string= head "FN")
                      (when (consp name) (setf name (car name)))
                      (setf args (typed-arguments args)))
                    (when (string= head "DEFINE-CONTROL")
                      (setf args (append args '(&optional options))))
                    (record name kind args
                            (when (stringp (fourth form)) (fourth form)))))
                 ((string= head "DEFCFUN")
                  (let* ((spec (second form))
                         (name (if (consp spec) (second spec) spec))
                         (body (cdddr form)))
                    (record name :function
                            (mapcar #'first (remove-if #'stringp body))
                            (find-if #'stringp body))))
                 ((member head '("DEFSTRUCT" "DEFSTRUCT*") :test #'string=)
                  (structure form))
                 ((member head '("DEFVAR" "DEFPARAMETER" "DEFCONSTANT")
                          :test #'string=)
                  (record (second form)
                          (if (string= head "DEFCONSTANT") :constant
                              :variable)
                          nil (when (stringp (fourth form)) (fourth form))))
                 ((string= head "DEFTYPE")
                  (record (second form) :type nil
                          (when (stringp (fourth form)) (fourth form))))
                 ((string= head "SETF")
                  (loop :for (place value) :on (cdr form) :by #'cddr
                        :when (and (consp place)
                                   (named-p (car place) "DOCUMENTATION")
                                   (consp (second place))
                                   (named-p (car (second place)) "QUOTE")
                                   (stringp value))
                          :do (let ((entry (gethash
                                            (key current
                                                 (second (second place)))
                                            definitions)))
                                (when entry
                                  (setf (getf entry :documentation)
                                        value)))))
                 ((string= head "DEFINE-COLLECTION")
                  (record (fourth form) :macro '(options &body body)
                          "Draw a panel in this collection.")
                  (loop :for name :in (cddddr form)
                        :for args :in '((text) (id text) (id text)
                                       (id value text) (id value) (id value)
                                       (id text) (id text) (id fraction)
                                       (id commands))
                        :do (record name :function
                                    (append args '(&optional options
                                                   &rest legacy))
                                    nil)))))))
         (resolve (package name &optional seen)
           (unless (member package seen :test #'equal)
             (or (gethash (key package name) definitions)
                 (loop :for option :in (gethash package packages)
                       :thereis
                       (and (eq (car option) :import-from)
                            (find (local-name name) (cddr option)
                                  :key #'local-name :test #'string=)
                            (resolve (string-downcase
                                      (string (second option)))
                                     name (cons package seen))))
                 (loop :for option :in (gethash package packages)
                       :thereis
                       (and (eq (car option) :use)
                            (loop :for parent :in (cdr option)
                                  :thereis
                                  (resolve (string-downcase (string parent))
                                           name (cons package seen)))))))))
      (let ((*package* (find-package :lui.docs.generator))
            (*readtable* (source-readtable)) (*read-eval* nil))
        (dolist (path (sort (copy-list paths) #'string< :key #'namestring))
          (setf current "cl-user"
                source (enough-namestring path *default-pathname-defaults*))
          (with-open-file (input path)
            (let ((text (make-string (file-length input))))
              (read-sequence text input)
              (with-input-from-string (stream (neutral-source text))
                (loop :for form := (read stream nil stream)
                      :until (eq form stream) :do (walk form)))))))
      (let ((entries nil))
        (maphash
         (lambda (package options)
           (dolist (option options)
             (when (eq (car option) :export)
               (dolist (name (cdr option))
                 (let* ((definition (resolve package name))
                        (entry (copy-list definition)))
                   (unless entry
                     (error "No source definition for ~A:~A." package name))
                   (let ((setter (gethash
                                  (key (getf entry :package) name) setters)))
                     (when setter
                       (setf (getf entry :signature)
                             (format nil "~A~%~A"
                                     (getf entry :signature) setter))))
                   (setf (getf entry :package) package)
                   ;; Compatibility controls share their public API docs.
                   (when (zerop (length (getf entry :documentation)))
                     (let ((public (gethash (key "lui" name) definitions)))
                       (when public
                         (setf (getf entry :documentation)
                               (getf public :documentation)))))
                   (push entry entries))))))
         packages)
        (sort entries #'string<
              :key (lambda (entry)
                     (format nil "~A:~A" (getf entry :package)
                             (getf entry :name))))))))

(defun write-data (entries &optional (path "build/docs-data.lisp"))
  "Write deterministic Lisp data, loaded after EXAMPLES/DOCS.LISP."
  (ensure-directories-exist path)
  (with-open-file (output path :direction :output :if-exists :supersede)
    (write-line ";; Generated by scripts/docs-data.lisp; do not edit." output)
    (write-line "(in-package #:lui.docs)" output)
    (write-line "(defparameter *entries*" output)
    (write-char #\' output)
    (let ((*print-case* :downcase) (*print-pretty* t)
          (*print-right-margin* 76))
      (write entries :stream output :escape t))
    (write-line ")" output)))

(defun main ()
  (let ((entries (collect-entries)))
    (write-data entries)
    (format t "Generated ~D public API entries in build/docs-data.lisp.~%"
            (length entries))))

(unless (uiop:getenv "LUI_DOCS_LIBRARY_ONLY") (main))
