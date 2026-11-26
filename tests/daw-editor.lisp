(defpackage #:%lui.tests.daw-editor
  (:use #:cl)
  (:import-from #:%lui.example.daw-state
    #:make-session #:session-song #:session-selected #:session-selection
    #:session-page #:session-octave #:session-view-bars #:session-tool
    #:session-playhead #:session-cycle-p #:session-cycle-start #:session-cycle-end
    #:session-play-start #:session-play-end #:session-play-loop-p
    #:session-started #:session-undo #:session-redo #:session-dirty-p
    #:session-pending #:session-status #:session-gesture
    #:current-track #:edit-note #:delete-selected #:undo-edit #:redo-edit
    #:copy-selected #:paste-notes #:select-notes #:move-selected
    #:change-bars #:quantize-selected)
  (:import-from #:%lui.example.daw-model
    #:note #:make-note #:track-notes #:note-at #:note-start #:note-duration
    #:note-pitch #:note-velocity #:song-beats #:make-track #:make-recorder
    #:midi-event #:finish-recording #:render-wav #:make-song #:song-tracks)
  (:export #:run-tests))
(in-package #:%lui.tests.daw-editor)

(defun widget-box (context key)
  "Find a completed widget's actual bounds for coordinate-based input tests."
  (let ((box nil))
    (%lui.layout:walk-elements
     (%lui.frame:context-root context)
     (lambda (node)
       (when (equal key (lui:widget-key (%lui.layout:element-id node)))
         (setf box (%lui.layout:element-box node)))))
    (assert box)
    box))

(defun pointer-event (context session kind beat pitch &key (button :primary)
                                                           (buttons 1))
  "Create a physical pointer event, with no widget ID bypassing hit-testing."
  (let* ((box (widget-box context :piano-roll))
         (scale (/ (- (lui:box-width box) 58) (* 4 (session-view-bars session))))
         (row (/ (- (lui:box-height box) 26) 24))
         (base (min 104 (* 12 (1+ (session-octave session))))))
    (%lui.frame:make-event
     :kind kind :button button :buttons buttons
     :x (+ (lui:box-x box) 58 (* (- beat (* 4 (session-page session))) scale))
     :y (+ (lui:box-y box) 26 (* (+ (- (+ base 23) pitch) 0.5) row)))))

(defun test-pointer-editing ()
  "Exercise real LUI capture: add, right-click delete, move, resize and cancel."
  (let ((session (make-session))
        (context (%lui.tests.support:make-test-context)))
    (setf (%lui.frame:context-text-mode-p context) nil)
    (labels ((frame (&optional events)
               (lui:with-frame (context 1200 1200 :events events)
                 (%lui.example.daw-demo:draw session)))
             (pointer (kind beat pitch &optional (button :primary) (buttons 1))
               (frame (list (pointer-event context session kind beat pitch
                                           :button button :buttons buttons))))
             (at (pitch beat) (note-at (current-track session) pitch beat)))
      (frame)
      (pointer :press 2.02 61)
      (pointer :release 2.02 61 :primary 0)
      (assert (at 61 2))
      (assert (= 1 (length (session-undo session))))
      (assert (= 1/2 (note-duration (at 61 2))))
      ;; Secondary release must neither recreate nor activate the deleted note.
      (pointer :press 2.4 61 :secondary 2)
      (pointer :release 2.4 61 :secondary 0)
      (assert (null (at 61 2)))
      (undo-edit session)
      (assert (at 61 2))
      (redo-edit session)
      (assert (null (at 61 2)))
      (frame)
      ;; Move the initial C4 to D4, keeping its duration.
      (let ((depth (length (session-undo session))))
        (pointer :press 0.2 60)
        (pointer :move 1.2 62)
        (pointer :move 2.2 62)
        (pointer :release 2.2 62 :primary 0)
        (assert (null (at 60 0)))
        (assert (= 2 (note-start (at 62 2))))
        (assert (= 1 (note-duration (at 62 2))))
        (assert (= (1+ depth) (length (session-undo session)))))
      ;; Resize from the far edge, not by dragging the note body.
      (pointer :press 2.98 62)
      (pointer :move 3.98 62)
      (pointer :release 3.98 62 :primary 0)
      (assert (= 2 (note-duration (at 62 2))))
      ;; Losing button capture restores the complete pre-drag snapshot.
      (let ((depth (length (session-undo session))))
        (pointer :press 2.2 62)
        (pointer :move 3.2 63)
        (pointer :move 3.2 63 :primary 0)
        (assert (null (session-gesture session)))
        (assert (at 62 2))
        (assert (null (at 63 3)))
        (assert (= depth (length (session-undo session)))))
      ;; Marquee and keyboard deletion operate on the focused roll only.
      (setf (session-tool session) :select)
      (pointer :press 0.01 71)
      (pointer :move 7.9 48)
      (pointer :release 7.9 48 :primary 0)
      (assert (= 2 (length (session-selection session))))
      (frame (list (%lui.frame:make-event :kind :key :key lui.key:delete)))
      (assert (null (at 62 2)))
      (assert (null (at 65 4)))
      ;; Native backends deliver printable shortcuts as text events.
      (frame (list (%lui.frame:make-event :kind :text :value "z")))
      (assert (at 62 2))
      (assert (at 65 4))
      ;; A resized window invalidates the drag's previous pixel geometry.
      (setf (session-tool session) :draw)
      (pointer :press 2.2 62)
      (pointer :move 3.2 63)
      (lui:with-frame (context 1000 1000)
        (%lui.example.daw-demo:draw session))
      (assert (null (session-gesture session)))
      (assert (at 62 2))
      (assert (null (at 63 3))))))

(defun test-history-and-clipboard ()
  "Copies are independent, undo is bounded, and redo is invalidated by edits."
  (let ((session (make-session)))
    (let ((note (edit-note session 70 2)))
      (copy-selected session)
      (setf (session-playhead session) 8)
      (paste-notes session)
      (assert (= 8 (note-start (session-selected session))))
      (assert (not (eq note (session-selected session))))
      (move-selected session 0 2)
      (assert (= 70 (note-pitch note)))
      (undo-edit session)
      (assert (= 70 (note-pitch (note-at (current-track session) 70 8))))
      (undo-edit session)
      (assert (null (note-at (current-track session) 70 8)))
      (redo-edit session)
      (assert (note-at (current-track session) 70 8))
      (edit-note session 72 3)
      (assert (zerop (length (session-redo session)))))
    (dotimes (index 70) (edit-note session (mod index 128) 0))
    (assert (= 64 (length (session-undo session))))
    (assert (session-dirty-p session))))

(defun test-bounds-and-projects ()
  "Keep quantized notes in bounds and never silently truncate a shorter song."
  (let ((session (make-session)))
    (change-bars session 2)
    (assert (= 16 (song-beats (session-song session))))
    (assert (search "later notes" (session-status session)))
    (change-bars session 8)
    (assert (= 32 (song-beats (session-song session))))
    (let ((note (edit-note session 127 31.9)))
      (quantize-selected session)
      (assert (<= (+ (note-start note) (note-duration note)) 32))
      (move-selected session 10 10)
      (assert (= 127 (note-pitch note)))
      (assert (<= (+ (note-start note) (note-duration note)) 32)))
    (%lui.example.daw-demo:request-file-action session :new)
    (assert (eq :new (session-pending session)))
    (assert (= 32 (song-beats (session-song session))))
    ;; A canceled confirmation leaves the original project and its history.
    (setf (session-pending session) nil)
    (assert (plusp (length (session-undo session))))))

(defun test-record-offset ()
  "Record at a nonzero cursor and clip held notes to the project end."
  (let* ((track (make-track))
         (recorder (make-recorder :track track :tempo 120 :offset 4 :beats 8)))
    (midi-event recorder 0 #x90 60 100)
    (finish-recording recorder 10)
    (assert (= 1 (length (track-notes track))))
    (assert (= 4 (note-start (aref (track-notes track) 0))))
    (assert (= 4 (note-duration (aref (track-notes track) 0))))))

(defun pcm-values (path)
  "Decode PCM samples using the existing independent audio test helper."
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (file-position stream 44)
    (let ((samples (make-array (/ (- (file-length stream) 44) 2)
                               :element-type '(signed-byte 16))))
      (dotimes (index (length samples))
        (let ((word (+ (read-byte stream) (* 256 (read-byte stream)))))
          (setf (aref samples index) (if (> word 32767) (- word 65536) word))))
      samples)))

(defun test-render-range ()
  "Seek preserves sustained notes; cycle ranges and metronome affect only playback."
  (let ((session (make-session)))
    (render-wav (session-song session) "build/daw-range.wav" :start 1/2 :end 1)
    (let ((samples (pcm-values "build/daw-range.wav")))
      (assert (= 11025 (length samples)))
      (assert (some (lambda (sample) (/= sample 0)) samples)))
    (let ((song (make-song :beats 4)))
      (render-wav song "build/daw-click.wav" :metronome t)
      (render-wav song "build/daw-silent.wav")
      (assert (some (lambda (sample) (/= sample 0))
                    (pcm-values "build/daw-click.wav")))
      (assert (every #'zerop (pcm-values "build/daw-silent.wav"))))))

(defun test-cycle-playback ()
  "Run multiple real ffplay cycles, then resume from a different cursor."
  (let ((session (make-session :song (make-song :beats 4 :tempo 240)
                               :cycle-p t :cycle-start 0 :cycle-end 1)))
    (unwind-protect
         (progn
           (%lui.example.daw-demo:play-song session)
           (sleep 0.6)
           (assert (uiop:process-alive-p
                    (%lui.example.daw-demo:session-player session)))
           (assert (<= 0 (%lui.example.daw-demo:transport-position session) 1))
           (%lui.example.daw-demo:stop-player session)
           (setf (session-cycle-p session) nil (session-playhead session) 2)
           (%lui.example.daw-demo:play-song session)
           (assert (= 2 (session-play-start session)))
           (assert (= 4 (session-play-end session)))
           (assert (= 22050 (length (pcm-values
                           (%lui.example.daw-demo:session-scratch session))))))
      (%lui.example.daw-demo:close-session session))))

(defun run-tests ()
  "Run direct-manipulation, history, project and transport-range regressions."
  (test-pointer-editing)
  (test-history-and-clipboard)
  (test-bounds-and-projects)
  (test-record-offset)
  (test-render-range)
  (test-cycle-playback)
  (format t "DAW pointer capture, right-click delete, undo, clipboard and ranges passed.~%"))
