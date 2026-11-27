(defpackage #:%lui.tests.daw
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
    #:make-song #:make-track #:demo-song #:song-tracks #:song-tempo
    #:track-notes #:track-muted-p #:track-solo-p #:track-volume #:audible-p
    #:note-pitch #:note-start #:note-duration #:note-velocity
    #:add-note #:note-at #:make-recorder #:midi-event #:finish-recording
    #:render-wav #:save-song #:load-song)
  (:export #:run-tests #:test-native-midi))
(in-package #:%lui.tests.daw)

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
  (let* ((song (demo-song))
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
  (let ((session (%lui.example.daw-demo:make-session))
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
  (let* ((session (%lui.example.daw-demo:make-session))
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
  (let ((session (%lui.example.daw-demo:make-session)))
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
  (let ((session (%lui.example.daw-demo:make-session))
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
    (let ((session (%lui.example.daw-demo:make-session
                     :song song :path "build/daw-test")))
      (unwind-protect
           (%lui.example.daw-demo:export-song session "mp3")
        (%lui.example.daw-demo:close-session session)))
    (setf (track-muted-p track) t)
    (render-wav song "build/daw-muted.wav")))

(defun test-playback ()
  "Exercise ffplay ownership and UI state with SDL's silent test audio sink."
  (let ((session (%lui.example.daw-demo:make-session))
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

(defun run-tests ()
  "Run DAW model, recording, public UI, persistence and audio integration checks."
  (test-midi)
  (test-model)
  (test-ui)
  (test-native-midi)
  (test-render)
  (test-playback)
  (test-audio)
  (format t "DAW model, MIDI, UI, project and export checks passed.~%"))
