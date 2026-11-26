(defpackage #:%lui.example.daw-demo
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
    #:note #:note-pitch #:note-start #:note-duration #:note-velocity
    #:track #:make-track #:track-name #:track-notes #:track-volume
    #:track-muted-p #:track-solo-p #:track-wave
    #:song #:song-tracks #:song-tempo #:song-beats #:demo-song
    #:add-note #:remove-note #:note-at #:make-recorder
    #:midi-event #:finish-recording #:render-wav #:save-song #:load-song)
  (:export #:main #:draw #:make-session #:session-song #:session-track
           #:session-selected #:session-status #:close-session
           #:start-recording #:stop-recording #:drain-midi
           #:session-midi #:session-recorder #:session-path #:export-song
           #:play-song #:session-player #:session-scratch))
(in-package #:%lui.example.daw-demo)

(defstruct session
  (song (demo-song) :type song)
  (track 0 :type fixnum)
  (selected nil :type (or null note))
  (page 0 :type fixnum)
  (octave 4 :type (integer -1 9))
  (duration 1/4 :type real)
  (velocity 100 :type (integer 1 127))
  (path "build/daw-project" :type string)
  (port "0" :type string)
  (status "Ready. Click an empty cell to add a note." :type string)
  (player nil :type (or null uiop:process-info))
  (midi nil :type (or null %lui.example.daw-midi:input))
  (recorder nil :type (or null %lui.example.daw-model:recorder))
  (started 0 :type integer)
  (last-time 0 :type real)
  (scratch nil :type (or null pathname)))

(defun current-track (session)
  "Return the selected track, which remains fixed while recording."
  (aref (song-tracks (session-song session)) (session-track session)))

(defun elapsed (session)
  "Seconds since the transport's monotonic start."
  (/ (- (get-internal-real-time) (session-started session))
     internal-time-units-per-second))

(defun output-path (session type)
  "Treat the path field as a basename and choose an explicit extension."
  (make-pathname :type type :defaults (pathname (session-path session))))

(defun scratch-path (session)
  "Allocate a private temporary WAV pathname for this window."
  (or (session-scratch session)
      (setf (session-scratch session)
            (uiop:with-temporary-file (:pathname path :keep t :type "wav")
              path))))

(defun run-action (session function)
  "Display errors from user-requested file/device operations without exiting."
  (declare (values))
  (handler-case (funcall function)
    (error (condition) (setf (session-status session)
                             (format nil "~A" condition))))
  (values))

(defun stop-player (session)
  "Terminate and reap the playback process owned by this session."
  (declare (values))
  (when (session-player session)
    (when (uiop:process-alive-p (session-player session))
      (uiop:terminate-process (session-player session)))
    (uiop:wait-process (session-player session))
    (setf (session-player session) nil))
  (values))

(defun play-song (session)
  "Render a snapshot, then play it asynchronously using ffplay."
  (declare (values))
  (stop-player session)
  (render-wav (session-song session) (scratch-path session))
  (setf (session-player session)
        (uiop:launch-program
         (list "ffplay" "-nodisp" "-autoexit" "-loglevel" "error"
               (namestring (scratch-path session)))
         :output nil :error-output nil)
        (session-started session) (get-internal-real-time)
        (session-status session) "Playing rendered mix; edits apply next Play.")
  (values))

(defun export-song (session type)
  "Export the audible mix; MP3 needs an FFmpeg build with libmp3lame."
  (declare (values))
  (let ((path (output-path session type)))
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
    (setf (session-status session) (format nil "Exported ~A" path)))
  (values))

(defun start-recording (session)
  "Open native MIDI input; tempo and track remain fixed for this take."
  (declare (values))
  (let ((port (parse-integer (session-port session))))
    (assert (<= 0 port))
    (stop-player session)
    (setf (session-midi session) (%lui.example.daw-midi:open-input port)
          (session-recorder session)
          (make-recorder :track (current-track session)
                         :tempo (song-tempo (session-song session))
                         :beats (song-beats (session-song session)))
          (session-last-time session) 0
          (session-started session) (get-internal-real-time)
          (session-status session) "Recording MIDI (no live monitoring)."))
  (values))

(defun drain-midi (session)
  "Poll native MIDI and preserve the device's inter-event timestamps."
  (declare (values))
  (%lui.example.daw-midi:poll-input
   (session-midi session) (elapsed session)
   (lambda (seconds status data1 data2)
     (setf (session-last-time session) seconds)
     (midi-event (session-recorder session) seconds status data1 data2)))
  (values))

(defun stop-recording (session)
  "Drain pending events, close held notes and free the native input."
  (declare (values))
  (when (session-midi session)
    (unwind-protect (drain-midi session)
      (%lui.example.daw-midi:close-input (session-midi session))
      (finish-recording (session-recorder session)
                        (max (session-last-time session) (elapsed session)))
      (setf (session-midi session) nil (session-recorder session) nil)))
  (values))

(defun close-session (session)
  "Release every child process and temporary audio file, also on UI errors."
  (declare (values))
  (unwind-protect (stop-recording session)
    (stop-player session)
    (when (session-scratch session)
      (uiop:delete-file-if-exists (session-scratch session))))
  (values))

(defun update-transport (session)
  "Poll MIDI without blocking drawing and schedule a modest transport refresh."
  (declare (values))
  (when (session-player session)
    (unless (uiop:process-alive-p (session-player session))
      (let ((code (uiop:wait-process (session-player session))))
        (setf (session-player session) nil
              (session-status session)
              (if (zerop code) "Playback finished."
                  "Playback failed; check ffplay and the audio output device.")))))
  (when (session-midi session)
    (handler-case
        (progn
          (drain-midi session)
          (when (>= (elapsed session)
                    (* (song-beats (session-song session))
                       (/ 60 (song-tempo (session-song session)))))
            (stop-recording session)
            (setf (session-status session) "Recording finished.")))
      (error (condition)
        (ignore-errors (stop-recording session))
        (error condition))))
  (when (or (session-player session) (session-midi session))
    (lui:request-frame 0.03))
  (values))

(defun recording-p (session)
  "Return a boolean suitable for LUI disabled options."
  (not (null (session-midi session))))

(defun playing-p (session)
  "Return whether this session owns a playback process."
  (not (null (session-player session))))

(defun transport (session)
  "Draw playback, recording and tempo controls."
  (declare (values))
  (lui:row (:gap (lui:units 1))
    (when (lui:button "Play" :disabled-p (recording-p session))
      (run-action session (lambda () (play-song session))))
    (when (lui:button "Stop")
      (run-action session (lambda () (stop-recording session)
                                    (stop-player session)
                                    (setf (session-status session) "Stopped."))))
    (when (lui:button "Record MIDI" :disabled-p
                      (recording-p session))
      (run-action session (lambda () (start-recording session))))
    (lui:label "BPM")
    (setf (song-tempo (session-song session))
          (round (lui:slider :value (song-tempo (session-song session))
                    :minimum 40 :maximum 240 :step 1
                    :width (lui:units 14)
                    :disabled-p (or (recording-p session)
                                    (playing-p session)))))
    (lui:label (format nil "~D" (song-tempo (session-song session))))
    (when (or (playing-p session) (session-midi session))
      (lui:label (format nil "Beat ~,1F"
                        (min (song-beats (session-song session))
                             (* (elapsed session)
                                (/ (song-tempo (session-song session)) 60)))))))
  (values))

(defun track-strip (session track index)
  "Draw a stable keyed track selector and independent mixer controls."
  (declare (values))
  (lui:with-key track
    (lui:row (:gap (lui:units 1))
      (when (lui:button
             (format nil "~A ~A" (if (= index (session-track session)) ">" " ")
                     (track-name track))
             :width (lui:units 15) :disabled-p (recording-p session))
        (setf (session-track session) index (session-selected session) nil)
        (when (plusp (length (track-notes track)))
          (setf (session-octave session)
                (1- (floor (note-pitch (aref (track-notes track) 0)) 12)))))
      (setf (track-muted-p track)
            (lui:checkbox "Mute" :value (track-muted-p track))
            (track-solo-p track)
            (lui:checkbox "Solo" :value (track-solo-p track))
            (track-volume track)
            (lui:slider :value (track-volume track) :minimum 0 :maximum 1
                        :step 0.05 :width (lui:units 12)))
      (when (lui:button (string-capitalize (track-wave track)))
        (setf (track-wave track)
              (ecase (track-wave track)
                (:sine :triangle) (:triangle :organ) (:organ :sine))))
      (lui:label (format nil "~D notes" (length (track-notes track))))))
  (values))

(defun mixer (session)
  "Expose multiple tracks with add/remove and per-track timbre and levels."
  (declare (values))
  (let ((tracks (song-tracks (session-song session))))
    (lui:row (:gap (lui:units 1))
      (lui:label "TRACKS")
      (when (lui:button "+ Track" :id :add-track
                        :disabled-p (or (recording-p session)
                                        (>= (length tracks) 32)))
        (vector-push-extend
         (make-track :name (format nil "Track ~D" (1+ (length tracks)))) tracks))
      (when (lui:button "Remove selected" :disabled-p
                        (or (recording-p session) (= (length tracks) 1)))
        (setf (song-tracks (session-song session))
              (delete (current-track session) tracks)
              (session-track session) 0
              (session-selected session) nil)))
    (lui:panel (:height (lui:units (if (lui:text-mode-p) 4 13)) :width (lui:grow) :scroll-p t)
      (loop :for track :across (song-tracks (session-song session))
            :for index :from 0 :do (track-strip session track index))))
  (values))

(defun pitch-name (pitch)
  "Name MIDI pitches with middle C as C4."
  (format nil "~A~D" (aref #("C" "C#" "D" "D#" "E" "F" "F#"
                              "G" "G#" "A" "A#" "B") (mod pitch 12))
          (1- (floor pitch 12))))

(defun roll-cell (session pitch beat)
  "A piano-roll cell selects a covering note or inserts one on the grid."
  (declare (values))
  (let* ((track (current-track session))
         (note (note-at track pitch beat))
         (playing (and (playing-p session)
                       (<= beat (* (elapsed session)
                                   (/ (song-tempo (session-song session)) 60)))
                       (< (* (elapsed session)
                             (/ (song-tempo (session-song session)) 60))
                          (+ beat 1/4)))))
    (when (lui:button
           (if (lui:text-mode-p)
               (cond ((and note (= beat (note-start note))) "o")
                     (note "-") (playing "|") (t "."))
               ;; else
               "")
            :id (list pitch beat)
            :width (lui:units (if (lui:text-mode-p) 4 6))
            :padding 0 :height (lui:units (if (lui:text-mode-p) 1 2.5))
            :background (cond ((and note (eq note (session-selected session)))
                               "#c78726")
                              (playing "#668894")
                              (note "#357b8c")
                              ((zerop (mod beat 1)) "#354052")
                              (t "#242d3b"))
            :foreground "#ffffff" :disabled-p (recording-p session)
            :accessible-name (format nil "~A beat ~,2F~A" (pitch-name pitch)
                                     beat (if note " note" " empty")))
      (setf (session-selected session)
            (or note (add-note track pitch beat
                               (min (session-duration session)
                                    (- (song-beats (session-song session)) beat))
                               (session-velocity session))))))
  (values))

(defun piano-roll (session)
  "Draw one bar and one octave at a time with sixteenth-note cells."
  (declare (values))
  (lui:row (:gap (lui:units 1))
    (lui:label (format nil "PIANO ROLL / ~A" (track-name (current-track session))))
    (when (lui:button "< Bar" :disabled-p (zerop (session-page session)))
      (decf (session-page session)))
    (lui:label (format nil "~D / ~D" (1+ (session-page session))
                      (ceiling (song-beats (session-song session)) 4)))
    (when (lui:button "Bar >" :disabled-p
                      (>= (* 4 (1+ (session-page session)))
                          (song-beats (session-song session))))
      (incf (session-page session)))
    (when (lui:button "Oct -" :disabled-p (= -1 (session-octave session)))
      (decf (session-octave session)))
    (when (lui:button "Oct +" :disabled-p (= 9 (session-octave session)))
      (incf (session-octave session))))
  (lui:panel (:width (lui:grow) :height (lui:units (if (lui:text-mode-p) 14 34))
              :scroll-p t :gap 0)
    (lui:row (:gap 0)
      (lui:label "Beat" :width (lui:units 5))
      (dotimes (step 16)
        (lui:label (if (zerop (mod step 4))
                       (write-to-string (1+ (+ (* 4 (session-page session))
                                               (/ step 4)))) " ")
                   :id step :width (lui:units (if (lui:text-mode-p) 4 6)))))
    (dotimes (row 12)
      (let ((pitch (+ (* (1+ (session-octave session)) 12) (- 11 row))))
        (when (<= pitch 127)
          (lui:row (:id pitch :gap 0)
            (lui:label (pitch-name pitch) :width (lui:units 5)
                       :height (lui:units (if (lui:text-mode-p) 1 2.5)))
            (dotimes (step 16)
              (let ((beat (+ (* 4 (session-page session)) (/ step 4))))
                (when (< beat (song-beats (session-song session)))
                  (roll-cell session pitch beat)))))))))
  (values))

(defun note-editor (session)
  "Edit selected note position, length, velocity and pitch, or insertion defaults."
  (declare (values))
  (let ((note (session-selected session)))
    (lui:row (:gap (lui:units 1))
      (lui:label (if note "Selected note" "New note"))
      (lui:label "Length (beats)")
      (let ((duration (lui:slider :value (if note (note-duration note)
                                            (session-duration session))
                                 :minimum 1/4
                                 :maximum (if note
                                              (song-beats (session-song session))
                                              4)
                                 :step 1/4
                                 :width (lui:units 12)
                                 :disabled-p (recording-p session))))
        (setf (session-duration session) duration)
        (when note
          (setf (note-duration note)
                (min duration (- (song-beats (session-song session))
                                 (note-start note)))))
        (lui:label (format nil "~,2F" (if note (note-duration note) duration))))
      (lui:label "Velocity")
      (setf (session-velocity session)
            (round (lui:slider :value (if note (note-velocity note)
                                          (session-velocity session))
                        :minimum 1 :maximum 127 :step 1 :width (lui:units 10)
                        :disabled-p (recording-p session))))
      (when note (setf (note-velocity note) (session-velocity session)))
      (when (lui:button "Delete note" :id :delete-note
                        :disabled-p (or (null note) (recording-p session)))
        (remove-note (current-track session) note)
        (setf (session-selected session) nil)))
    (when note
      (lui:row (:gap (lui:units 1))
        (lui:label (pitch-name (note-pitch note)))
        (setf (note-pitch note)
              (round (lui:slider :value (note-pitch note) :minimum 0 :maximum 127
                          :step 1 :width (lui:units 14)
                          :disabled-p (recording-p session))))
        (lui:label "Start beat")
        (setf (note-start note)
              (lui:slider :value (note-start note) :minimum 0
                          :maximum (- (song-beats (session-song session)) 1/4)
                          :step 1/4 :width (lui:units 20)
                          :disabled-p (recording-p session))
              (note-duration note)
              (min (note-duration note) (- (song-beats (session-song session))
                                          (note-start note))))
        (lui:label (format nil "~,2F" (note-start note))))))
  (values))

(defun file-controls (session)
  "Project persistence and audio export share an explicit output basename."
  (declare (values))
  (lui:row (:gap (lui:units 1))
    (lui:label "File base")
    (setf (session-path session)
          (lui:text-field :value (session-path session) :width (lui:units 30)))
    (when (lui:button "Save project")
      (run-action session
        (lambda () (save-song (session-song session) (output-path session "lisp"))
                   (setf (session-status session) "Project saved."))))
    (when (lui:button "Load project" :disabled-p
                      (or (recording-p session) (playing-p session)))
      (run-action session
        (lambda () (setf (session-song session)
                         (load-song (output-path session "lisp"))
                         (session-track session) 0 (session-page session) 0
                         (session-selected session) nil
                         (session-status session) "Project loaded.")))))
  (lui:row (:gap (lui:units 1))
    (dolist (type '("wav" "mp3"))
      (when (lui:button (format nil "Export ~A" (string-upcase type)) :id type
                        :disabled-p (or (recording-p session)
                                        (playing-p session)))
        (run-action session (lambda () (export-song session type)))))
    (lui:label "Save/export replace files at this basename."))
  (values))

(defun midi-controls (session)
  "List actual device ports and select the input index used by Record MIDI."
  (declare (values))
  (lui:row (:gap (lui:units 1))
    (lui:label "MIDI port")
    (setf (session-port session)
          (lui:text-field :value (session-port session) :width (lui:units 5)
                          :disabled-p (recording-p session)))
    (when (lui:button "List inputs" :disabled-p (recording-p session))
      (run-action session
        (lambda ()
          (let ((names (%lui.example.daw-midi:list-inputs)))
            (setf (session-status session)
                  (if (zerop (length names)) "No MIDI input devices found."
                      (format nil "~{~A~^; ~}"
                              (loop :for name :across names :for index :from 0
                                    :collect (format nil "~D: ~A" index
                                                     name)))))))))
    (lui:label "Native MIDI / RtMidi. Records selected track."))
  (values))

(defun draw (session)
  "Draw the native DAW using only LUI's public application API."
  (declare (values))
  (run-action session (lambda () (update-transport session)))
  (lui:with-toolkit (:qt)
    (lui:with-palette (:dark)
      (lui:panel (:width (lui:grow) :height (lui:grow) :scroll-p t
                  :padding (lui:units 1) :gap (lui:units 0.5))
        (lui:label "LUI / POCKET STUDIO")
        (transport session)
        (mixer session)
        (piano-roll session)
        (note-editor session)
        (midi-controls session)
        (file-controls session)
        (lui:label (session-status session) :width (lui:grow))
        (lui:label
         "Click to add/select; use sliders to move/resize. Four bars, 4/4."))))
  (when (or (playing-p session) (recording-p session))
    (lui:request-frame 0.03))
  (values))

(defun main (&key (interactive t))
  "Run with make daw-demo; FFmpeg/ffplay provide export and snapshot playback.
MIDI input uses Common Lisp CFFI bindings to the RtMidi shared library.
Recording quantizes to sixteenths and stops at the end of the four-bar song.
There is no live monitoring, audio recording, undo, plug-ins or browser audio."
  (let ((session (make-session)))
    (unwind-protect
         (lui:run (lambda () (draw session)) :title "LUI Pocket Studio"
                  :interactive interactive :max-fps 30
                  :width (unless (eq lui:*backend* :terminal) 1000)
                  :height (unless (eq lui:*backend* :terminal) 800))
      (close-session session))))
