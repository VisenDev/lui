(defpackage #:%lui.example.daw-demo
  (:use #:cl)
  (:import-from #:%lui.example.daw-state #:session #:make-session #:session-song #:session-track
    #:session-selected #:session-selection #:session-page #:session-octave
    #:session-duration #:session-velocity #:session-path #:session-port
    #:session-status #:session-player #:session-midi #:session-recorder
    #:session-started #:session-last-time #:session-scratch #:session-playhead
    #:session-play-start #:session-play-end #:session-play-loop-p
    #:session-cycle-p #:session-cycle-start #:session-cycle-end
    #:session-metronome-p #:session-snap #:session-view-bars #:session-tool
    #:session-undo #:session-redo #:session-dirty-p #:session-gesture
    #:session-pending #:session-pending-path #:session-close-after-save-p
    #:session-file-input
    #:session-devices #:session-device-index
    #:gesture #:make-gesture #:gesture-kind #:gesture-beat #:gesture-pitch
    #:gesture-end-beat #:gesture-end-pitch #:gesture-originals
    #:gesture-snapshot #:gesture-notes #:gesture-changed-p
    #:current-track #:recording-p #:playing-p #:editable-p #:checkpoint
    #:undo-edit #:redo-edit #:select-notes #:clear-selection #:delete-selected
    #:copy-selected #:paste-notes #:duplicate-selected #:quantize-selected
    #:move-selected #:set-note-property #:change-bars #:select-track
    #:reset-session-song #:snap-beat #:commit-gesture #:cancel-gesture
    #:edit-note #:push-history)
  (:import-from #:%lui.example.daw-model
    #:note #:song #:make-song #:make-track #:clone-track #:track-name
    #:track-notes #:track-volume #:track-muted-p #:track-solo-p #:track-wave
    #:song-tracks #:song-tempo #:song-beats #:note-start #:note-duration
    #:note-pitch #:note-velocity #:make-recorder #:midi-event
    #:finish-recording #:render-wav #:save-song #:load-song)
  (:export #:main #:draw #:make-session #:session-song #:session-track
    #:session-selected #:session-status #:close-session #:start-recording
    #:stop-recording #:drain-midi #:session-midi #:session-recorder
    #:session-path #:export-song #:play-song #:session-player #:session-scratch
    #:transport-position #:stop-player #:request-file-action
    #:request-session-close #:resolve-close #:resolve-file-confirmation))
(in-package #:%lui.example.daw-demo)

(defun elapsed (session)
  "Seconds since the transport's monotonic start."
  (/ (- (get-internal-real-time) (session-started session))
     internal-time-units-per-second))

(defun output-path (session type)
  "Choose a project/export extension without shell interpolation."
  (make-pathname :type type
                 :defaults (if (plusp (length (session-path session)))
                               (pathname (session-path session))
                               (merge-pathnames "Untitled.lisp"
                                                (user-homedir-pathname)))))

(defun scratch-path (session)
  "Allocate one private temporary WAV per window."
  (or (session-scratch session)
      (setf (session-scratch session)
            (uiop:with-temporary-file (:pathname path :keep t :type "wav") path))))

(defun run-action (session function)
  "Report file/device failures without losing the current project."
  (declare (values))
  (handler-case (funcall function)
    (error (condition)
      (setf (session-status session) (format nil "~A" condition))))
  (values))

(defun transport-position (session)
  "Estimate the playhead from the frozen render range and monotonic time."
  (if (playing-p session)
      (let* ((start (session-play-start session))
             (length (- (session-play-end session) start))
             (beats (* (elapsed session) (/ (song-tempo (session-song session)) 60))))
        (+ start (if (and (session-play-loop-p session) (plusp length))
                     (mod beats length) (min length beats))))
      ;; else
      (session-playhead session)))

(defun stop-player (session)
  "Pause at the current playhead and reap this window's playback process."
  (declare (values))
  (when (session-player session)
    (setf (session-playhead session) (transport-position session))
    (when (uiop:process-alive-p (session-player session))
      (uiop:terminate-process (session-player session)))
    (uiop:wait-process (session-player session))
    (setf (session-player session) nil))
  (values))

(defun play-song (session)
  "Play from the cursor or cycle range; optionally include metronome clicks."
  (declare (values))
  (stop-player session)
  (let* ((loop-p (and (session-cycle-p session) (not (recording-p session))))
         (end (if loop-p (session-cycle-end session)
                  (song-beats (session-song session))))
         (start (if loop-p (session-cycle-start session)
                    (session-playhead session))))
    (when (>= start end) (setf start 0))
    (render-wav (session-song session) (scratch-path session)
                :start start :end end :metronome (session-metronome-p session))
    (launch-playback session start end loop-p)
    (setf (session-status session) "Playing. Edits are heard on the next Play."))
  (values))

(defun launch-playback (session start end loop-p)
  "Launch an already rendered range and establish the shared transport clock."
  (declare (values))
  (setf (session-player session)
        (uiop:launch-program
         (append (list "ffplay" "-nodisp" "-autoexit" "-loglevel" "error")
                 (when loop-p (list "-loop" "0"))
                 (list (namestring (scratch-path session))))
         :output nil :error-output nil)
        (session-play-start session) start (session-play-end session) end
        (session-play-loop-p session) loop-p
        (session-playhead session) start
        (session-started session) (get-internal-real-time))
  (values))

(defun export-song (session type &optional (path (output-path session type)))
  "Export the full mix, excluding transport metronome and cycle settings."
  (declare (values))
  (if (string= type "wav")
      (render-wav (session-song session) path)
      ;; else
      (progn
        (render-wav (session-song session) (scratch-path session))
        (ensure-directories-exist path)
        (uiop:run-program
         (list "ffmpeg" "-nostdin" "-v" "error" "-y" "-i"
               (namestring (scratch-path session)) "-codec:a" "libmp3lame"
               "-q:a" "2" (namestring path))
         :output nil :error-output :string)))
  (setf (session-status session) (format nil "Exported ~A" path))
  (values))

(defun start-recording (session)
  "Record an undoable take on the selected track, starting at the cursor."
  (declare (values))
  (stop-player session)
  (when (>= (session-playhead session) (song-beats (session-song session)))
    (setf (session-playhead session) 0))
  ;; Render before opening input so synthesis time cannot shift a take.
  (render-wav (session-song session) (scratch-path session)
              :start (session-playhead session)
              :metronome (session-metronome-p session))
  (let ((input (%lui.example.daw-midi:open-input
                (parse-integer (session-port session)))))
    (checkpoint session)
    (setf (session-midi session) input
          (session-recorder session)
          (make-recorder :track (current-track session)
                         :tempo (song-tempo (session-song session))
                         :offset (session-playhead session)
                         :beats (song-beats (session-song session)))
          (session-last-time session) 0
          (session-play-start session) (session-playhead session)
          (session-started session) (get-internal-real-time)
          (session-status session) "Recording over backing mix; new notes are not monitored.")
    (handler-case
        (launch-playback session (session-playhead session)
                         (song-beats (session-song session)) nil)
      (error (condition)
        (stop-recording session)
        (error condition))))
  (values))

(defun drain-midi (session)
  "Poll the native MIDI queue; no external interpreter or foreign-thread Lisp."
  (declare (values))
  (%lui.example.daw-midi:poll-input
   (session-midi session) (elapsed session)
   (lambda (seconds status data1 data2)
     (setf (session-last-time session) seconds)
     (midi-event (session-recorder session) seconds status data1 data2)))
  (values))

(defun stop-recording (session)
  "Flush pending MIDI, close held notes, and always free the native input."
  (declare (values))
  (when (session-midi session)
    (unwind-protect (drain-midi session)
      (%lui.example.daw-midi:close-input (session-midi session))
      (finish-recording (session-recorder session)
                        (max (session-last-time session) (elapsed session)))
      (setf (session-midi session) nil (session-recorder session) nil)
      (stop-player session)))
  (values))

(defun close-session (session)
  "Release input, playback and temporary audio even when the window errors."
  (declare (values))
  (unwind-protect (stop-recording session)
    (stop-player session)
    (when (session-scratch session)
      (uiop:delete-file-if-exists (session-scratch session))))
  (values))

(defun update-transport (session)
  "Update a visible playhead, poll MIDI, and handle natural completion."
  (declare (values))
  (when (playing-p session)
    (setf (session-playhead session) (transport-position session))
    (unless (uiop:process-alive-p (session-player session))
      (let ((code (uiop:wait-process (session-player session))))
        (setf (session-player session) nil
              (session-status session)
              (if (zerop code) "Playback finished."
                  "Playback failed; check ffplay and the audio output device.")))))
  (when (recording-p session)
    (handler-case
        (progn
          (drain-midi session)
          (setf (session-playhead session)
                (min (song-beats (session-song session))
                     (+ (session-play-start session)
                        (* (elapsed session)
                           (/ (song-tempo (session-song session)) 60)))))
          (when (>= (session-playhead session) (song-beats (session-song session)))
            (stop-recording session)
            (setf (session-status session) "Recording finished.")))
      (error (condition)
        (ignore-errors (stop-recording session))
        (error condition))))
  (values))

(defun toggle-play (session)
  "Space and the transport button share pause/resume behavior."
  (declare (values))
  (unless (recording-p session)
    (run-action session
      (lambda () (if (playing-p session) (stop-player session)
                     (play-song session)))))
  (values))

(defun paint-toolbar (renderer node)
  "Leave toolbar groups unframed while preserving normal container layout."
  (declare (ignore renderer node) (values))
  (values))

(defmacro responsive-bar ((minimum) &body body)
  "Stack a stable group below MINIMUM text units without changing identities."
  `(let ((stacked (< (lui:frame-width)
                     (lui:resolve-units (lui:units ,minimum)))))
     (lui:panel (:direction (if stacked :column :row)
                            :width (lui:grow) :padding 0 :gap (lui:units 0.5)
                            :cross-align (if stacked :start :center)
                            :painter #'paint-toolbar)
       ,@body)))

(defun transport (session)
  "Expose pause/resume, stop, rewind, tempo, cycle and metronome together."
  (declare (values))
  (let ((busy (or (recording-p session) (playing-p session))))
    (responsive-bar (140)
      (responsive-bar (70)
        (lui:label "POCKET STUDIO" :font-weight :bold)
        (when (lui:button "|<" :accessible-name "Return to start"
                          :disabled-p (recording-p session))
          (stop-player session) (setf (session-playhead session) 0))
        (when (lui:button (if (playing-p session) "Pause" "Play")
                          :id :play :disabled-p (recording-p session))
          (toggle-play session))
        (when (lui:button "Stop" :id :stop)
          (run-action session (lambda () (stop-recording session)
                                (stop-player session)
                                (setf (session-status session) "Stopped."))))
        (when (lui:button "Record MIDI" :disabled-p busy)
          (run-action session (lambda () (start-recording session)))))
      (responsive-bar (70)
        (lui:label (format nil "Bar ~D / Beat ~,2F"
                           (1+ (floor (session-playhead session) 4))
                           (1+ (mod (session-playhead session) 4))))
        (lui:label "BPM")
        (let* ((old (song-tempo (session-song session)))
               (value (round (lui:slider :value old :minimum 40 :maximum 240
                                         :step 1 :width (lui:units 10) :disabled-p busy))))
          (unless (= old value) (checkpoint session)
                  (setf (song-tempo (session-song session)) value))
          (lui:label (write-to-string value)))
        (setf (session-cycle-p session)
              (lui:checkbox "Cycle" :value (session-cycle-p session) :disabled-p busy)
              (session-metronome-p session)
              (lui:checkbox "Click" :value (session-metronome-p session)
                            :disabled-p busy)))))
  (values))

(defun history-controls (session)
  "Expose editing history and selection commands without hidden gestures."
  (declare (values))
  (let ((disabled (not (editable-p session)))
        (empty (zerop (length (session-selection session)))))
    (responsive-bar (115)
      (responsive-bar (65)
        (when (lui:button "Undo" :id :undo :disabled-p
                          (or disabled (playing-p session)
                              (zerop (length (session-undo session)))))
          (undo-edit session))
        (when (lui:button "Redo" :id :redo :disabled-p
                          (or disabled (playing-p session)
                              (zerop (length (session-redo session)))))
          (redo-edit session))
        (when (lui:button "All" :disabled-p disabled)
          (select-notes session (copy-seq (track-notes (current-track session)))))
        (when (lui:button "Copy" :disabled-p empty) (copy-selected session))
        (when (lui:button "Paste at cursor" :disabled-p disabled) (paste-notes session)))
      (responsive-bar (65)
        (when (lui:button "Duplicate" :disabled-p (or disabled empty))
          (duplicate-selected session))
        (when (lui:button "Quantize" :disabled-p (or disabled empty))
          (quantize-selected session))
        (when (lui:button "Delete" :id :delete-note :disabled-p (or disabled empty))
          (delete-selected session))
        (lui:label (format nil "~D selected" (length (session-selection session)))))))
  (values))

(defun terminal-track-bars (session track index)
  "Keep keyboard-accessible bar buttons in terminal mode."
  (declare (values))
  (dotimes (bar (/ (song-beats (session-song session)) 4))
    (let ((count (count-if
                  (lambda (note)
                    (and (< (note-start note) (* 4 (1+ bar)))
                         (> (+ (note-start note) (note-duration note))
                            (* 4 bar))))
                  (track-notes track))))
      (when (lui:button (format nil "~D~A" (1+ bar)
                               (if (plusp count) " +" ""))
                        :id bar :width (lui:units 8)
                        :accessible-name
                        (format nil "Bar ~D, ~D notes" (1+ bar) count)
                        :background (if (plusp count) "#286752" "#29313d")
                        :disabled-p (recording-p session))
        (%lui.example.daw-roll:navigate-lane session index (* 4 bar)))))
  (values))

(defun compact-name (name)
  "Keep track captions compact; the inspector retains the complete name."
  (if (> (length name) 20)
      (concatenate 'string (subseq name 0 19) "…")
      name))

(defun track-header (session track index)
  "Group selection, mix controls and activity in a consistent track header."
  (declare (values))
  (lui:column (:id :track-header :width (lui:units 26)
               :padding 4 :gap 4)
    (when (lui:button (compact-name (track-name track)) :id :select-track
                      :accessible-name (track-name track)
                      :width (lui:grow)
                      :background (if (= index (session-track session))
                                      "#36586b" "#343e4b")
                      :disabled-p (recording-p session))
      (select-track session index))
    (lui:row (:width (lui:grow) :gap (lui:units 1)
               :cross-align :center)
      (let* ((busy (or (recording-p session) (playing-p session)))
             (muted (lui:checkbox "M" :value (track-muted-p track)
                                  :accessible-name "Mute track"
                                  :disabled-p busy))
             (solo (lui:checkbox "S" :value (track-solo-p track)
                                 :accessible-name "Solo track"
                                 :disabled-p busy)))
        (unless (and (eql muted (track-muted-p track))
                     (eql solo (track-solo-p track)))
          (checkpoint session)
          (setf (track-muted-p track) muted (track-solo-p track) solo)))
      (lui:label
       (if (and (or (playing-p session) (recording-p session))
                (%lui.example.daw-roll:track-active-p session track))
           "Playing" "")
       :width (lui:units 7) :foreground "#58c49c")))
  (values))

(defun track-strip (session track index)
  "Align each grouped header with its full-song lane."
  (declare (values))
  (lui:with-key track
    (lui:row (:id :track-strip :width (lui:grow) :gap 0
               :cross-align :center)
      (track-header session track index)
      (if (lui:text-mode-p)
          (terminal-track-bars session track index)
          ;; else
          (%lui.example.daw-roll:draw-lane session track index))))
  (values))

(defun track-controls (session)
  "Rename, duplicate or remove tracks; keep the complete mix undoable."
  (declare (values))
  (let* ((track (current-track session))
         (tracks (song-tracks (session-song session)))
         (disabled (not (editable-p session))))
    (responsive-bar (125)
      (responsive-bar (65)
        (lui:label "ARRANGEMENT — full song")
        (when (lui:button "+ Track" :id :add-track
                          :disabled-p (or disabled (>= (length tracks) 32)))
          (checkpoint session)
          (vector-push-extend
           (make-track :name (format nil "Track ~D" (1+ (length tracks)))) tracks)
          (select-track session (1- (length tracks)))))
      (responsive-bar (65)
        (when (lui:button "Duplicate track" :disabled-p
                          (or disabled (>= (length tracks) 32)))
          (checkpoint session)
          (let ((copy (clone-track track)))
            (setf (track-name copy) (concatenate 'string (track-name track) " copy"))
            (vector-push-extend copy tracks)
            (select-track session (1- (length tracks)))))
        (when (lui:button "Remove track" :disabled-p
                          (or disabled (= (length tracks) 1)))
          (checkpoint session)
          (setf (song-tracks (session-song session)) (delete track tracks))
          (select-track session 0))
        (lui:label "Bars")
        (let ((bars (round (lui:slider :value (/ (song-beats (session-song session)) 4)
                                       :minimum 1 :maximum 32 :step 1 :width (lui:units 12)
                                       :disabled-p (or disabled (playing-p session))))))
          (change-bars session bars)
          (lui:label (write-to-string (/ (song-beats (session-song session)) 4))))))
    (lui:panel (:height (if (lui:text-mode-p) (lui:units 8)
                            (+ 4 (* 80 (min 4 (length tracks)))))
                        :id :track-list :width (lui:grow) :scroll-p t :padding 2 :gap 0)
      (loop :for item :across (song-tracks (session-song session))
            :for index :from 0 :do (track-strip session item index)))
    (setf track (current-track session))
    (responsive-bar (75)
      (lui:row (:gap (lui:units 0.5) :cross-align :center)
        (lui:label "Name")
        (let ((name (lui:text-field :id :track-name
                                    :value (track-name track) :width (lui:units 20)
                                    :disabled-p disabled)))
          (unless (string= name (track-name track))
            (checkpoint session) (setf (track-name track) name))))
      (lui:row (:gap (lui:units 0.5) :cross-align :center)
        (lui:label "Level")
        (let ((volume (lui:slider :value (track-volume track) :minimum 0 :maximum 1
                                  :step 0.05 :width (lui:units 14)
                                  :disabled-p disabled)))
          (unless (= volume (track-volume track))
            (checkpoint session) (setf (track-volume track) volume))))
      (when (lui:button (format nil "Sound: ~A" (string-capitalize (track-wave track)))
                        :disabled-p disabled)
        (checkpoint session)
        (setf (track-wave track) (ecase (track-wave track)
                                   (:sine :triangle) (:triangle :organ) (:organ :sine))))))
  (values))

(defun roll-toolbar (session)
  "Provide explicit tools, musical grid sizes, zoom, and view navigation."
  (declare (values))
  (responsive-bar (150)
    (responsive-bar (65)
      (lui:label (format nil "EDITOR: ~A"
                         (compact-name (track-name (current-track session))))
                 :width (lui:units 18))
      (dolist (tool '(:draw :select :erase))
        (when (lui:button (format nil "~A~A" (if (eq tool (session-tool session)) "> " "")
                                  (string-capitalize tool))
                          :id tool :disabled-p (not (editable-p session)))
          (cancel-gesture session) (setf (session-tool session) tool))))
    (responsive-bar (65)
      (when (lui:button (format nil "Grid: 1/~D" (/ 4 (session-snap session))))
        (setf (session-snap session)
              (case (session-snap session) (1 1/2) (1/2 1/4) (1/4 1/8) (t 1))))
      (when (lui:button (format nil "View: ~D bars" (session-view-bars session)))
        (setf (session-view-bars session)
              (case (session-view-bars session) (1 2) (2 4) (t 1))))
      (when (lui:button "<" :accessible-name "Previous bar"
                        :disabled-p (zerop (session-page session)))
        (decf (session-page session)))
      (lui:label (format nil "Bar ~D" (1+ (session-page session))))
      (when (lui:button ">" :accessible-name "Next bar"
                        :disabled-p (>= (* 4 (1+ (session-page session)))
                                        (song-beats (session-song session))))
        (incf (session-page session))))
    (responsive-bar (65)
      (when (lui:button "Oct -" :disabled-p (= -1 (session-octave session)))
        (decf (session-octave session)))
      (when (lui:button "Oct +" :disabled-p (= 8 (session-octave session)))
        (incf (session-octave session)))
      (when (lui:button "Loop view" :disabled-p
                        (or (playing-p session) (recording-p session)))
        (setf (session-cycle-p session) t
              (session-cycle-start session) (* 4 (session-page session))
              (session-cycle-end session)
              (min (song-beats (session-song session))
                   (+ (* 4 (session-page session)) (* 4 (session-view-bars session))))))))
  (values))

(defun note-editor (session)
  "Edit insertion defaults or the primary selection's exact properties."
  (declare (values))
  (let ((note (session-selected session))
        (disabled (not (editable-p session))))
    (responsive-bar (100)
      (responsive-bar (55)
        (lui:label (if note "NOTE" "NEW NOTE"))
        (lui:label "Length")
        (let ((duration (lui:slider :value (if note (note-duration note)
                                               (session-duration session))
                                    :minimum (if note (min (session-snap session)
                                                           (note-duration note))
                                                 (session-snap session))
                                    :maximum (if note (song-beats (session-song session)) 4)
                                    :step (session-snap session) :width (lui:units 14)
                                    :disabled-p disabled)))
          (if note (set-note-property session :duration duration)
              (setf (session-duration session) duration))
          (lui:label (format nil "~,2F beats" duration))))
      (responsive-bar (55)
        (lui:label "Velocity")
        (let ((velocity (round (lui:slider :value (if note (note-velocity note)
                                                      (session-velocity session))
                                           :minimum 1 :maximum 127 :step 1
                                           :width (lui:units 12) :disabled-p disabled))))
          (if note (set-note-property session :velocity velocity)
              (setf (session-velocity session) velocity)))
        (when note
          (lui:label (%lui.example.daw-roll:pitch-name (note-pitch note)))
          (lui:label (format nil "Start ~,2F" (note-start note)))))))
  (values))

(defun perform-file-action (session action &optional path)
  "Execute an action, committing the selected path only after successful I/O."
  (declare (values))
  (ecase action
    (:new (reset-session-song session (make-song))
          (vector-push-extend (make-track :name "Keys")
                              (song-tracks (session-song session)))
          (setf (session-path session) ""
                (session-status session) "New project."))
    (:load (let ((song (load-song path)))
             (reset-session-song session song)
             (setf (session-path session) (namestring path)
                   (session-status session) "Project loaded.")))
    ((:save :save-as)
     (let ((path (or path
                    (let ((current (pathname (session-path session))))
                      (if (pathname-type current) current
                          (output-path session "lisp"))))))
       (save-song (session-song session) path)
       (setf (session-path session) (namestring path)
             (session-dirty-p session) nil
             (session-status session) "Project saved.")))
    (:wav (export-song session "wav" path))
    (:mp3 (export-song session "mp3" path)))
  (when (and (member action '(:save :save-as))
             (session-close-after-save-p session))
    (setf (session-close-after-save-p session) nil)
    (lui:request-close))
  (values))

(defun select-file-action (session action)
  "Select an independent Open, Save As or export destination."
  (let* ((type (case action (:wav "wav") (:mp3 "mp3") (t "lisp")))
         (title (ecase action (:load "Open project")
                  (:save-as "Save project as") (:wav "Export WAV")
                  (:mp3 "Export MP3"))))
    (if (eq lui:*backend* :terminal)
        (make-pathname :type type
                       :defaults (pathname (session-file-input session)))
        ;; else
        (%lui.example.daw-files:choose-file
         (eq action :load) title (output-path session type) type))))

(defun prepare-file-action (session action)
  "Choose a path and defer destructive changes until explicitly confirmed."
  (declare (values))
  (let ((path (unless (eq action :new) (select-file-action session action))))
    (cond
      ((and (not (eq action :new)) (null path))
       (setf (session-close-after-save-p session) nil))
      ((if (member action '(:new :load))
           (session-dirty-p session)
           (probe-file path))
       (setf (session-pending session) action
             (session-pending-path session) path))
      (t (perform-file-action session action path))))
  (values))

(defun request-file-action (session action)
  "Save an established project directly; choose paths for all other I/O."
  (declare (values))
  (run-action session
    (lambda ()
      (if (and (eq action :save) (plusp (length (session-path session))))
          (perform-file-action session :save)
          ;; else
          (prepare-file-action session (if (eq action :save) :save-as action)))))
  (values))

(defun resolve-file-confirmation (session answer)
  "Apply or cancel a selected file operation without losing its destination."
  (declare (values))
  (let ((action (session-pending session))
        (path (session-pending-path session)))
    (setf (session-pending session) nil (session-pending-path session) nil)
    (if (eq answer :confirm)
        (run-action session
          (lambda () (perform-file-action session action path)))
        ;; else
        (setf (session-close-after-save-p session) nil)))
  (when (session-close-after-save-p session)
    (setf (session-close-after-save-p session) nil
          (session-pending session) :close))
  (values))

(defun request-session-close (session)
  "Stop transport and veto closing while unsaved changes need a decision."
  (cancel-gesture session)
  (run-action session
    (lambda ()
      (unwind-protect
           (when (recording-p session) (stop-recording session))
        (stop-player session))))
  (if (session-dirty-p session)
      (progn (setf (session-pending session) :close) nil)
      t))

(defun resolve-close (session answer)
  "Keep the project open on cancellation or save failure; close after success."
  (declare (values))
  (case answer
    (:cancel (setf (session-pending session) nil
                   (session-close-after-save-p session) nil))
    (:alternate
     (setf (session-dirty-p session) nil (session-pending session) nil
           (session-close-after-save-p session) nil)
     (lui:request-close))
    (:confirm
     (setf (session-pending session) nil
           (session-close-after-save-p session) t)
     (request-file-action session :save)
     (when (and (session-close-after-save-p session)
                (null (session-pending session)))
       (setf (session-pending session) :close))))
  (values))

(defun close-confirmation (session)
  "Offer Save, Discard and Cancel without losing edits after a failed save."
  (declare (values))
  (let ((answer (lui:confirm
                 (format nil "Save changes before closing?~%~A~%~A"
                         (output-path session "lisp") (session-status session))
                 :title "Unsaved project" :confirm-label "Save"
                 :alternate-label "Discard" :cancel-label "Cancel")))
    (when answer (resolve-close session answer)))
  (values))

(defun file-controls (session)
  "Show project location, unsaved state, and explicit save/export actions."
  (declare (values))
  (lui:column (:width (lui:grow) :gap (lui:units 0.5))
    (lui:label (if (session-dirty-p session) "UNSAVED" "PROJECT"))
    (lui:label (if (plusp (length (session-path session)))
                   (session-path session) "Untitled project")
               :width (lui:grow))
    (when (eq lui:*backend* :terminal)
      (setf (session-file-input session)
            (lui:text-field :id :file-destination
                            :value (session-file-input session)
                            :width (lui:units 30))))
    (responsive-bar (95)
      (dolist (action '(:new :load :save :save-as :wav :mp3))
        (when (lui:button (ecase action (:new "New") (:load "Open…")
                                 (:save "Save") (:save-as "Save As…")
                                 (:wav "Export WAV…") (:mp3 "Export MP3…"))
                          :id action :disabled-p
                          (or (playing-p session) (recording-p session)))
          (request-file-action session action)))))
  (when (and (session-pending session)
             (not (eq (session-pending session) :close)))
    (let ((result (lui:confirm
                   (if (member (session-pending session) '(:new :load))
                       "Discard unsaved changes to this project?"
                       (format nil "Replace the existing file?~%~A"
                               (session-pending-path session)))
                   :confirm-label "Continue" :cancel-label "Cancel")))
      (when result
        (resolve-file-confirmation session result))))
  (values))

(defun midi-controls (session)
  "List native input devices by name and select one without guessing indices."
  (declare (values))
  (responsive-bar (140)
    (responsive-bar (65)
      (lui:label "MIDI")
      (when (lui:button "Refresh devices" :disabled-p (recording-p session))
        (run-action session
                    (lambda ()
                      (setf (session-devices session) (%lui.example.daw-midi:list-inputs)
                            (session-device-index session) 0 (session-port session) "0")
                      (when (zerop (length (session-devices session)))
                        (setf (session-status session) "No MIDI input devices found."))))))
    (responsive-bar (65)
      (let ((devices (session-devices session)))
        (if (plusp (length devices))
            (when (lui:button (format nil "~D/~D ~A" (1+ (session-device-index session))
                                      (length devices)
                                      (aref devices (session-device-index session)))
                              :width (lui:grow) :disabled-p (recording-p session))
              (setf (session-device-index session)
                    (mod (1+ (session-device-index session)) (length devices))
                    (session-port session) (write-to-string (session-device-index session))))
            ;; else
            (setf (session-port session)
                  (lui:text-field :value (session-port session) :width (lui:units 4)
                                  :disabled-p (recording-p session)))))
      ))
  (lui:label "Record selected track from cursor. Native RtMidi; no live monitoring."
             :width (lui:grow))
  (values))

(defun save-shortcut-p (session)
  "Remember Save before fields consume input; perform it after model updates."
  (and (not (or (session-pending session) (playing-p session)
                (recording-p session)))
       (loop :for event :across (lui:events-for (lui:focused-widget))
             :thereis (lui:event-shortcut-p event lui.key:s :primary t))))

(defun draw (session)
  "Draw an arrangement overview and direct-manipulation piano-roll editor."
  (declare (values))
  (let ((save-p (save-shortcut-p session)))
    (run-action session (lambda () (update-transport session)))
    (lui:with-toolkit (:qt)
      (lui:with-palette (:dark)
        (lui:panel (:id :daw-page :width (lui:grow) :height (lui:grow) :scroll-p t
                    :padding (lui:units 1) :gap (lui:units 0.5))
          (transport session)
          (track-controls session)
          (lui:label "Click any track lane to select a track and time. Gold line: playhead." :width (lui:grow))
          (history-controls session)
          (roll-toolbar session)
          (when (%lui.example.daw-roll:draw session) (toggle-play session))
          (note-editor session)
          (lui:label
           "Draw: click empty space. Drag notes to move; right edge to resize; right-click deletes." :width (lui:grow))
          (lui:label
           "Roll: Space, Delete, arrows, Q. Ctrl/Cmd+A/C/V/D; Z undo, Shift+Z redo." :width (lui:grow))
          (lui:label "Project: Ctrl/Cmd+S saves. Closing asks about unsaved changes." :width (lui:grow))
          (midi-controls session)
          (file-controls session)
          (lui:label (session-status session) :width (lui:grow)))))
    (when save-p
      (request-file-action session :save)
      (lui:request-frame)))
  (when (eq (session-pending session) :close)
    (close-confirmation session))
  (when (plusp (length (lui:activated-ids))) (lui:request-frame))
  (when (or (playing-p session) (recording-p session)) (lui:request-frame 0.03))
  (values))

(defun main (&key (interactive t))
  "Run with make daw-demo. Native Lisp MIDI uses RtMidi; audio uses ffplay.
The editor supports drag/marquee/resize, right-click deletion, undo/redo,
quantization, track duplication, variable song lengths and cycle playback.
Audio is rendered on Play; the playhead is approximate, not sample synchronized.
Recording plays the backing mix and optional click, without live monitoring."
  (let ((session (make-session)))
    (unwind-protect
         (lui:run (lambda () (draw session)) :title "LUI Pocket Studio"
                  :interactive interactive :max-fps 30
                  :on-close (lambda () (request-session-close session))
                  :width (unless (eq lui:*backend* :terminal) 1200)
                  :height (unless (eq lui:*backend* :terminal) 1000))
      (close-session session))))
