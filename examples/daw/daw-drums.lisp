(defpackage #:%lui.example.daw-drums
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
    #:note #:track-wave #:track-notes #:add-note #:remove-note
    #:note-start #:note-pitch #:song-beats)
  (:import-from #:%lui.example.daw-state
    #:session-song #:session-page #:session-playhead #:current-track
    #:editable-p #:checkpoint #:clear-selection #:playing-p)
  (:export #:draw #:drum-track-p #:toggle-step #:basic-beat #:clear-bar))
(in-package #:%lui.example.daw-drums)

(defun drum-track-p (session)
  "Select the step editor for the synthesized GM percussion kit."
  (eq :drums (track-wave (current-track session))))

(defun hit-at (track pitch beat)
  "Find an onset, so a sustained open hat does not light two step buttons."
  (find-if (lambda (note) (and (= pitch (note-pitch note))
                              (= beat (note-start note))))
           (track-notes track)))

(defun toggle-step (session pitch step)
  "Toggle one sixteenth-note drum hit as a single undoable edit."
  (declare (values))
  (when (editable-p session)
    (let* ((beat (+ (* 4 (session-page session)) (/ step 4)))
           (track (current-track session))
           (note (hit-at track pitch beat)))
      (when (< beat (song-beats (session-song session)))
        (checkpoint session)
        (clear-selection session)
        (if note (remove-note track note)
            (add-note track pitch beat
                      (min (if (= pitch 46) 1/2 1/4)
                           (- (song-beats (session-song session)) beat))
                      (case pitch (36 110) (38 100) (otherwise 76)))))))
  (values))

(defun clear-bar (session)
  "Clear the current drum bar without changing notes in other bars."
  (declare (values))
  (when (editable-p session)
    (checkpoint session)
    (clear-selection session)
    (let* ((start (* 4 (session-page session)))
           (track (current-track session))
           (notes (track-notes track))
           (retained (make-array (length notes) :element-type 'note
                                 :initial-contents notes
                                 :adjustable t :fill-pointer 0)))
      (loop :for note :across notes
            :unless (and (<= start (note-start note))
                         (< (note-start note) (+ start 4)))
              :do (vector-push note retained))
      (setf (track-notes track) retained)))
  (values))

(defun basic-beat (session)
  "Replace the current bar with kick, backbeat snare and eighth-note hats."
  (declare (values))
  (when (editable-p session)
    (clear-bar session)
    (let ((start (* 4 (session-page session)))
          (track (current-track session)))
      (dotimes (beat 4) (add-note track 36 (+ start beat) 1/4 108))
      (dolist (beat '(1 3)) (add-note track 38 (+ start beat) 1/4 100))
      (dotimes (step 8)
        (add-note track 42 (+ start (/ step 2)) 1/4
                  (if (evenp step) 76 58)))))
  (values))

(defun draw-voice (session pitch caption)
  "Draw sixteen steps, splitting into two lines on narrow windows."
  (declare (values))
  (let ((columns (if (< (lui:frame-width) (lui:resolve-units (lui:units 85))) 8 16)))
    (lui:label caption)
    (dotimes (part (/ 16 columns))
      (lui:row (:id (list pitch part) :width (lui:grow) :gap 2)
        (dotimes (column columns)
          (let* ((step (+ (* part columns) column))
                 (beat (+ (* 4 (session-page session)) (/ step 4)))
                 (note (hit-at (current-track session) pitch beat))
                 (active (and (playing-p session)
                              (<= beat (session-playhead session) (+ beat 1/4)))))
            (when (lui:button (if note "●" "·") :id (list :drum pitch step)
                              :width (lui:grow) :font-size 12
                              :accessible-name
                              (format nil "~A step ~D: ~A" caption (1+ step)
                                      (if note "on" "off"))
                              :background (cond (active "#b28d44")
                                                (note "#286752")
                                                ((zerop (mod step 4)) "#485767")
                                                (t "#29313d"))
                              :disabled-p (not (editable-p session)))
              (toggle-step session pitch step)))))))
  (values))

(defun draw (session)
  "Edit one bar of kick, snare and closed/open hi-hats in sixteenth-note steps."
  (declare (values))
  (lui:row (:gap (lui:units 0.5f0) :cross-align :center)
    (when (lui:button "<" :disabled-p (zerop (session-page session)))
      (decf (session-page session)))
    (lui:label (format nil "Drums / Bar ~D" (1+ (session-page session))))
    (when (lui:button ">" :disabled-p
                      (>= (* 4 (1+ (session-page session)))
                          (song-beats (session-song session))))
      (incf (session-page session))))
  (lui:row (:gap (lui:units 0.5f0))
    (when (lui:button "Basic beat" :id :basic-beat
                      :disabled-p (not (editable-p session)))
      (basic-beat session))
    (when (lui:button "Clear bar" :disabled-p (not (editable-p session)))
      (clear-bar session)))
  (lui:label "16 steps per bar. Bright columns mark each beat." :width (lui:grow))
  (loop :for pitch :in '(36 38 42 46)
        :for caption :in '("Kick" "Snare" "Closed hi-hat" "Open hi-hat")
        :do (lui:with-key pitch (draw-voice session pitch caption)))
  (values))
