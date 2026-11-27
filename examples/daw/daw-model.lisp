(defpackage #:%lui.example.daw-model
  (:use #:cl)
  (:export #:note #:make-note #:note-pitch #:note-start #:note-duration
           #:note-velocity #:track #:make-track #:track-name #:track-notes
           #:track-volume #:track-muted-p #:track-solo-p #:track-wave
           #:song #:make-song #:song-tracks #:song-tempo #:song-beats
           #:demo-song #:add-note #:remove-note #:note-at #:audible-p
           #:recorder #:make-recorder #:midi-event #:finish-recording
           #:render-wav #:render-dry-track #:make-effect-state #:configure-effects
           #:effect-state #:effect-sample #:song-master-volume #:track-distortion #:track-cutoff
           #:track-resonance #:track-reverb #:mix-metronome #:save-song #:load-song #:clone-song #:clone-track
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
  (wave :sine :type (member :sine :triangle :organ :drums))
  (distortion 0.0 :type real)
  (cutoff 20000.0 :type real)
  (resonance 0.0 :type real)
  (reverb 0.0 :type real))

(defstruct song
  (tracks (make-array 0 :element-type 'track :adjustable t :fill-pointer 0)
          :type (vector track))
  (tempo 120 :type (integer 40 240))
  (master-volume 1.0 :type real)
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
  (let ((copy (make-song :tempo (song-tempo song) :beats (song-beats song)
                         :master-volume (song-master-volume song))))
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

(defun passacaglia-bar (arpeggio bass melody bar root chord tune)
  "Arrange one ground-bass variation with articulated notes and a final cadence."
  (declare (values))
  (let ((start (* bar 4))
        (final (= bar 15))
        (variation (>= bar 8)))
    (add-note bass root start (if final 4 7/4) 100)
    (unless final
      (add-note bass (+ root 7) (+ start 2) 3/4 74)
      (add-note bass (+ root 12) (+ start 3) 3/4 82))
    (dotimes (step (if final 4 8))
      (let* ((pattern (if variation #(3 2 1 2 0 2 1 3)
                         #(0 2 1 3 2 1 2 3)))
             (pitch (aref chord (aref pattern step))))
        (add-note arpeggio pitch (+ start (/ step 2)) 7/16
                  (+ (if variation 80 68) (if (evenp step) 10 0)))))
    (if final
        (progn
          (loop :for pitch :across chord
                :do (add-note arpeggio pitch (+ start 2) 2 76))
          (add-note melody 67 start 4 88))
        ;; else
        (dotimes (step (if variation 4 2))
          (add-note melody (aref tune (if variation step (* step 2)))
                    (+ start (if variation step (* step 2)))
                    (if variation 7/8 7/4)
                    (+ (if variation 87 75) (if (zerop step) 8 0))))))
  (values))

(defun demo-song ()
  "Create a 16-bar, 108 BPM passacaglia-inspired showcase in G minor.
Original broken-chord and melodic variations over Gm-Cm-F-Bb-Eb-Cm-D-Gm,
inspired by Handel's HWV 432 Passacaglia; not a transcription of a recording.
Three independently editable voices build over two cycles and resolve on G."
  (let ((song (make-song :tempo 108 :beats 64))
        (arpeggio (make-track :name "Broken Chords" :wave :triangle :volume 0.52))
        (bass (make-track :name "Ground Bass" :wave :sine :volume 0.70))
        (melody (make-track :name "Upper Voice" :wave :organ :volume 0.38))
        (roots #(43 48 41 46 39 48 38 43))
        (chords #(#(55 58 62 67) #(55 60 63 67) #(53 57 60 65)
                  #(53 58 62 65) #(55 58 63 67) #(55 60 63 67)
                  #(54 57 62 66) #(55 58 62 67)))
        (tunes #(#(74 70 69 67) #(75 74 72 67) #(72 69 65 69)
                 #(74 72 70 65) #(75 74 70 67) #(72 75 74 72)
                 #(69 72 69 66) #(67 69 70 74))))
    (dotimes (bar 16)
      (let ((chord (mod bar 8)))
        (passacaglia-bar arpeggio bass melody bar (aref roots chord)
                         (aref chords chord) (aref tunes chord))))
    (dolist (track (list arpeggio bass melody))
      (vector-push-extend track (song-tracks song)))
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

(defun drum-sample (pitch index rate)
  "Synthesize deterministic GM kick, snare and hi-hats without sample assets."
  (let* ((seconds (/ index (float rate 1d0)))
         (seed (logand #xffffffff (* (+ index 17) #x45d9f3b)))
         (mixed (logand #xffffffff (* (logxor seed (ash seed -16)) #x45d9f3b)))
         (noise (- (/ (logxor mixed (ash mixed -16)) 2147483648d0) 1d0)))
    (case pitch
      (36 (* (exp (* -12 seconds))
             (sin (* 2 pi (+ (* 48 seconds)
                            (* 5 (- 1 (exp (* -35 seconds)))))))))
      (38 (* (exp (* -22 seconds))
             (+ (* 0.8 noise) (* 0.2 (sin (* 2 pi 180 seconds))))))
      (46 (* 0.5 noise (exp (* -9 seconds))))
      (otherwise (* 0.5 noise (exp (* -65 seconds)))))))

(defstruct (effect-state (:constructor %make-effect-state))
  (coefficients (make-array 5 :element-type 'double-float :initial-element 0d0)
                :type (simple-array double-float (5)))
  (history (make-array 4 :element-type 'double-float :initial-element 0d0)
           :type (simple-array double-float (4)))
  (delays #() :type simple-vector)
  (positions (make-array 3 :element-type 'fixnum :initial-element 0)
             :type (simple-array fixnum (3)))
  (rate 44100 :type fixnum)
  (filter-p nil :type boolean)
  (drive 0d0 :type double-float)
  (wet 0d0 :type double-float))

(defun make-effect-state (&optional (rate 44100))
  "Allocate a biquad and three short feedback-comb reverberators per voice."
  (%make-effect-state
   :rate rate
   :delays (map 'vector
                (lambda (seconds)
                  (make-array (round (* seconds rate))
                              :element-type 'single-float :initial-element 0.0))
                #(0.0297 0.0371 0.0411))))

(defun configure-effects (state track)
  "Compute stable low-pass coefficients once per block from live parameters."
  (declare (values))
  (let* ((omega (/ (* 2 pi (min (track-cutoff track)
                               (* 0.45 (effect-state-rate state))))
                    (effect-state-rate state)))
         (cosine (cos omega))
         (alpha (/ (sin omega) (* 2 (+ 0.707 (* 9 (track-resonance track))))))
         (denominator (+ 1 alpha))
         (c (effect-state-coefficients state)))
    (when (and (plusp (effect-state-wet state)) (zerop (track-reverb track)))
      (loop :for delay :across (effect-state-delays state) :do (fill delay 0.0))
      (fill (effect-state-positions state) 0))
    (setf (effect-state-filter-p state) (< (track-cutoff track) 20000)
          (effect-state-drive state) (coerce (track-distortion track) 'double-float)
          (effect-state-wet state) (coerce (track-reverb track) 'double-float)
          (aref c 0) (/ (- 1 cosine) 2 denominator)
          (aref c 1) (/ (- 1 cosine) denominator)
          (aref c 2) (aref c 0)
          (aref c 3) (/ (* -2 cosine) denominator)
          (aref c 4) (/ (- 1 alpha) denominator)))
  (values))

(defun effect-sample (state sample)
  "Apply distortion, resonant low-pass and a small feedback-comb reverb."
  (let ((value (coerce sample 'double-float)))
    (when (plusp (effect-state-drive state))
      (let ((drive (+ 1 (* 30 (effect-state-drive state)))))
        (setf value (/ (tanh (* value drive)) (sqrt drive)))))
    (when (effect-state-filter-p state)
      (let* ((c (effect-state-coefficients state))
             (h (effect-state-history state))
             (filtered (- (+ (* (aref c 0) value)
                             (* (aref c 1) (aref h 0))
                             (* (aref c 2) (aref h 1)))
                          (* (aref c 3) (aref h 2))
                          (* (aref c 4) (aref h 3)))))
        (setf (aref h 1) (aref h 0) (aref h 0) value
              (aref h 3) (aref h 2) (aref h 2) filtered
              value filtered)))
    (when (plusp (effect-state-wet state))
      (let ((echo 0d0))
        (dotimes (i 3)
          (let* ((buffer (aref (effect-state-delays state) i))
                 (position (aref (effect-state-positions state) i))
                 (delayed (aref buffer position)))
            (incf echo delayed)
            (setf (aref buffer position) (coerce (+ value (* 0.72 delayed))
                                               'single-float)
                  (aref (effect-state-positions state) i)
                  (mod (1+ position) (length buffer)))))
        (setf value (+ (* value (- 1 (* 0.4 (effect-state-wet state))))
                       (* (/ echo 3) 0.4 (effect-state-wet state))))))
    (coerce value 'single-float)))

(defun render-dry-track (track tempo count rate start)
  "Render a unity-gain snapshot; mixing and effects are applied separately."
  (let ((samples (make-array count :element-type 'single-float :initial-element 0.0))
        (source (copy-track track)))
    (setf (track-volume source) 1.0)
    (loop :for note :across (track-notes source)
          :do (mix-note samples note source tempo rate start))
    samples))

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
              (coerce (* gain envelope (if (eq (track-wave track) :drums)
                                     (drum-sample (note-pitch note) index rate)
                                     (tone (* index step) (track-wave track))))
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
  "Render the effected mix as mono PCM16 WAV with master gain and output limiting.
This small offline synth is deliberately replaceable by a CLM renderer with
this same SONG/PATH contract. Export includes track effects and master gain."
  (assert (<= 0 start end (song-beats song)))
  (let* ((count (ceiling (* rate (- end start) (/ 60 (song-tempo song)))))
         (samples (make-array count :element-type 'single-float
                                   :initial-element 0.0))
         (master (song-master-volume song)))
    (loop :for track :across (song-tracks song)
          :when (audible-p song track)
            :do (let ((dry (render-dry-track track (song-tempo song) count rate start))
                      (effects (make-effect-state rate)))
                  (configure-effects effects track)
                  (dotimes (i count)
                    (incf (aref samples i)
                          (coerce (* (track-volume track)
                                     (effect-sample effects (aref dry i)))
                                  'single-float)))))
    (when metronome
      (mix-metronome samples (song-tempo song) rate start end))
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
            :do (write-le (logand #xffff (round (* 32767 (max -1 (min 1 (* sample master))))))
                          2 stream)))
    path))

(defun save-song (song path)
  "Save plain project data; no Lisp executable forms or structure readers."
  (declare (values))
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede)
    (with-standard-io-syntax
      (write (list :lui-daw 2 (song-tempo song) (song-beats song)
                   (song-master-volume song)
                   (loop :for track :across (song-tracks song)
                         :collect
                         (list (track-name track) (track-wave track)
                               (track-volume track) (track-muted-p track)
                               (track-solo-p track)
                               (track-distortion track) (track-cutoff track)
                               (track-resonance track) (track-reverb track)
                               (loop :for note :across (track-notes track)
                                     :collect (list (note-pitch note)
                                                    (note-start note)
                                                    (note-duration note)
                                                    (note-velocity note))))))
             :stream stream)))
  (values))

(defun load-track (data beats version)
  "Validate one serialized track before constructing model objects."
  (assert (and (listp data) (= (length data) (if (= version 1) 6 10))))
  (when (= version 1)
    (setf data (append (subseq data 0 5) (list 0.0 20000.0 0.0 0.0 (sixth data)))))
  (destructuring-bind (name wave volume muted solo distortion cutoff resonance reverb notes) data
    (assert (and (stringp name) (member wave '(:sine :triangle :organ :drums))
                 (realp volume) (<= 0 volume 1)
                 (realp distortion) (<= 0 distortion 1)
                 (realp cutoff) (<= 40 cutoff 20000)
                 (realp resonance) (<= 0 resonance 1)
                 (realp reverb) (<= 0 reverb 1)
                 (typep muted 'boolean) (typep solo 'boolean)
                 (listp notes) (<= (length notes) 10000)))
    (let ((track (make-track :name name :wave wave :volume volume
                             :muted-p muted :solo-p solo :distortion distortion
                             :cutoff cutoff :resonance resonance :reverb reverb)))
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
  "Load validated version-two projects or version-one files with neutral effects."
  (with-open-file (stream path)
    (with-standard-io-syntax
      (let* ((*read-eval* nil)
             (data (read stream)))
        (assert (and (listp data) (eq (first data) :lui-daw)
                     (member (second data) '(1 2))
                     (= (length data) (if (= (second data) 1) 5 6))))
        (let* ((version (second data))
               (master (if (= version 1) 1.0 (fifth data)))
               (tracks (if (= version 1) (fifth data) (sixth data))))
          (assert (and (typep (third data) '(integer 40 240))
                       (typep (fourth data) '(integer 4 128))
                       (zerop (mod (fourth data) 4))
                       (realp master) (<= 0 master 1)
                       (listp tracks) (<= 1 (length tracks) 32)))
          (let ((song (make-song :tempo (third data) :beats (fourth data)
                                 :master-volume master)))
            (dolist (track tracks)
              (vector-push-extend (load-track track (song-beats song) version)
                                  (song-tracks song)))
            song))))))
