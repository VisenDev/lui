(defpackage #:%lui.example.daw-model
  (:use #:cl)
  (:export #:note #:make-note #:note-pitch #:note-start #:note-duration
           #:note-velocity #:track #:make-track #:track-name #:track-notes
           #:track-volume #:track-muted-p #:track-solo-p #:track-wave
           #:song #:make-song #:song-tracks #:song-tempo #:song-beats
           #:demo-song #:add-note #:remove-note #:note-at #:audible-p
           #:recorder #:make-recorder #:midi-event #:finish-recording
           #:render-wav #:save-song #:load-song #:clone-song #:clone-track
           #:clone-note))
(in-package #:%lui.example.daw-model)

(defstruct note
  (pitch 60 :type (integer 0 127))
  (start 0 :type real)
  (duration 1/4 :type real)
  (velocity 100 :type (integer 1 127)))

(defstruct track
  (name "Track" :type string)
  (notes (make-array 0 :element-type 'note :adjustable t :fill-pointer 0)
         :type (vector note))
  (volume 0.7 :type real)
  (muted-p nil :type boolean)
  (solo-p nil :type boolean)
  (wave :sine :type (member :sine :triangle :organ)))

(defstruct song
  (tracks (make-array 0 :element-type 'track :adjustable t :fill-pointer 0)
          :type (vector track))
  (tempo 120 :type (integer 40 240))
  (beats 16 :type (integer 4 128)))

(defun clone-note (note)
  "Copy one editable note without sharing mutable state."
  (copy-note note))

(defun clone-track (track)
  "Copy a track and its notes for duplication and undo snapshots."
  (let ((copy (copy-track track))
        (notes (make-array 0 :element-type 'note :adjustable t :fill-pointer 0)))
    (loop :for note :across (track-notes track)
          :do (vector-push-extend (clone-note note) notes))
    (setf (track-notes copy) notes)
    copy))

(defun clone-song (song)
  "Return an independent snapshot, preserving adjustable track storage."
  (let ((copy (make-song :tempo (song-tempo song) :beats (song-beats song))))
    (loop :for track :across (song-tracks song)
          :do (vector-push-extend (clone-track track) (song-tracks copy)))
    copy))

(defun add-note (track pitch start duration &optional (velocity 100))
  "Insert a note in beat coordinates and return its stable identity."
  (assert (and (<= 0 start) (< 0 duration)))
  (let ((note (make-note :pitch pitch :start start :duration duration
                         :velocity velocity)))
    (vector-push-extend note (track-notes track))
    note))

(defun remove-note (track note)
  "Remove NOTE without changing the identity of other notes."
  (declare (values))
  (setf (track-notes track) (delete note (track-notes track)))
  (values))

(defun note-at (track pitch beat)
  "Find a note covering a piano-roll cell."
  (find-if (lambda (note)
             (and (= pitch (note-pitch note))
                  (<= (note-start note) beat)
                  (< beat (+ (note-start note) (note-duration note)))))
           (track-notes track) :from-end t))

(defun audible-p (song track)
  "Mute takes precedence over solo; any solo silences other tracks."
  (and (not (track-muted-p track))
       (or (track-solo-p track)
           (not (some #'track-solo-p (song-tracks song))))))

(defun demo-song ()
  "Create a four-bar sketch with independently editable instruments."
  (let ((song (make-song)))
    (dolist (spec '(("Keys" :sine 60) ("Bass" :triangle 36)
                    ("Organ" :organ 67)))
      (let ((track (make-track :name (first spec) :wave (second spec))))
        (dotimes (bar 4)
          (add-note track (+ (third spec) (aref #(0 5 7 0) bar))
                    (* bar 4) (if (= (third spec) 36) 2 1) 90))
        (vector-push-extend track (song-tracks song))))
    song))

(defstruct recorder
  (track (make-track) :type track)
  (tempo 120 :type real)
  (beats 16 :type real)
  (offset 0 :type real)
  (pending (make-hash-table :test #'equal) :type hash-table)
  (sustain (make-array 16 :element-type 'bit :initial-element 0)
           :type (simple-bit-vector 16)))

(defun close-key (recorder key seconds)
  "Commit a held note, quantizing onset and length to sixteenth notes."
  (declare (values))
  (let ((entry (gethash key (recorder-pending recorder))))
    (when entry
      (let* ((start (first entry))
             (end (min (recorder-beats recorder)
                       (+ (recorder-offset recorder)
                          (* seconds (/ (recorder-tempo recorder) 60)))))
             (onset (* 1/4 (round (* start 4))))
             (duration (max 1/4 (* 1/4 (round (* (- end onset) 4))))))
        (when (< onset (recorder-beats recorder))
          (add-note (recorder-track recorder) (cdr key) onset
                    (min duration (- (recorder-beats recorder) onset))
                    (second entry))))
      (remhash key (recorder-pending recorder))))
  (values))

(defun release-channel (recorder channel seconds &optional all)
  "Release sustained notes, or every held note for a channel."
  (declare (values))
  (let ((keys nil))
    (maphash (lambda (key entry)
               (when (and (= channel (car key)) (or all (third entry)))
                 (push key keys)))
             (recorder-pending recorder))
    (dolist (key keys) (close-key recorder key seconds)))
  (values))

(defun midi-event (recorder seconds status data1 data2)
  "Record channel note messages, sustain, all-notes-off and velocity-zero off.
SECONDS is monotonic time since record start, independent of UI frame rate."
  (declare (values))
  (assert (and (<= 0 seconds) (<= 128 status 255)
               (<= 0 data1 127) (<= 0 data2 127)))
  (let* ((channel (logand status 15))
         (kind (logand status #xf0))
         (key (cons channel data1))
         (entry (gethash key (recorder-pending recorder))))
    (cond
      ((and (= kind #x90) (plusp data2))
       (close-key recorder key seconds)
       (setf (gethash key (recorder-pending recorder))
             (list (+ (recorder-offset recorder)
                      (* seconds (/ (recorder-tempo recorder) 60)))
                   data2 nil)))
      ((or (= kind #x80) (and (= kind #x90) (zerop data2)))
       (when entry
         (if (= 1 (aref (recorder-sustain recorder) channel))
             (setf (third entry) t)
             ;; else
             (close-key recorder key seconds))))
      ((and (= kind #xb0) (= data1 64))
       (setf (aref (recorder-sustain recorder) channel)
             (if (>= data2 64) 1 0))
       (when (< data2 64) (release-channel recorder channel seconds)))
      ((and (= kind #xb0) (member data1 '(120 123)))
       (release-channel recorder channel seconds t))))
  (values))

(defun finish-recording (recorder seconds)
  "Close all held notes on stop, timeout or device disconnection."
  (declare (values))
  (dotimes (channel 16) (release-channel recorder channel seconds t))
  (values))

(defun write-le (value bytes stream)
  "Write an unsigned little-endian word."
  (declare (values))
  (dotimes (index bytes) (write-byte (ldb (byte 8 (* 8 index)) value) stream))
  (values))

(defun write-tag (tag stream)
  "Write an ASCII RIFF chunk tag."
  (declare (values))
  (map nil (lambda (char) (write-byte (char-code char) stream)) tag)
  (values))

(defun tone (phase wave)
  "Evaluate a bounded periodic oscillator; the organ adds two harmonics."
  (ecase wave
    (:sine (sin phase))
    (:triangle (* (/ 2 pi) (asin (sin phase))))
    (:organ (/ (+ (sin phase) (* 0.4 (sin (* 2 phase)))
                   (* 0.2 (sin (* 3 phase)))) 1.6))))

(defun mix-note (samples note track tempo rate origin)
  "Mix one voice with attack/release ramps to avoid note-edge clicks."
  (declare (values))
  (let* ((start (round (* rate (- (note-start note) origin) (/ 60 tempo))))
         (count (max 1 (round (* rate (note-duration note) (/ 60 tempo)))))
         (step (/ (* 2 pi 440 (expt 2 (/ (- (note-pitch note) 69) 12))) rate))
         (gain (* 0.22 (track-volume track) (/ (note-velocity note) 127))))
    (loop :for index :from (max 0 (- start))
          :below (min count (- (length samples) start))
          :do
      (let ((envelope (min 1 (/ index (* rate 0.008))
                            (/ (- count index 1) (* rate 0.035)))))
        (incf (aref samples (+ start index))
              (coerce (* gain envelope (tone (* index step) (track-wave track)))
                      'single-float)))))
  (values))

(defun mix-metronome (samples tempo rate start end)
  "Add short downbeat/beat clicks to a transport render, never an export."
  (declare (values))
  (loop :for beat :from (ceiling start) :below end
        :for offset := (round (* (- beat start) rate (/ 60 tempo)))
        :for frequency := (if (zerop (mod beat 4)) 1760 1100)
        :do (dotimes (index (min (round (* rate 0.025))
                                 (- (length samples) offset)))
              (incf (aref samples (+ offset index))
                    (coerce (* 0.28 (exp (/ (- index) (* rate 0.004)))
                               (sin (* 2 pi frequency (/ index rate))))
                            'single-float))))
  (values))

(defun render-wav (song path &key (rate 44100) (start 0)
                                 (end (song-beats song)) metronome)
  "Render the audible mix as mono PCM16 WAV, normalizing only to avoid clipping.
This small offline synth is deliberately replaceable by a CLM renderer with
this same SONG/PATH contract. Playback is a rendered snapshot, not live DSP."
  (assert (<= 0 start end (song-beats song)))
  (let* ((count (ceiling (* rate (- end start) (/ 60 (song-tempo song)))))
         (samples (make-array count :element-type 'single-float
                                   :initial-element 0.0))
         (peak 1.0))
    (loop :for track :across (song-tracks song)
          :when (audible-p song track)
            :do (loop :for note :across (track-notes track)
                      :do (mix-note samples note track (song-tempo song)
                                    rate start)))
    (when metronome
      (mix-metronome samples (song-tempo song) rate start end))
    (loop :for sample :across samples :do (setf peak (max peak (abs sample))))
    (ensure-directories-exist path)
    (with-open-file (stream path :direction :output :if-exists :supersede
                                 :element-type '(unsigned-byte 8))
      (write-tag "RIFF" stream)
      (write-le (+ 36 (* 2 count)) 4 stream)
      (write-tag "WAVEfmt " stream)
      (dolist (pair `((16 4) (1 2) (1 2) (,rate 4) (,(* rate 2) 4)
                      (2 2) (16 2)))
        (write-le (first pair) (second pair) stream))
      (write-tag "data" stream)
      (write-le (* 2 count) 4 stream)
      (loop :for sample :across samples
            :do (write-le (logand #xffff (round (* 32767 (/ sample peak))))
                          2 stream)))
    path))

(defun save-song (song path)
  "Save plain project data; no Lisp executable forms or structure readers."
  (declare (values))
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede)
    (with-standard-io-syntax
      (write (list :lui-daw 1 (song-tempo song) (song-beats song)
                   (loop :for track :across (song-tracks song)
                         :collect
                         (list (track-name track) (track-wave track)
                               (track-volume track) (track-muted-p track)
                               (track-solo-p track)
                               (loop :for note :across (track-notes track)
                                     :collect (list (note-pitch note)
                                                    (note-start note)
                                                    (note-duration note)
                                                    (note-velocity note))))))
             :stream stream)))
  (values))

(defun load-track (data beats)
  "Validate one serialized track before constructing model objects."
  (assert (and (listp data) (= (length data) 6)))
  (destructuring-bind (name wave volume muted solo notes) data
    (assert (and (stringp name) (member wave '(:sine :triangle :organ))
                 (realp volume) (<= 0 volume 1)
                 (typep muted 'boolean) (typep solo 'boolean)
                 (listp notes) (<= (length notes) 10000)))
    (let ((track (make-track :name name :wave wave :volume volume
                             :muted-p muted :solo-p solo)))
      (dolist (data notes)
        (assert (and (listp data) (= (length data) 4)))
        (destructuring-bind (pitch start duration velocity) data
          (assert (and (typep pitch '(integer 0 127))
                       (typep velocity '(integer 1 127))
                       (realp start) (realp duration)
                       (<= 0 start) (< start beats) (< 0 duration)
                       (<= (+ start duration) beats)))
          (add-note track pitch start duration velocity)))
      track)))

(defun load-song (path)
  "Load a validated project with reader evaluation disabled."
  (with-open-file (stream path)
    (with-standard-io-syntax
      (let* ((*read-eval* nil)
             (data (read stream)))
        (assert (and (listp data) (= (length data) 5)
                     (eq (first data) :lui-daw) (eql (second data) 1)
                     (typep (third data) '(integer 40 240))
                     (typep (fourth data) '(integer 4 128))
                     (zerop (mod (fourth data) 4))
                     (listp (fifth data)) (<= 1 (length (fifth data)) 32)))
        (let ((song (make-song :tempo (third data) :beats (fourth data))))
          (dolist (track (fifth data))
            (vector-push-extend (load-track track (song-beats song))
                                (song-tracks song)))
          song)))))
