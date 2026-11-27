(defpackage #:%lui.tests.daw-audio
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
    #:make-song #:make-track #:add-note #:song-tracks #:song-master-volume
    #:track-volume #:track-distortion #:track-cutoff #:track-resonance
    #:track-reverb #:track-notes #:note-start #:note-duration #:render-wav
    #:save-song #:load-song #:make-effect-state #:configure-effects #:effect-sample)
  (:import-from #:%lui.example.daw-audio
    #:prepare-player #:mix-block #:player-sent #:player-device #:active-p)
  (:export #:run-tests))
(in-package #:%lui.tests.daw-audio)

(defun tone-song ()
  "Two equal-amplitude tones provide independently measurable mixer voices."
  (let ((song (make-song :beats 4 :tempo 240)))
    (dolist (pitch '(69 81))
      (let ((track (make-track :volume 0.5)))
        (add-note track pitch 0 4 127)
        (vector-push-extend track (song-tracks song))))
    song))

(defun energy (samples)
  "Mean-square energy, independent of PCM normalization or peak phase."
  (/ (loop :for sample :across samples :sum (* sample sample)) (length samples)))

(defun test-live-gains ()
  "Track and master changes affect later blocks without replacing the player."
  (let* ((song (tone-song))
         (player (prepare-player song 0 4 nil nil)))
    (mix-block player song 4410)
    (let ((original (energy (mix-block player song 4410))))
      (setf (track-volume (aref (song-tracks song) 0)) 0)
      (mix-block player song 4410)
      (assert (< (abs (- (/ (energy (mix-block player song 4410)) original) 0.5))
                 0.001))
      (setf (song-master-volume song) 0.5)
      (mix-block player song 4410)
      (assert (< (abs (- (/ (energy (mix-block player song 4410)) original) 0.125))
                 0.001))
      (setf (song-master-volume song) 0)
      (mix-block player song 4410)
      (assert (every #'zerop (mix-block player song 4410)))
      (assert (= 35280 (player-sent player))))))

(defun effect-tone (track frequency)
  "Measure a configured effect after its startup transient."
  (let ((state (make-effect-state))
        (output (make-array 4410 :element-type 'single-float)))
    (configure-effects state track)
    (dotimes (i 8820)
      (let ((sample (effect-sample state (* 0.1 (sin (* 2 pi frequency (/ i 44100)))))))
        (when (>= i 4410) (setf (aref output (- i 4410)) sample))))
    output))

(defun test-effects ()
  "Verify cutoff attenuation, resonant emphasis, distortion and a decaying tail."
  (let ((track (make-track)))
    (let ((dry (energy (effect-tone track 8000))))
      (setf (track-cutoff track) 500)
      (assert (< (energy (effect-tone track 8000)) (* dry 0.01))))
    (setf (track-cutoff track) 1000)
    (let ((flat (energy (effect-tone track 1000))))
      (setf (track-resonance track) 0.5)
      (assert (> (energy (effect-tone track 1000)) (* flat 4))))
    (setf (track-cutoff track) 20000 (track-distortion track) 0.8)
    (let ((state (make-effect-state)))
      (configure-effects state track)
      (assert (> (abs (- (effect-sample state 0.1) 0.1)) 0.01)))
    (setf (track-distortion track) 0 (track-reverb track) 0.8)
    (let ((state (make-effect-state))
          (tail 0.0)
          (late 0.0))
      (configure-effects state track)
      (effect-sample state 1.0)
      (dotimes (i 44100)
        (let ((value (abs (effect-sample state 0.0))))
          (when (< i 10000) (incf tail value))
          (when (> i 34000) (incf late value))))
      (assert (> tail 0.1))
      (assert (< late (* tail 0.01))))))

(defun test-live-metronome ()
  "Mix the click at a nonzero source offset and apply the master gain."
  (let* ((song (make-song :beats 4 :tempo 240))
         (player (prepare-player song 1 4 nil t)))
    (assert (plusp (energy (mix-block player song 4410))))
    (setf (song-master-volume song) 0)
    (mix-block player song 4410)
    (assert (every #'zerop (mix-block player song 4410)))))

(defun test-mix-ui ()
  "Route live slider input while the same real SDL dummy device keeps playing."
  (let* ((song (tone-song))
         (session (%lui.example.daw-state:make-session :song song :cycle-p t
                                                      :cycle-end 4))
         (context (%lui.tests.support:make-test-context)))
    (setf (%lui.frame:context-text-mode-p context) nil)
    (unwind-protect
         (progn
           (%lui.example.daw-demo:play-song session)
           (lui:with-frame (context 1200 880) (%lui.example.daw-demo:draw session))
           (let* ((player (%lui.example.daw-state:session-player session))
                  (device (player-device player)))
             (dolist (spec '((:track-volume 0.25) (:master-volume 0.4)))
               (lui:with-frame
                   (context 1200 880 :events
                            (list (%lui.frame:make-event
                                   :kind :change :id (lui:widget-id (first spec) context)
                                   :value (second spec))))
                 (%lui.example.daw-demo:draw session)))
             (assert (= 0.25 (track-volume (aref (song-tracks song) 0))))
             (assert (< (abs (- 0.4 (song-master-volume song))) 0.00001))
             (assert (eq player (%lui.example.daw-state:session-player session)))
             (assert (= device (player-device player)))
             (assert (active-p player))
             (setf (%lui.example.daw-state:session-effects-p session) t)
             (lui:with-frame (context 1200 880)
               (%lui.example.daw-demo:draw session))
             (lui:with-frame
                 (context 1200 880 :events
                          (list (%lui.frame:make-event
                                 :kind :change :id (lui:widget-id :reverb context)
                                 :value 0.5)))
               (%lui.example.daw-demo:draw session))
             (assert (= 0.5 (track-reverb (aref (song-tracks song) 0))))
             (assert (= device (player-device player)))
             (%lui.example.daw-demo:stop-player session)
             (assert (not (active-p player)))
             (%lui.example.daw-state:undo-edit session)
             (%lui.example.daw-state:undo-edit session)
             (assert (= 1 (song-master-volume
                            (%lui.example.daw-state:session-song session))))))
      (%lui.example.daw-demo:close-session session))))

(defun test-effect-persistence-and-export ()
  "Persist new controls, import old files, and preserve gain in PCM exports."
  (let* ((song (tone-song))
         (track (aref (song-tracks song) 0)))
    (setf (song-master-volume song) 0.5
          (track-distortion track) 0.2 (track-cutoff track) 1500
          (track-resonance track) 0.4 (track-reverb track) 0.3)
    (save-song song "build/daw-effects.lisp")
    (let* ((copy (load-song "build/daw-effects.lisp"))
           (track (aref (song-tracks copy) 0)))
      (assert (= 0.5 (song-master-volume copy)))
      (assert (= 0.2 (track-distortion track)))
      (assert (= 1500 (track-cutoff track)))
      (assert (= 0.4 (track-resonance track)))
      (assert (= 0.3 (track-reverb track))))
    (render-wav song "build/daw-half.wav")
    (setf (song-master-volume song) 1)
    (render-wav song "build/daw-full.wav")
    (let ((half (%lui.tests.daw:read-pcm "build/daw-half.wav" 44))
          (full (%lui.tests.daw:read-pcm "build/daw-full.wav" 44)))
      (assert (plusp (energy full)))
      (loop :for a :across half :for b :across full
            :do (assert (<= (abs (- (* 2 a) b)) 1))))
    (setf (song-master-volume song) 0)
    (render-wav song "build/daw-zero.wav")
    (assert (every #'zerop (%lui.tests.daw:read-pcm "build/daw-zero.wav" 44)))
    (with-open-file (out "build/daw-v1.lisp" :direction :output :if-exists :supersede)
      (write '(:lui-daw 1 120 4 (("Old" :sine 0.7 nil nil ((60 0 1 100)))))
             :stream out))
    (let ((old (load-song "build/daw-v1.lisp")))
      (assert (= 1 (song-master-volume old)))
      (assert (= 0 (track-reverb (aref (song-tracks old) 0)))))))

(defun test-drum-editor ()
  "Toggle exact onsets, preserve long hats, undo, and save final-bar hits."
  (let* ((song (make-song :beats 4))
         (track (make-track :wave :drums))
         (session (%lui.example.daw-state:make-session :song song)))
    (vector-push-extend track (song-tracks song))
    (%lui.example.daw-drums:basic-beat session)
    (assert (= 14 (length (track-notes track))))
    (%lui.example.daw-drums:toggle-step session 46 14)
    (%lui.example.daw-drums:toggle-step session 46 15)
    (assert (= 16 (length (track-notes track))))
    (assert (every (lambda (note) (<= (+ (note-start note) (note-duration note)) 4))
                   (track-notes track)))
    (save-song song "build/daw-drums.lisp")
    (assert (= 16 (length (track-notes (aref (song-tracks
                                             (load-song "build/daw-drums.lisp")) 0)))))
    (render-wav song "build/daw-drums.wav")
    (assert (> (energy (%lui.tests.daw:read-pcm "build/daw-drums.wav" 44)) 100))
    (%lui.example.daw-drums:toggle-step session 46 15)
    (assert (= 15 (length (track-notes track))))
    (%lui.example.daw-state:undo-edit session)
    (assert (= 16 (length (track-notes (%lui.example.daw-state:current-track session)))))))

(defun test-drum-layout ()
  "Route Add Drums and Basic Beat and fit the expanded editor at small widths."
  (let* ((font (lui.font:open-font))
         (renderer (lui.draw:%make-renderer :font font))
         (context (%lui.frame:make-context
                   :measure (lambda (widget width)
                              (lui.draw:%measure-widget renderer widget width))))
         (session (%lui.example.daw-state:make-session))
         (lui:*unit* 8))
    (unwind-protect
         (progn
           (lui:with-frame (context 1200 1400)
             (%lui.example.daw-demo:draw session))
           (lui:with-frame
               (context 1200 1400 :events
                        (list (%lui.frame:make-event
                               :kind :activate :id (lui:widget-id :add-drums context))))
             (%lui.example.daw-demo:draw session))
           (assert (%lui.example.daw-drums:drum-track-p session))
           (lui:with-frame
               (context 1200 1400 :events
                        (list (%lui.frame:make-event
                               :kind :activate :id (lui:widget-id :basic-beat context))))
             (%lui.example.daw-demo:draw session))
           (assert (= 14 (length (track-notes
                                  (%lui.example.daw-state:current-track session)))))
           (setf (%lui.example.daw-state:session-effects-p session) t)
           (dolist (width '(320 640 1200))
             (lui:with-frame (context width 480)
               (%lui.example.daw-demo:draw session))
             (%lui.layout:walk-elements
              (%lui.frame:context-root context)
              (lambda (node)
                (let ((box (%lui.layout:element-box node)))
                  (assert (<= (+ (lui:box-x box) (lui:box-width box))
                              (+ width 0.01))))))))
      (lui.font:close-font font))))

(defun test-live-cycle-exit ()
  "Cycle can be disabled through its live checkbox and finish at the song end."
  (let* ((session (%lui.example.daw-state:make-session :song (tone-song)
                                                      :cycle-p t :cycle-end 1))
         (context (%lui.tests.support:make-test-context)))
    (unwind-protect
         (progn
           (%lui.example.daw-demo:play-song session)
           (dotimes (i 15)
             (sleep 0.03)
             (lui:with-frame (context 1200 880)
               (%lui.example.daw-demo:draw session)))
           (let* ((player (%lui.example.daw-state:session-player session))
                  (device (player-device player)))
             (assert (> (player-sent player) 11025))
             (lui:with-frame
                 (context 1200 880 :events
                          (list (%lui.frame:make-event
                                 :kind :change :value nil
                                 :id (lui:widget-id :cycle context))))
               (%lui.example.daw-demo:draw session))
             (assert (not (%lui.example.daw-state:session-cycle-p session)))
             (assert (eq player (%lui.example.daw-state:session-player session)))
             (assert (= device (player-device player)))
             (loop :repeat 100 :while (%lui.example.daw-state:playing-p session)
                   :do (sleep 0.02) (%lui.example.daw-demo:update-transport session))
             (assert (not (%lui.example.daw-state:playing-p session)))
             (assert (= 4 (%lui.example.daw-state:session-playhead session)))))
      (%lui.example.daw-demo:close-session session))))

(defun test-editor-close-and-removal ()
  "Close/reopen the editor and confirm or cancel an undoable track deletion."
  (let* ((session (%lui.tests.daw:make-editor-session))
         (context (%lui.tests.support:make-test-context))
         (%lui.frame:*context* context)
         (target (aref (song-tracks (%lui.example.daw-state:session-song session)) 1)))
    (setf (%lui.frame:context-text-mode-p context) nil)
    (lui:with-frame (context 1200 880) (%lui.example.daw-demo:draw session))
    (lui:with-frame
        (context 1200 880 :events
                 (list (%lui.frame:make-event
                        :kind :activate :id (lui:widget-id :close-editor context))))
      (%lui.example.daw-demo:draw session))
    (lui:with-frame (context 1200 880) (%lui.example.daw-demo:draw session))
    (assert (not (%lui.example.daw-state:session-editor-p session)))
    (%lui.layout:walk-elements
     (%lui.frame:context-root context)
     (lambda (node)
       (assert (not (eq :piano-roll (lui:widget-key (%lui.layout:element-id node)))))
       (when (eq :track-list (lui:widget-key (%lui.layout:element-id node)))
         (assert (> (lui:box-height (%lui.layout:element-box node)) 500)))))
    (%lui.example.daw-state:select-track session 1)
    (assert (not (%lui.example.daw-state:session-editor-p session)))
    (%lui.example.daw-roll:navigate-lane session 1 0)
    (assert (%lui.example.daw-state:session-editor-p session))
    (%lui.example.daw-demo:request-track-removal session target)
    (lui:with-frame (context 1200 880) (%lui.example.daw-demo:draw session))
    (assert (%lui.frame:context-modal context))
    (%lui.example.daw-demo:resolve-track-removal session :cancel)
    (assert (= 3 (length (song-tracks (%lui.example.daw-state:session-song session)))))
    (assert (not (%lui.example.daw-state:session-dirty-p session)))
    (%lui.example.daw-demo:request-track-removal session target)
    (%lui.example.daw-demo:resolve-track-removal session :confirm)
    (assert (= 2 (length (song-tracks (%lui.example.daw-state:session-song session)))))
    (assert (not (find target (song-tracks (%lui.example.daw-state:session-song session)))))
    (%lui.example.daw-state:undo-edit session)
    (assert (= 3 (length (song-tracks (%lui.example.daw-state:session-song session)))))))

(defun control-box (context key)
  "Find actual control geometry without bypassing pointer hit testing."
  (let ((box nil))
    (%lui.layout:walk-elements
     (%lui.frame:context-root context)
     (lambda (node)
       (when (equal key (lui:widget-key (%lui.layout:element-id node)))
         (setf box (%lui.layout:element-box node)))))
    (assert box)
    box))

(defun test-bar-pointer-navigation ()
  "Both editors change once on release and show the new bar in that frame."
  (dolist (wave '(:drums :sine))
    (let* ((session (%lui.example.daw-state:make-session))
           (context (%lui.tests.support:make-test-context))
           (caption (if (eq wave :drums) "Drums / Bar" "Bar")))
      (setf (%lui.frame:context-text-mode-p context) nil
            (%lui.example.daw-model:track-wave
             (%lui.example.daw-state:current-track session)) wave
            (%lui.example.daw-state:session-page session) 8)
      (labels ((frame (&optional events)
                 (lui:with-frame (context 1200 1400 :events events)
                   (%lui.example.daw-demo:draw session)))
               (check (page)
                 (assert (= page (%lui.example.daw-state:session-page session)))
                 (assert (%lui.tests.support:visible-text-p
                          context (format nil "~A ~D" caption (1+ page)))))
               (pointer (key kind &optional outside)
                 (let ((box (control-box context key)))
                   (frame (list (%lui.frame:make-event
                                 :kind kind :button :primary
                                 :buttons (if (eq kind :release) 0 1)
                                 :x (if outside -10
                                        (+ (lui:box-x box) (/ (lui:box-width box) 2)))
                                 :y (+ (lui:box-y box) (/ (lui:box-height box) 2))))))))
        (frame)
        (pointer :next-bar :press)
        (check 8)
        (frame)
        (check 8)
        (pointer :next-bar :release)
        (check 9)
        (frame)
        (check 9)
        (pointer :previous-bar :press)
        (check 9)
        (pointer :previous-bar :release)
        (check 8)
        ;; A stray second release and a canceled click must do nothing.
        (pointer :previous-bar :release)
        (check 8)
        (pointer :previous-bar :press)
        (pointer :previous-bar :release t)
        (check 8)
        (setf (%lui.example.daw-state:session-page session) 0)
        (frame)
        (pointer :previous-bar :press)
        (pointer :previous-bar :release)
        (check 0)))))

(defun test-drum-spacing ()
  "Wrapped step rows retain equal horizontal and vertical inter-control gaps."
  (let ((session (%lui.example.daw-state:make-session))
        (context (%lui.tests.support:make-test-context))
        (lui:*unit* 8))
    (setf (%lui.frame:context-text-mode-p context) nil)
    (lui:with-frame (context 640 1000)
      (lui:column (:width (lui:grow) :gap (lui:units 0.5f0))
        (%lui.example.daw-drums:draw session)))
    (let* ((first (control-box context '(:drum 36 0)))
           (second (control-box context '(:drum 36 1)))
           (below (control-box context '(:drum 36 8)))
           (horizontal (- (lui:box-x second)
                          (+ (lui:box-x first) (lui:box-width first))))
           (vertical (- (lui:box-y below)
                        (+ (lui:box-y first) (lui:box-height first)))))
      (assert (plusp horizontal))
      (assert (= horizontal vertical)))))

(defun run-tests ()
  "Exercise live mixer controls, DSP, persistence and drum sequencing."
  (test-live-gains)
  (test-live-metronome)
  (test-effects)
  (test-mix-ui)
  (test-effect-persistence-and-export)
  (test-drum-editor)
  (test-drum-layout)
  (test-live-cycle-exit)
  (test-editor-close-and-removal)
  (test-bar-pointer-navigation)
  (test-drum-spacing)
  (format t "Live gain, DSP, export, versioned projects and drum steps passed.~%"))
