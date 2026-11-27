(defpackage #:%lui.example.daw-roll
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
    #:note #:add-note #:note-at #:note-pitch #:note-start #:note-duration
    #:note-velocity #:track-notes #:song-beats #:clone-note #:clone-song)
  (:import-from #:%lui.example.daw-state
    #:session-song #:session-selected #:session-selection #:session-page
    #:session-octave #:session-view-bars #:session-snap #:session-tool
    #:session-duration #:session-velocity #:session-playhead #:session-gesture
    #:session-cycle-p #:session-cycle-start #:session-cycle-end
    #:session-status #:current-track #:editable-p #:playing-p
    #:select-notes #:clear-selection #:delete-selected #:copy-selected
    #:paste-notes #:duplicate-selected #:quantize-selected #:move-selected
    #:undo-edit #:redo-edit #:snap-beat #:edit-note
    #:make-gesture #:gesture-kind #:gesture-beat #:gesture-pitch
    #:gesture-end-beat #:gesture-end-pitch #:gesture-originals
    #:gesture-notes #:gesture-changed-p #:commit-gesture #:cancel-gesture
    #:gesture-frame-width #:gesture-frame-height)
  (:export #:draw #:pitch-name #:roll-point #:note-bounds #:handle-event
           #:draw-lane #:track-active-p #:navigate-lane))
(in-package #:%lui.example.daw-roll)

(defconstant +keyboard-width+ 58)
(defconstant +ruler-height+ 26)
(defconstant +rows+ 24)

(defun track-active-p (session track)
  "Report scheduled note activity, respecting mute, solo and track gain."
  (and (%lui.example.daw-model:audible-p (session-song session) track)
       (plusp (%lui.example.daw-model:track-volume track))
       (some (lambda (note)
               (and (plusp (note-velocity note))
                    (<= (note-start note) (session-playhead session))
                    (< (session-playhead session)
                       (+ (note-start note) (note-duration note)))))
             (track-notes track))))

(defun navigate-lane (session index beat)
  "Reveal a track and time in the editor without seeking running playback."
  (declare (values))
  (when (editable-p session)
    (cancel-gesture session)
    (%lui.example.daw-state:select-track session index)
    (let ((beat (max 0 (min beat (- (song-beats (session-song session))
                                   (session-snap session))))))
      (setf (session-page session) (floor beat 4))
      (unless (playing-p session)
        (setf (session-playhead session) (snap-beat session beat)))))
  (values))

(defun paint-lane (session track index renderer box)
  "Paint the complete song with note previews and a common time scale."
  (declare (values))
  (let* ((x (lui:box-x box))
         (y (lui:box-y box))
         (height (lui:box-height box))
         (scale (/ (lui:box-width box) (song-beats (session-song session))))
         (selected (= index (%lui.example.daw-state:session-track session)))
         (audible (%lui.example.daw-model:audible-p (session-song session) track))
         (color (aref #("#58c49c" "#69a9e9" "#c58ae6" "#e5aa62")
                      (mod index 4))))
    (rectangle renderer x y (lui:box-width box) height
               (if selected "#263e4d" "#1c2531"))
    (when selected
      (rectangle renderer (+ x (* 4 (session-page session) scale)) y
                 (* (min (* 4 (session-view-bars session))
                         (- (song-beats (session-song session))
                            (* 4 (session-page session)))) scale)
                 height "#83b8ef" 0.15))
    (loop :for beat :from 0 :below (song-beats (session-song session)) :by 4
          :for at := (+ x (* beat scale))
          :do (rectangle renderer at y 1 height "#485767")
              (lui.draw:paint-text renderer (write-to-string (1+ (/ beat 4)))
                                   (+ at 4) (+ y 13) "#aab6c4"))
    (loop :for note :across (track-notes track)
          :do (rectangle renderer (+ x (* (note-start note) scale))
                         (+ y 19 (* (- 127 (note-pitch note))
                                    (/ (- height 25) 128)))
                         (max 2 (* (note-duration note) scale)) 4
                         (if audible color "#637080")))
    (rectangle renderer (+ x (* (session-playhead session) scale)) y
               2 height "#f2d58b"))
  (values))

(defun draw-lane (session track index)
  "Show all bars of a track; clicking reveals that time in the piano roll."
  (declare (values))
  (lui:canvas nil :id :arrangement-lane :width (lui:grow) :height 80
              :font-size 11
              :disabled-p (not (editable-p session))
              :accessible-name
              (format nil "~A: full song; click to edit"
                      (%lui.example.daw-model:track-name track))
              :painter (lambda (renderer node)
                         (paint-lane session track index renderer
                                     (lui:element-box node))))
  (let ((box (lui:previous-box :arrangement-lane)))
    (when box
      (loop :for event :across (lui:events-for :arrangement-lane)
            :when (and (eq (lui:event-kind event) :press)
                       (eq (lui:event-button event) :primary))
              :do (navigate-lane
                   session index
                   (* (song-beats (session-song session))
                      (/ (- (lui:event-x event) (lui:box-x box))
                         (max 1 (lui:box-width box))))))))
  (values))

(defun pitch-name (pitch)
  "Name MIDI pitches with middle C as C4."
  (format nil "~A~D" (aref #("C" "C#" "D" "D#" "E" "F" "F#"
                              "G" "G#" "A" "A#" "B") (mod pitch 12))
          (1- (floor pitch 12))))

(defun base-pitch (session)
  "Lowest visible pitch, clamped so the final octave fits MIDI's range."
  (min 104 (* 12 (1+ (session-octave session)))))

(defun beat-width (session box)
  "Pixels per beat in this zoom level."
  (/ (max 1 (- (lui:box-width box) +keyboard-width+))
     (* 4 (session-view-bars session))))

(defun row-height (box)
  "Pixels per semitone, independent of text metrics."
  (/ (max 1 (- (lui:box-height box) +ruler-height+)) +rows+))

(defun roll-point (session box x y)
  "Map surface coordinates to continuous beats and MIDI pitch."
  (values (+ (* 4 (session-page session))
             (/ (- x (lui:box-x box) +keyboard-width+) (beat-width session box)))
          (+ (base-pitch session) (1- +rows+)
             (- (floor (- y (lui:box-y box) +ruler-height+)
                       (row-height box))))))

(defun note-bounds (session box note)
  "Return a visible clipped note rectangle or NIL."
  (let* ((first (* 4 (session-page session)))
         (last (+ first (* 4 (session-view-bars session))))
         (start (max first (note-start note)))
         (end (min last (+ (note-start note) (note-duration note))))
         (row (- (+ (base-pitch session) (1- +rows+)) (note-pitch note))))
    (when (and (< start end) (<= 0 row) (< row +rows+))
      (lui:make-box
       :x (+ (lui:box-x box) +keyboard-width+
             (* (- start first) (beat-width session box)) 1)
       :y (+ (lui:box-y box) +ruler-height+ (* row (row-height box)) 1)
       :width (max 1 (- (* (- end start) (beat-width session box)) 2))
       :height (max 1 (- (row-height box) 2))))))

(defun rectangle (renderer x y width height color &optional (alpha 1))
  "Paint a simple rectangle through LUI's public drawing API."
  (declare (values))
  (lui.draw:shape renderer
                  (lui:make-box :x x :y y :width (max 0 width)
                               :height (max 0 height)) 0 color alpha)
  (values))

(defun paint-grid (session renderer box)
  "Paint a piano keyboard, bar ruler, alternating keys and snap lines."
  (declare (values))
  (let ((x (lui:box-x box))
        (y (lui:box-y box))
        (width (lui:box-width box))
        (height (lui:box-height box))
        (beat-width (beat-width session box))
        (row-height (row-height box)))
    (rectangle renderer x y width height "#171d26")
    (dotimes (row +rows+)
      (let* ((pitch (- (+ (base-pitch session) (1- +rows+)) row))
             (top (+ y +ruler-height+ (* row row-height)))
             (black (member (mod pitch 12) '(1 3 6 8 10))))
        (rectangle renderer (+ x +keyboard-width+) top
                   (- width +keyboard-width+) (1- row-height)
                   (if black "#1c2531" "#25303e"))
        (rectangle renderer x top (- +keyboard-width+ 2) (1- row-height)
                   (if black "#151b24" "#c8d0d9"))
        (lui.draw:paint-text renderer (pitch-name pitch) (+ x 9)
                            (+ top (* row-height 0.75))
                            (if black "#aab6c4" "#273341"))))
    (loop :for beat :from 0 :to (* 4 (session-view-bars session))
          :by (session-snap session)
          :for at := (+ x +keyboard-width+ (* beat beat-width))
          :do (rectangle renderer at (+ y +ruler-height+) 1
                         (- height +ruler-height+)
                         (cond ((zerop (mod beat 4)) "#748396")
                               ((integerp beat) "#485767") (t "#303b49"))))
    (dotimes (bar (session-view-bars session))
      (lui.draw:paint-text renderer
                          (format nil "~D" (+ 1 (session-page session) bar))
                          (+ x +keyboard-width+ 5 (* bar 4 beat-width))
                          (+ y 18) "#d6dfeb")))
  (values))

(defun paint-notes (session renderer box)
  "Draw continuous note blocks with resize grips and velocity strips."
  (declare (values))
  (loop :for note :across (track-notes (current-track session))
        :for bounds := (note-bounds session box note)
        :when bounds
          :do (let ((selected (find note (session-selection session))))
                (lui.draw:shape renderer bounds 3
                                (if selected "#f5b85d" "#56bda0") 1)
                (when (and (> (lui:box-width bounds) 38)
                           (>= (lui:box-height bounds) 16))
                  (lui.draw:paint-text
                   renderer (pitch-name (note-pitch note))
                   (+ (lui:box-x bounds) 4) (+ (lui:box-y bounds) 15) "#112c2b"))
                (rectangle renderer (+ (lui:box-x bounds) 2)
                           (+ (lui:box-y bounds) (lui:box-height bounds) -3)
                           (* (- (lui:box-width bounds) 4)
                              (/ (note-velocity note) 127)) 2 "#1b665a")
                (when (> (lui:box-width bounds) 10)
                  (rectangle renderer
                             (+ (lui:box-x bounds) (lui:box-width bounds) -5)
                             (+ (lui:box-y bounds) 4) 1
                             (- (lui:box-height bounds) 8) "#254a42"))))
  (values))

(defun paint-cursor (session renderer box)
  "Draw the playhead, loop range, and any active selection rectangle."
  (declare (values))
  (let* ((first (* 4 (session-page session)))
         (last (+ first (* 4 (session-view-bars session))))
         (scale (beat-width session box))
         (x (+ (lui:box-x box) +keyboard-width+)))
    (when (session-cycle-p session)
      (let ((start (max first (session-cycle-start session)))
            (end (min last (session-cycle-end session))))
        (when (< start end)
          (rectangle renderer (+ x (* (- start first) scale))
                     (lui:box-y box) (* (- end start) scale) 4 "#e3ae54"))))
    (when (<= first (session-playhead session) last)
      (rectangle renderer (+ x (* (- (session-playhead session) first) scale))
                 (+ (lui:box-y box) 4) 2 (- (lui:box-height box) 4) "#f2d58b"))
    (let ((gesture (session-gesture session)))
      (when (and gesture (eq (gesture-kind gesture) :marquee))
        (let* ((start (min (gesture-beat gesture) (gesture-end-beat gesture)))
               (end (max (gesture-beat gesture) (gesture-end-beat gesture)))
               (high (max (gesture-pitch gesture) (gesture-end-pitch gesture)))
               (low (min (gesture-pitch gesture) (gesture-end-pitch gesture))))
          (rectangle renderer (+ x (* (- start first) scale))
                     (+ (lui:box-y box) +ruler-height+
                        (* (- (+ (base-pitch session) 23) high) (row-height box)))
                     (* (- end start) scale) (* (1+ (- high low)) (row-height box))
                     "#83b8ef" 0.25)))))
  (values))

(defun paint-roll (session renderer node)
  "Paint the editor using renderer-independent LUI primitives."
  (declare (values))
  (let ((box (lui:element-box node)))
    (paint-grid session renderer box)
    (paint-notes session renderer box)
    (paint-cursor session renderer box))
  (values))

(defun single-selection (session note)
  "Select one note without allocating a heterogeneous vector."
  (declare (values))
  (select-notes session (make-array 1 :element-type 'note :initial-element note))
  (values))

(defun begin-note-gesture (session box beat pitch)
  "Select, draw, erase, resize, or begin a marquee at the pointer."
  (declare (values))
  (let* ((note (note-at (current-track session) pitch beat))
         (snapshot (clone-song (session-song session)))
         (kind :move))
    (cond
      ((eq (session-tool session) :erase)
       (when note (single-selection session note) (delete-selected session))
       (return-from begin-note-gesture (values)))
      (note
       (unless (find note (session-selection session))
         (single-selection session note))
       (when (>= beat (- (+ (note-start note) (note-duration note))
                        (min (/ (note-duration note) 3) (/ 8 (beat-width session box)))))
         (setf kind :resize)))
      ((eq (session-tool session) :select)
       (clear-selection session)
       (setf kind :marquee))
      (t
       (setf kind :draw)
       (let ((start (max 0 (min (- (song-beats (session-song session))
                                   (session-snap session))
                                (snap-beat session beat)))))
         (setf note (add-note (current-track session) pitch start
                              (min (session-duration session)
                                   (- (song-beats (session-song session)) start))
                              (session-velocity session)))
         (single-selection session note))))
    (setf (session-gesture session)
          (make-gesture :kind kind :beat beat :pitch pitch
                        :frame-width (lui:frame-width)
                        :frame-height (lui:frame-height)
                        :end-beat beat :end-pitch pitch :snapshot snapshot
                        :notes (copy-seq (session-selection session))
                        :originals (map '(vector note) #'clone-note
                                        (session-selection session))
                        :changed-p (eq kind :draw))))
  (values))

(defun update-note-gesture (session beat pitch)
  "Preview a drag against its original values so rounding cannot accumulate."
  (declare (values))
  (let ((gesture (session-gesture session)))
    (when gesture
      (setf (gesture-end-beat gesture) beat (gesture-end-pitch gesture) pitch)
      (let* ((notes (gesture-notes gesture))
             (originals (gesture-originals gesture))
             (delta (snap-beat session (- beat (gesture-beat gesture))))
             (transpose (- pitch (gesture-pitch gesture)))
             (end (song-beats (session-song session))))
        (case (gesture-kind gesture)
          (:marquee
           (select-notes session
             (remove-if-not
              (lambda (note)
                (and (<= (min (gesture-pitch gesture) pitch) (note-pitch note)
                         (max (gesture-pitch gesture) pitch))
                     (< (note-start note) (max (gesture-beat gesture) beat))
                     (> (+ (note-start note) (note-duration note))
                        (min (gesture-beat gesture) beat))))
              (track-notes (current-track session)))))
          (:move
           (setf delta (max (- (reduce #'min originals :key #'note-start))
                            (min delta (- end (loop :for note :across originals
                                :maximize (+ (note-start note) (note-duration note))))))
                 transpose (max (- (reduce #'min originals :key #'note-pitch))
                                (min transpose (- 127 (reduce #'max originals
                                                              :key #'note-pitch)))))
           (loop :for note :across notes :for original :across originals
                 :do (setf (note-start note) (+ (note-start original) delta)
                           (note-pitch note) (+ (note-pitch original) transpose)))
           (setf (gesture-changed-p gesture) (or (/= delta 0) (/= transpose 0))))
          ((:resize :draw)
           (when (or (eq (gesture-kind gesture) :resize) (/= delta 0))
             (loop :for note :across notes :for original :across originals
                   :do (setf (note-duration note)
                             (min (- end (note-start original))
                                  (max (session-snap session)
                                       (snap-beat session
                                        (+ (note-duration original) delta))))))
             (setf (gesture-changed-p gesture) t)))))))
  (values))

(defun roll-key (session event)
  "Apply exact editor-scoped chords; leave ordinary typing to text fields."
  (flet ((plain (key) (lui:event-shortcut-p event key))
         (primary (key &optional shift)
           (lui:event-shortcut-p event key :primary t :shift shift)))
    (cond
      ((or (plain lui.key:delete) (plain lui.key:backspace))
       (delete-selected session))
      ((plain lui.key:escape)
       (cancel-gesture session) (clear-selection session))
      ((plain lui.key:left) (move-selected session (- (session-snap session)) 0))
      ((plain lui.key:right) (move-selected session (session-snap session) 0))
      ((plain lui.key:up) (move-selected session 0 1))
      ((plain lui.key:down) (move-selected session 0 -1))
      ((primary lui.key:a)
       (select-notes session (copy-seq (track-notes (current-track session)))))
      ((primary lui.key:c) (copy-selected session))
      ((primary lui.key:v) (paste-notes session))
      ((primary lui.key:d) (duplicate-selected session))
      ((plain lui.key:q) (quantize-selected session))
      ((primary lui.key:z t) (redo-edit session))
      ((primary lui.key:z) (undo-edit session))
      ((lui:event-shortcut-p event lui.key:y :control t) (redo-edit session))
      ((plain lui.key:space) :toggle-play))))

(defun handle-event (session box event)
  "Route right-click removal, captured drags, cancellation and editor keys."
  (when (and (editable-p session)
             (member (lui:event-kind event) '(:key :text)))
    (when (session-gesture session) (cancel-gesture session))
    (return-from handle-event (roll-key session event)))
  (when (eq (lui:event-kind event) :cancel)
    (cancel-gesture session))
  (when (and (editable-p session) box)
    (multiple-value-bind (beat pitch)
        (roll-point session box (lui:event-x event) (lui:event-y event))
      (let ((kind (lui:event-kind event)))
        (cond
          ((and (eq kind :press) (<= 0 pitch 127)
                (>= (lui:event-y event) (+ (lui:box-y box) +ruler-height+))
                (< (lui:event-x event) (+ (lui:box-x box) +keyboard-width+)))
           (select-notes session
             (remove-if-not (lambda (note) (= pitch (note-pitch note)))
                            (track-notes (current-track session)))))
          ((and (eq kind :press)
                (< (lui:event-y event) (+ (lui:box-y box) +ruler-height+)))
           (unless (playing-p session)
             (setf (session-playhead session)
                   (max 0 (min (song-beats (session-song session))
                               (snap-beat session beat))))))
          ((and (eq kind :press) (<= 0 pitch 127)
                (>= (lui:event-x event) (+ (lui:box-x box) +keyboard-width+))
                (<= 0 beat) (< beat (song-beats (session-song session))))
           (lui:focus-widget :piano-roll)
           (cancel-gesture session)
           (if (eq (lui:event-button event) :secondary)
               (let ((note (note-at (current-track session) pitch beat)))
                 (when note (single-selection session note)
                            (delete-selected session)))
               ;; else
               (begin-note-gesture session box beat pitch)))
          ((and (eq kind :move) (session-gesture session)
                (lui:event-dragging-p event))
           (update-note-gesture session beat (max 0 (min 127 pitch))))
          ((and (eq kind :release) (eq (lui:event-button event) :primary)
                (session-gesture session))
           (update-note-gesture session beat (max 0 (min 127 pitch)))
           (commit-gesture session))))))
  nil)

(defun draw-terminal (session)
  "Keep a compact accessible button grid for terminal use."
  (declare (values))
  (dotimes (row 12)
    (let ((pitch (min 127 (+ (base-pitch session) (- 23 row)))))
      (lui:row (:id pitch :gap 0)
        (lui:label (pitch-name pitch) :width 5)
        (dotimes (step 16)
          (let* ((beat (+ (* 4 (session-page session)) (/ step 4)))
                 (note (note-at (current-track session) pitch beat)))
            (multiple-value-bind (activated changed id)
                (lui:button (if note "o" ".") :id (list pitch beat)
                            :width 4 :height 1 :disabled-p (not (editable-p session)))
              (declare (ignore changed))
              (when activated
                (if note (single-selection session note)
                    (edit-note session pitch beat)))
              (loop :for event :across (lui:events-for id)
                    :when (and note (eq (lui:event-kind event) :press)
                               (eq (lui:event-button event) :secondary))
                      :do (single-selection session note)
                          (delete-selected session))))))))
  (values))

(defun draw (session)
  "Declare a scalable editor; return true when Space requests transport toggle."
  (let ((gesture (session-gesture session)))
    (when (and gesture
               (or (/= (gesture-frame-width gesture) (lui:frame-width))
                   (/= (gesture-frame-height gesture) (lui:frame-height))))
      (cancel-gesture session)
      (lui:request-frame)))
  (if (lui:text-mode-p)
      (progn (draw-terminal session) nil)
      ;; else
      (progn
        (lui:canvas nil :id :piano-roll :width (lui:grow) :height 330
                    :font-size 12 :disabled-p (not (editable-p session))
                    :accessible-name "Piano roll: draw, move, resize or erase notes"
                    :painter (lambda (renderer node)
                               (paint-roll session renderer node)))
        (let ((toggle nil)
              (box (lui:previous-box :piano-roll)))
          (loop :for event :across (lui:events-for :piano-roll)
                :do (when (eq :toggle-play (handle-event session box event))
                      (setf toggle t)))
          toggle))))
