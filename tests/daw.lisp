(defpackage #:%lui.tests.daw
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
    #:make-song #:make-track #:demo-song #:song-tracks #:song-tempo
    #:track-notes #:track-muted-p #:track-solo-p #:track-volume #:audible-p
    #:note-pitch #:note-start #:note-duration #:note-velocity
    #:add-note #:note-at #:make-recorder #:midi-event #:finish-recording
    #:render-wav #:save-song #:load-song)
  (:export #:run-tests #:test-native-midi #:make-editor-session #:editor-song))
(in-package #:%lui.tests.daw)

(defun editor-song ()
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

(defun make-editor-session (&rest options)
  "Use a small explicit editing fixture independently of the showcase music."
  (apply #'%lui.example.daw-state:make-session
         (if (member :song options) options
             (append options (list :song (editor-song))))))

(defun test-midi ()
  "Exercise channels, velocity-zero off, sustain, retrigger and stop cleanup."
  (let* ((track (make-track))
         (recorder (make-recorder :track track :tempo 120 :beats 16)))
    (midi-event recorder 0 #x90 60 100)
    (midi-event recorder 0 #x91 60 80)
    (midi-event recorder 0.25 #x90 60 0)
    (assert (= 1 (length (track-notes track))))
    (assert (= 1/2 (note-duration (aref (track-notes track) 0))))
    (midi-event recorder 0.25 #xb1 64 127)
    (midi-event recorder 0.5 #x81 60 0)
    (assert (= 1 (length (track-notes track))))
    (midi-event recorder 1 #xb1 64 0)
    (assert (= 2 (note-duration (aref (track-notes track) 1))))
    (assert (= 80 (note-velocity (aref (track-notes track) 1))))
    (midi-event recorder 1 #x90 64 50)
    (midi-event recorder 1.25 #x90 64 60)
    (finish-recording recorder 1.75)
    (assert (= 4 (length (track-notes track))))
    (assert (= 1 (note-duration (aref (track-notes track) 3))))
    (midi-event recorder 7.9 #x90 70 100)
    (finish-recording recorder 10)
    (assert (= 16 (+ (note-start (aref (track-notes track) 4))
                     (note-duration (aref (track-notes track) 4)))))
    (midi-event recorder 9 #x90 70 100)
    (finish-recording recorder 10)
    (assert (= 5 (length (track-notes track))))))

(defun test-model ()
  "Check mixer precedence, project roundtrip, and disabled reader evaluation."
  (let* ((song (editor-song))
         (tracks (song-tracks song))
         (first (aref tracks 0))
         (second (aref tracks 1)))
    (assert (audible-p song first))
    (setf (track-solo-p second) t)
    (assert (not (audible-p song first)))
    (assert (audible-p song second))
    (setf (track-muted-p second) t)
    (assert (not (audible-p song second)))
    (save-song song "build/daw-test.lisp")
    (let ((loaded (load-song "build/daw-test.lisp")))
      (assert (= 3 (length (song-tracks loaded))))
      (assert (track-muted-p (aref (song-tracks loaded) 1)))
      (assert (track-solo-p (aref (song-tracks loaded) 1)))
      (assert (= 4 (length (track-notes (aref (song-tracks loaded) 0))))))
    (with-open-file (stream "build/daw-invalid.lisp" :direction :output
                                                      :if-exists :supersede)
      (write-line "#.(error \"Reader evaluated\")" stream))
    (assert (handler-case (progn (load-song "build/daw-invalid.lisp") nil)
              (reader-error () t)))))

(defun find-key (context key)
  "Find a public declared widget key for real activation routing."
  (let ((found nil))
    (%lui.layout:walk-elements
     (%lui.frame:context-root context)
     (lambda (node)
       (when (equal key (lui:widget-key (%lui.layout:element-id node)))
         (setf found (%lui.layout:element-id node)))))
    (assert found)
    found))

(defun test-ui ()
  "Create/select/delete through piano-roll controls and add a mixer track."
  (let ((session (make-editor-session))
        (context (%lui.tests.support:make-test-context)))
    (labels ((frame (&optional events)
               (lui:with-frame (context 110 65 :events events)
                 (%lui.example.daw-demo:draw session)))
             (activate (key)
               (frame (list (%lui.frame:make-event
                             :kind :activate :id (find-key context key))))
               (frame)))
      (frame)
      (assert (%lui.tests.support:visible-text-p context "EDITOR: Keys"))
      (activate '(61 0))
      (let ((note (%lui.example.daw-demo:session-selected session)))
        (assert note)
        (assert (= 61 (note-pitch note)))
        (assert (= 1/2 (note-duration note))))
      (activate :delete-note)
      (assert (null (%lui.example.daw-demo:session-selected session)))
      (assert (null (note-at (aref (song-tracks
                         (%lui.example.daw-demo:session-song session)) 0) 61 0)))
      (activate :add-track)
      (assert (= 4 (length (song-tracks
                            (%lui.example.daw-demo:session-song session))))))))

(defun test-midi-close-failure ()
  "A failed final read must release MIDI and preserve Save/Discard/Cancel."
  (let* ((session (make-editor-session))
         (context (%lui.tests.support:make-test-context))
         (%lui.frame:*context* context))
    (setf (%lui.frame:context-on-close context)
          (lambda () (%lui.example.daw-demo:request-session-close session)))
    (unwind-protect
         (progn
           (add-note (aref (song-tracks
                            (%lui.example.daw-demo:session-song session)) 0)
                     79 3 1/2)
           (%lui.example.daw-demo:start-recording session)
           (cffi:foreign-funcall "lui_test_fail_read" :void)
           (assert (not (%lui.frame:accept-close-p context t)))
           (assert (eq :close (%lui.example.daw-state:session-pending session)))
           (assert (%lui.example.daw-state:session-dirty-p session))
           (assert (null (%lui.example.daw-demo:session-midi session)))
           (assert (null (%lui.example.daw-demo:session-player session)))
           (assert (zerop (cffi:foreign-funcall "lui_test_live_inputs" :int)))
           (assert (search "Native MIDI failed"
                           (%lui.example.daw-demo:session-status session)))
           (lui:with-frame (context 110 65)
             (%lui.example.daw-demo:draw session))
           (assert (%lui.frame:context-modal context))
           (%lui.example.daw-demo:resolve-close session :cancel)
           (assert (%lui.example.daw-state:session-dirty-p session))
           (assert (not (%lui.frame:accept-close-p context t)))
           (setf (%lui.example.daw-demo:session-path session)
                 "build/daw-midi-close-test")
           (%lui.example.daw-demo:resolve-close session :confirm)
           (assert (%lui.frame:accept-close-p context))
           (let ((loaded (load-song "build/daw-midi-close-test.lisp")))
             (assert (= 1/2 (note-duration
                             (note-at (aref (song-tracks loaded) 0) 79 3))))))
      (%lui.example.daw-demo:close-session session))))

(defun test-native-midi ()
  "Run native CFFI input against a deterministic C ABI double, including stop."
  (assert (equalp #("LUI native test keyboard")
                  (%lui.example.daw-midi:list-inputs)))
  (assert (handler-case (progn (%lui.example.daw-midi:open-input 1) nil)
            (%lui.example.daw-midi:midi-error () t)))
  (assert (zerop (cffi:foreign-funcall "lui_test_live_inputs" :int)))
  (test-midi-close-failure)
  (let ((session (make-editor-session)))
    (unwind-protect
         (progn
           (%lui.example.daw-demo:start-recording session)
           (sleep 0.15)
           (let ((context (%lui.tests.support:make-test-context)))
             (lui:with-frame (context 110 65)
               (%lui.example.daw-demo:draw session)))
           (%lui.example.daw-demo:drain-midi session)
           (%lui.example.daw-demo:stop-recording session)
           (assert (null (%lui.example.daw-demo:session-midi session)))
           (let ((notes (track-notes (aref (song-tracks
                            (%lui.example.daw-demo:session-song session)) 0))))
             (assert (= 5 (length notes)))
             (assert (= 72 (note-pitch (aref notes 4))))
             (assert (= 1/2 (note-duration (aref notes 4))))))
      (%lui.example.daw-demo:close-session session)))
  (assert (zerop (cffi:foreign-funcall "lui_test_live_inputs" :int)))
  (let ((session (make-editor-session))
        (context (%lui.tests.support:make-test-context)))
    (unwind-protect
         (progn
           (%lui.example.daw-demo:start-recording session)
           (cffi:foreign-funcall "lui_test_fail_read" :void)
           (lui:with-frame (context 110 65)
             (%lui.example.daw-demo:draw session))
           (assert (null (%lui.example.daw-demo:session-midi session)))
           (assert (search "Native MIDI failed"
                           (%lui.example.daw-demo:session-status session))))
      (%lui.example.daw-demo:close-session session)))
  (assert (zerop (cffi:foreign-funcall "lui_test_live_inputs" :int))))

(defun test-render ()
  "Produce fixtures for independent WAV/MP3 decoding and timing checks."
  (let* ((song (make-song :beats 4 :tempo 120))
         (track (make-track)))
    (vector-push-extend track (song-tracks song))
    (add-note track 69 1 1 100)
    (render-wav song "build/daw-test.wav")
    (let ((session (make-editor-session
                     :song song :path "build/daw-test")))
      (unwind-protect
           (%lui.example.daw-demo:export-song session "mp3")
        (%lui.example.daw-demo:close-session session)))
    (setf (track-muted-p track) t)
    (render-wav song "build/daw-muted.wav")))

(defun test-playback ()
  "Exercise ffplay ownership and UI state with SDL's silent test audio sink."
  (let ((session (make-editor-session))
        (context (%lui.tests.support:make-test-context))
        (path nil))
    (unwind-protect
         (progn
           (%lui.example.daw-demo:play-song session)
           (setf path (%lui.example.daw-demo:session-scratch session))
           (sleep 0.2)
           (assert (uiop:process-alive-p
                    (%lui.example.daw-demo:session-player session)))
           (lui:with-frame (context 110 65)
             (%lui.example.daw-demo:draw session)))
      (%lui.example.daw-demo:close-session session))
    (assert (null (%lui.example.daw-demo:session-player session)))
    (assert (not (probe-file path)))))

(defun read-pcm (path &optional (skip 0))
  "Read little-endian signed PCM16 without using the demo's writer."
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (file-position stream skip)
    (let ((samples (make-array (/ (- (file-length stream) skip) 2)
                              :element-type '(signed-byte 16))))
      (dotimes (index (length samples))
        (let ((word (+ (read-byte stream) (* 256 (read-byte stream)))))
          (setf (aref samples index) (if (>= word 32768) (- word 65536) word))))
      samples)))

(defun test-audio ()
  "Independently check WAV timing/pitch/mute and decode a genuine MP3."
  (let ((samples (read-pcm "build/daw-test.wav" 44)))
    (assert (= 88200 (length samples)))
    (assert (every #'zerop (subseq samples 0 22050)))
    (assert (every #'zerop (subseq samples 44100)))
    (assert (> (reduce #'max samples) 1000))
    (assert (< (reduce #'max samples :key #'abs) 32767))
    (let ((crossings (loop :for index :from 24001 :below 40000
                           :count (and (<= (aref samples (1- index)) 0)
                                       (> (aref samples index) 0)))))
      (assert (< (abs (- (* crossings (/ 44100 16000)) 440)) 4))))
  (assert (every #'zerop (read-pcm "build/daw-muted.wav" 44)))
  (let ((codec (uiop:run-program
                '("ffprobe" "-v" "error" "-select_streams" "a:0"
                  "-show_entries" "stream=codec_name" "-of"
                  "default=noprint_wrappers=1:nokey=1" "build/daw-test.mp3")
                :output :string)))
    (assert (string= "mp3" (string-trim '(#\Return #\Newline) codec))))
  (uiop:run-program '("ffmpeg" "-v" "error" "-y" "-i" "build/daw-test.mp3"
                      "-f" "s16le" "build/daw-decoded.pcm"))
  (let ((decoded (read-pcm "build/daw-decoded.pcm")))
    (assert (< (abs (- (length decoded) 88200)) 4410))
    (assert (> (reduce #'max decoded :key #'abs) 1000)))
  (format t "WAV timing, 440 Hz pitch, mute and actual MP3 decode passed.~%"))

(defun test-showcase-song ()
  "Check the real startup composition, cadence, variation and file roundtrip."
  (let* ((song (demo-song))
         (tracks (song-tracks song))
         (bass (aref tracks 1))
         (melody (aref tracks 2)))
    (assert (= 64 (%lui.example.daw-model:song-beats song)))
    (assert (= 108 (song-tempo song)))
    (assert (= 3 (length tracks)))
    (loop :for track :across tracks
          :do (assert (plusp (length (track-notes track))))
              (loop :for note :across (track-notes track)
                    :do (assert (<= 0 (note-start note)))
                        (assert (plusp (note-duration note)))
                        (assert (<= (+ (note-start note) (note-duration note)) 64))))
    (loop :for root :across #(43 48 41 46 39 48 38 43)
          :for bar :from 0
          :do (assert (note-at bass root (* 4 bar)))
              (assert (note-at bass root (+ 32 (* 4 bar)))))
    (assert (> (count-if (lambda (note) (>= (note-start note) 32))
                         (track-notes melody))
               (count-if (lambda (note) (< (note-start note) 32))
                         (track-notes melody))))
    (assert (= 4 (note-duration (note-at melody 67 60))))
    (save-song song "build/daw-showcase.lisp")
    (let ((copy (load-song "build/daw-showcase.lisp")))
      (assert (= 64 (%lui.example.daw-model:song-beats copy)))
      (loop :for original :across tracks :for loaded :across (song-tracks copy)
            :do (assert (= (length (track-notes original))
                           (length (track-notes loaded))))
                (loop :for a :across (track-notes original)
                      :for b :across (track-notes loaded)
                      :do (dolist (reader (list #'note-pitch #'note-start
                                               #'note-duration #'note-velocity))
                            (assert (= (funcall reader a) (funcall reader b)))))))))

(defun run-tests ()
  "Run DAW model, recording, public UI, persistence and audio integration checks."
  (test-midi)
  (test-model)
  (test-showcase-song)
  (test-ui)
  (test-native-midi)
  (test-render)
  (test-playback)
  (test-audio)
  (format t "DAW model, MIDI, UI, project and export checks passed.~%"))
