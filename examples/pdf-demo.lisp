(load "scripts/setup.lisp")
(asdf:load-system "lui/pdf")

(defpackage #:lui.pdf-demo
  (:use #:cl)
  (:export #:make-document #:main))

(in-package #:lui.pdf-demo)

(defun make-document ()
  (lui:column (:width (lui:grow) :gap (lui:units 2)
                     :padding (lui:units 4))
    (lui:panel (lui:opt :width (lui:grow) :padding (lui:units 3)
                        :opacity 1
                        :gap (lui:units 1) :background "#18324b")
      (lui:label "FIELDNOTES  /  PRODUCT UPDATE"
                 (lui:opt :foreground "#a8d9d0"))
      (lui:label "A clearer path to launch"
                 (lui:opt :foreground "#ffffff"))
      (lui:label "WEEKLY PROJECT BRIEF  /  06 NOV 2026"
                 (lui:opt :foreground "#c4d2df")))
    (lui:label "Three workstreams lead up to the November 18 release."
               (lui:opt :foreground "#18324b"))
    (lui:row (:width (lui:grow) :gap (lui:units 2))
      (lui:panel (lui:opt :width (lui:grow) :padding (lui:units 2)
                          :gap (lui:units 1) :background "#ffffff" :opacity 1)
        (lui:label "64%" (lui:opt :foreground "#147d73"))
        (lui:label "MILESTONES COMPLETE" (lui:opt :foreground "#52677b")))
      (lui:panel (lui:opt :width (lui:grow) :padding (lui:units 2)
                          :gap (lui:units 1) :background "#ffffff" :opacity 1)
        (lui:label "18 Nov" (lui:opt :foreground "#147d73"))
        (lui:label "TARGET RELEASE" (lui:opt :foreground "#52677b"))))
    (lui:label "WORKSTREAMS" (lui:opt :foreground "#18324b"))
    (lui:table (:width (lui:grow) :column-gap (lui:units 2)
                 :gap (lui:units 1))
      (lui:table-row ()
        (lui:label "WORKSTREAM" (lui:opt :foreground "#52677b"))
        (lui:label "STATUS" (lui:opt :foreground "#52677b"))
        (lui:label "NEXT CHECKPOINT" (lui:opt :foreground "#52677b")))
      (lui:table-row ()
        (lui:label "Core experience" (lui:opt :foreground "#18324b"))
        (lui:label "On track" (lui:opt :foreground "#147d73"))
        (lui:label "Usability review / 10 Nov" (lui:opt :foreground "#18324b")))
      (lui:table-row ()
        (lui:label "Visual system" (lui:opt :foreground "#18324b"))
        (lui:label "In review" (lui:opt :foreground "#a36518"))
        (lui:label "Approve final tokens / 11 Nov" (lui:opt :foreground "#18324b")))
      (lui:table-row ()
        (lui:label "Launch readiness" (lui:opt :foreground "#18324b"))
        (lui:label "On track" (lui:opt :foreground "#147d73"))
        (lui:label "Support handoff / 16 Nov" (lui:opt :foreground "#18324b"))))
    (lui:panel (lui:opt :width (lui:grow) :padding (lui:units 2)
                        :gap (lui:units 1) :background "#e2efed" :opacity 1)
      (lui:label "THIS WEEK'S FOCUS" (lui:opt :foreground "#147d73"))
      (lui:label "Validate the first-run flow with five customers, and prioritize the fixes before release."
                 (lui:opt :foreground "#18324b")))
    (lui:label "FIELDNOTES  /  PRODUCT & DESIGN"
               (lui:opt :foreground "#52677b"))))

(defun main (&optional (pathname #p"build/pdf-demo.pdf"))
  (ensure-directories-exist pathname)
  (lui:render-pdf #'make-document pathname
                      :title "Fieldnotes weekly project brief"
                      :width 612 :height 792 :background "#f4f7fb"))

(main)
