(defpackage #:%lui.example.daw-state
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
    #:song #:note #:track #:make-song #:make-track #:make-note #:demo-song
    #:clone-song #:clone-track #:clone-note #:song-tracks #:song-beats
    #:track-notes #:note-start #:note-duration #:note-pitch #:note-velocity
    #:add-note #:remove-note)
  (:export #:session #:make-session #:session-song #:session-track
    #:session-selected #:session-selection #:session-page #:session-octave
    #:session-duration #:session-velocity #:session-path #:session-port
    #:session-status #:session-player #:session-midi #:session-recorder
    #:session-started #:session-last-time #:session-scratch #:session-playhead
    #:session-play-start #:session-play-end #:session-play-loop-p
    #:session-cycle-p #:session-cycle-start #:session-cycle-end
    #:session-metronome-p #:session-snap #:session-view-bars #:session-tool
    #:session-undo #:session-redo #:session-dirty-p #:session-gesture
    #:session-pending #:session-pending-path #:session-close-after-save-p
    #:session-file-input #:session-effects-p #:session-editor-p #:session-pending-track
    #:session-devices #:session-device-index
    #:gesture #:make-gesture #:gesture-kind #:gesture-beat #:gesture-pitch
    #:gesture-end-beat #:gesture-end-pitch #:gesture-originals
    #:gesture-snapshot #:gesture-notes #:gesture-changed-p
    #:gesture-frame-width #:gesture-frame-height
    #:current-track #:recording-p #:playing-p #:editable-p #:checkpoint
    #:undo-edit #:redo-edit #:select-notes #:clear-selection #:delete-selected
    #:copy-selected #:paste-notes #:duplicate-selected #:quantize-selected
    #:move-selected #:set-note-property #:change-bars #:select-track
    #:reset-session-song #:snap-beat #:commit-gesture #:cancel-gesture
    #:edit-note #:push-history))
(in-package #:%lui.example.daw-state)

(defstruct gesture
  (kind :move :type (member :move :resize :marquee :draw))
  (beat 0 :type real)
  (pitch 60 :type integer)
  (end-beat 0 :type real)
  (end-pitch 60 :type integer)
  (frame-width 0 :type real)
  (frame-height 0 :type real)
  (originals (make-array 0 :element-type 'note) :type (vector note))
  (notes (make-array 0 :element-type 'note) :type (vector note))
  (snapshot (make-song) :type song)
  (changed-p nil :type boolean))

(defstruct session
  (song (demo-song) :type song)
  (track 0 :type fixnum)
  (selected nil :type (or null note))
  (selection (make-array 0 :element-type 'note) :type (vector note))
  (clipboard (make-array 0 :element-type 'note) :type (vector note))
  (page 0 :type fixnum)
  (octave 3 :type (integer -1 8))
  (view-bars 2 :type (member 1 2 4))
  (snap 1/4 :type real)
  (tool :draw :type (member :draw :select :erase))
  (duration 1/2 :type real)
  (velocity 100 :type (integer 1 127))
  (path "" :type string)
  (file-input "build/daw-project" :type string)
  (port "0" :type string)
  (devices (make-array 0 :element-type 'string :initial-element "")
           :type (vector string))
  (device-index 0 :type fixnum)
  (status "Draw notes; drag to move; drag the right edge to resize." :type string)
  (player nil :type (or null %lui.example.daw-audio:player))
  (midi nil :type (or null %lui.example.daw-midi:input))
  (recorder nil :type (or null %lui.example.daw-model:recorder))
  (started 0 :type integer)
  (last-time 0 :type real)
  (scratch nil :type (or null pathname))
  (playhead 0 :type real)
  (play-start 0 :type real)
  (play-end 16 :type real)
  (play-loop-p nil :type boolean)
  (cycle-p nil :type boolean)
  (cycle-start 0 :type real)
  (cycle-end 8 :type real)
  (metronome-p nil :type boolean)
  (effects-p nil :type boolean)
  (editor-p t :type boolean)
  (pending-track nil :type (or null track))
  (undo (make-array 0 :element-type 'song :adjustable t :fill-pointer 0)
        :type (vector song))
  (redo (make-array 0 :element-type 'song :adjustable t :fill-pointer 0)
        :type (vector song))
  (dirty-p nil :type boolean)
  (gesture nil :type (or null gesture))
  (pending-path nil :type (or null pathname))
  (close-after-save-p nil :type boolean)
  (pending nil :type (member nil :new :load :save :save-as :wav :mp3 :close :remove-track)))

(defun current-track (session)
  "Return the track selected for editing and recording."
  (aref (song-tracks (session-song session)) (session-track session)))

(defun recording-p (session)
  "Return whether a native MIDI input is open."
  (not (null (session-midi session))))

(defun playing-p (session)
  "Return whether this window owns an active audio player."
  (not (null (session-player session))))

(defun editable-p (session)
  "Prevent edits during takes or confirmation dialogs."
  (not (or (recording-p session) (session-pending session))))

(defun push-history (snapshot history)
  "Keep the latest 64 independent undo snapshots."
  (declare (values))
  (when (= 64 (length history))
    (replace history history :start2 1)
    (decf (fill-pointer history)))
  (vector-push-extend snapshot history)
  (values))

(defun checkpoint (session)
  "Begin a discrete edit, invalidate redo and mark the project unsaved."
  (declare (values))
  (push-history (clone-song (session-song session)) (session-undo session))
  (setf (fill-pointer (session-redo session)) 0
        (session-dirty-p session) t)
  (values))

(defun select-notes (session notes)
  "Set the selection and its primary note together."
  (declare (values))
  (setf (session-selection session) notes
        (session-selected session) (when (plusp (length notes)) (aref notes 0)))
  (values))

(defun clear-selection (session)
  "Discard note references after a track or snapshot change."
  (declare (values))
  (select-notes session (make-array 0 :element-type 'note))
  (setf (session-gesture session) nil)
  (values))

(defun restore-history (session source destination)
  "Restore a snapshot while clamping view and transport state to its bounds."
  (declare (values))
  (when (and (editable-p session) (not (playing-p session))
             (plusp (length source)))
    (push-history (clone-song (session-song session)) destination)
    (setf (session-song session) (vector-pop source)
          (session-track session)
          (min (session-track session)
               (1- (length (song-tracks (session-song session)))))
          (session-page session)
          (min (session-page session) (1- (/ (song-beats (session-song session)) 4)))
          (session-playhead session) 0
          (session-cycle-start session) 0
          (session-cycle-end session) (min 8 (song-beats (session-song session)))
          (session-dirty-p session) t)
    (clear-selection session))
  (values))

(defun undo-edit (session)
  "Undo one edit or one completed pointer gesture."
  (declare (values))
  (restore-history session (session-undo session) (session-redo session))
  (values))

(defun redo-edit (session)
  "Redo the last undone edit."
  (declare (values))
  (restore-history session (session-redo session) (session-undo session))
  (values))

(defun select-track (session index)
  "Choose a track and reveal its first note's octave."
  (declare (values))
  (unless (recording-p session)
    (setf (session-track session) index)
    (clear-selection session)
    (let ((notes (track-notes (current-track session))))
      (when (plusp (length notes))
        (setf (session-octave session)
              (max -1 (min 8 (- (floor (note-pitch (aref notes 0)) 12) 2)))))))
  (values))

(defun snap-beat (session beat)
  "Round a beat coordinate to the chosen grid division."
  (* (session-snap session) (round beat (session-snap session))))

(defun delete-selected (session)
  "Delete all selected notes as one undoable edit."
  (declare (values))
  (when (and (editable-p session) (plusp (length (session-selection session))))
    (checkpoint session)
    (loop :for note :across (session-selection session)
          :do (remove-note (current-track session) note))
    (clear-selection session))
  (values))

(defun copy-selected (session)
  "Copy note values with relative offsets, independent of model identities."
  (declare (values))
  (let ((notes (session-selection session)))
    (when (plusp (length notes))
      (let ((start (reduce #'min notes :key #'note-start)))
        (setf (session-clipboard session) (map '(vector note) #'clone-note notes))
        (loop :for note :across (session-clipboard session)
              :do (decf (note-start note) start)))))
  (values))

(defun paste-notes (session &optional (at (session-playhead session)))
  "Paste at the playhead, preserving timing and clipping to the song end."
  (declare (values))
  (let* ((end (song-beats (session-song session)))
         (start (max 0 (snap-beat session at)))
         (source (session-clipboard session))
         (notes (make-array 0 :element-type 'note :adjustable t :fill-pointer 0)))
    (when (and (editable-p session) (< start end) (plusp (length source)))
      (checkpoint session)
      (loop :for note :across source
            :for onset := (+ start (note-start note))
            :when (< onset end)
              :do (vector-push-extend
                   (add-note (current-track session) (note-pitch note) onset
                             (min (note-duration note) (- end onset))
                             (note-velocity note)) notes))
      (select-notes session notes)))
  (values))

(defun duplicate-selected (session)
  "Copy the selection immediately after its last note."
  (declare (values))
  (when (plusp (length (session-selection session)))
    (let ((end (loop :for note :across (session-selection session)
                     :maximize (+ (note-start note) (note-duration note)))))
      (copy-selected session)
      (paste-notes session end)))
  (values))

(defun quantize-selected (session)
  "Snap selected note starts and lengths while keeping them inside the song."
  (declare (values))
  (when (and (editable-p session) (plusp (length (session-selection session))))
    (checkpoint session)
    (loop :for note :across (session-selection session)
          :for end := (song-beats (session-song session))
          :do (setf (note-start note)
                    (max 0 (min (- end (session-snap session))
                                (snap-beat session (note-start note))))
                    (note-duration note)
                    (min (- end (note-start note))
                         (max (session-snap session)
                              (snap-beat session (note-duration note)))))))
  (values))

(defun move-selected (session beats semitones)
  "Nudge a selection together, preserving intervals at pitch and song edges."
  (declare (values))
  (let ((notes (session-selection session)))
    (when (and (editable-p session) (plusp (length notes)))
      (let ((delta (max (- (reduce #'min notes :key #'note-start))
                       (min beats (- (song-beats (session-song session))
                                     (loop :for note :across notes :maximize
                                           (+ (note-start note)
                                              (note-duration note)))))))
            (pitch (max (- (reduce #'min notes :key #'note-pitch))
                       (min semitones (- 127 (reduce #'max notes
                                                    :key #'note-pitch))))))
        (when (or (/= delta 0) (/= pitch 0))
          (checkpoint session)
          (loop :for note :across notes
                :do (incf (note-start note) delta)
                    (incf (note-pitch note) pitch))))))
  (values))

(defun set-note-property (session property value)
  "Set a selected note property, recording only actual changes."
  (declare (values))
  (let ((note (session-selected session)))
    (when (and note (editable-p session))
      (let ((old (ecase property
                   (:start (note-start note)) (:duration (note-duration note))
                   (:pitch (note-pitch note)) (:velocity (note-velocity note)))))
        (unless (= old value)
          (checkpoint session)
          (ecase property
            (:start (setf (note-start note) value))
            (:duration (setf (note-duration note) value))
            (:pitch (setf (note-pitch note) value))
            (:velocity (setf (note-velocity note) value)))
          (setf (note-duration note)
                (min (note-duration note)
                     (- (song-beats (session-song session)) (note-start note))))))))
  (values))

(defun change-bars (session bars)
  "Resize the project; refuse to truncate notes when reducing its length."
  (declare (values))
  (let ((end (* 4 bars)))
    (when (and (editable-p session) (not (playing-p session))
               (/= end (song-beats (session-song session))))
      (if (loop :for track :across (song-tracks (session-song session))
                :thereis (some (lambda (note)
                                 (> (+ (note-start note) (note-duration note)) end))
                               (track-notes track)))
          (setf (session-status session) "Move or delete later notes first.")
          ;; else
          (progn
            (checkpoint session)
            (setf (song-beats (session-song session)) end
                  (session-page session) (min (session-page session) (1- bars))
                  (session-cycle-start session) 0
                  (session-cycle-end session) (min 8 end)
                  (session-playhead session) (min (session-playhead session) end))))))
  (values))

(defun reset-session-song (session song)
  "Install a newly created or loaded song and discard history and old identities."
  (declare (values))
  (setf (session-song session) song (session-track session) 0
        (session-page session) 0 (session-playhead session) 0
        (session-cycle-start session) 0 (session-cycle-end session)
        (min 8 (song-beats song)) (session-dirty-p session) nil
        (fill-pointer (session-undo session)) 0
        (fill-pointer (session-redo session)) 0)
  (clear-selection session)
  (values))

(defun edit-note (session pitch beat)
  "Insert and select one note as a discrete undoable edit."
  (checkpoint session)
  (let ((note (add-note (current-track session) pitch beat
                        (min (session-duration session)
                             (- (song-beats (session-song session)) beat))
                        (session-velocity session))))
    (select-notes session (make-array 1 :element-type 'note :initial-element note))
    note))

(defun commit-gesture (session)
  "Store one undo snapshot for an entire drag, not one per frame."
  (declare (values))
  (let ((gesture (session-gesture session)))
    (when (and gesture (gesture-changed-p gesture))
      (push-history (gesture-snapshot gesture) (session-undo session))
      (setf (fill-pointer (session-redo session)) 0
            (session-dirty-p session) t))
    (setf (session-gesture session) nil))
  (values))

(defun cancel-gesture (session)
  "Cancel an interrupted pointer gesture without creating an undo entry."
  (declare (values))
  (when (session-gesture session)
    (when (gesture-changed-p (session-gesture session))
      (setf (session-song session)
            (gesture-snapshot (session-gesture session)))
      (clear-selection session))
    (setf (session-gesture session) nil))
  (values))
