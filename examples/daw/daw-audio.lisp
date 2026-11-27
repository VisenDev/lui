(defpackage #:%lui.example.daw-audio
  (:use #:cl)
  (:import-from #:%lui.example.daw-model
                #:track #:song #:song-tracks #:song-tempo #:song-master-volume
                #:track-volume #:audible-p #:render-dry-track #:make-effect-state
                #:configure-effects #:effect-sample #:mix-metronome)
  (:export #:player #:open-player #:close-player #:pump #:position-beat
           #:active-p #:mix-block #:player-sent #:player-device
           #:player-frames #:player-rate #:audio-error #:prepare-player #:set-cycle))
(in-package #:%lui.example.daw-audio)

(define-condition audio-error (error)
  ((message :initarg :message :reader audio-error-message))
  (:report (lambda (condition stream)
             (write-string (audio-error-message condition) stream)))
  (:documentation "SDL audio library loading, device opening or queuing failed."))

(cffi:define-foreign-library sdl-audio
    (:darwin (:or "libSDL2.dylib" (:framework "SDL2")))
  (:windows "SDL2.dll")
  (:unix (:or "libSDL2-2.0.so.0" "libSDL2.so")))

(defvar *library* nil "Lazily loaded SDL2 shared library.")

(cffi:defcstruct audio-spec
    (frequency :int) (format :uint16) (channels :uint8) (silence :uint8)
    (samples :uint16) (padding :uint16) (size :uint32)
    (callback :pointer) (userdata :pointer))
(cffi:defcfun ("SDL_SetMainReady" main-ready) :void)
(cffi:defcfun ("SDL_InitSubSystem" init-audio) :int (flags :uint32))
(cffi:defcfun ("SDL_QuitSubSystem" quit-audio) :void (flags :uint32))
(cffi:defcfun ("SDL_GetError" last-error) :string)
(cffi:defcfun ("SDL_OpenAudioDevice" open-device) :uint32
  (name :pointer) (capture :int) (desired :pointer) (obtained :pointer)
  (changes :int))
(cffi:defcfun ("SDL_CloseAudioDevice" close-device) :void (device :uint32))
(cffi:defcfun ("SDL_PauseAudioDevice" pause-device) :void
  (device :uint32) (pause :int))
(cffi:defcfun ("SDL_GetQueuedAudioSize" queued-size) :uint32 (device :uint32))
(cffi:defcfun ("SDL_QueueAudio" queue-audio) :int
  (device :uint32) (data :pointer) (length :uint32))

(defstruct stem
  (track nil :type (or null track))
  (samples (make-array 0 :element-type 'single-float)
           :type (simple-array single-float (*)))
  (effects (make-effect-state) :type %lui.example.daw-model:effect-state)
  (gain 0.0f0 :type single-float))

(defstruct player
  (device 0 :type (unsigned-byte 32))
  (rate 44100 :type fixnum)
  (frames 0 :type integer)
  (sent 0 :type integer)
  (cursor 0 :type integer)
  (range-start 0 :type integer)
  (range-end 0 :type integer)
  (history nil :type list)
  (drained-at nil :type (or null integer))
  (start 0 :type real)
  (tempo 120 :type real)
  (loop-p nil :type boolean)
  (master 1.0f0 :type single-float)
  (stems (make-array 0 :element-type 'stem) :type (vector stem))
  (click (make-array 0 :element-type 'single-float)
         :type (simple-array single-float (*))))

(defun prepare-player (song start end loop-p metronome)
  "Snapshot note synthesis; keep source track references for live mix controls."
  (let* ((rate 44100)
         (frames (ceiling (* rate (%lui.example.daw-model:song-beats song)
                             (/ 60 (song-tempo song)))))
         (player (make-player :frames frames :start start :tempo (song-tempo song)
                              :cursor (round (* rate start (/ 60 (song-tempo song))))
                              :range-start (round (* rate start (/ 60 (song-tempo song))))
                              :range-end (round (* rate end (/ 60 (song-tempo song))))
                              :loop-p loop-p
                              :master (coerce (song-master-volume song) 'single-float)
                              :stems (make-array (length (song-tracks song))
                                                 :element-type 'stem :initial-element (make-stem)))))
    (assert (plusp frames))
    (loop :for track :across (song-tracks song) :for i :from 0
          :do (setf (aref (player-stems player) i)
                    (make-stem :track track :effects (make-effect-state rate)
                               :gain (coerce (if (audible-p song track)
                                                 (track-volume track) 0)
                                             'single-float)
                               :samples (render-dry-track track (song-tempo song)
                                                          frames rate 0))))
    (when metronome
      (setf (player-click player)
            (make-array frames :element-type 'single-float :initial-element 0.0f0))
      (mix-metronome (player-click player) (song-tempo song) rate 0
                     (%lui.example.daw-model:song-beats song)))
    player))

(defun mix-block (player song count)
  "Mix upcoming frames with live gains/effects; ramp gain changes over one block."
  (let ((result (make-array count :element-type 'single-float :initial-element 0.0f0))
        (offset (player-cursor player))
        (master (song-master-volume song)))
    (loop :for stem :across (player-stems player)
          :for track := (stem-track stem)
          :for gain := (if (and (find track (song-tracks song))
                                (audible-p song track)) (track-volume track) 0)
          :do (configure-effects (stem-effects stem) track)
          (dotimes (i count)
            (let ((value (effect-sample
                          (stem-effects stem)
                          (aref (stem-samples stem) (+ offset i))))
                  (level (+ (stem-gain stem)
                            (* (/ (1+ i) count) (- gain (stem-gain stem))))))
              (incf (aref result i) (coerce (* value level) 'single-float))))
          (setf (stem-gain stem) (coerce gain 'single-float)))
    (dotimes (i count)
      (let ((click (if (plusp (length (player-click player)))
                        (aref (player-click player) (+ offset i)) 0))
             (level (+ (player-master player)
                       (* (/ (1+ i) count) (- master (player-master player))))))
        (setf (aref result i)
              (coerce (max -1 (min 1 (* level (+ click (aref result i)))))
                      'single-float))))
    (setf (player-master player) (coerce master 'single-float))
    (setf (player-history player)
          (nconc (player-history player) (list (cons (player-sent player) offset))))
    (incf (player-sent player) count)
    (incf (player-cursor player) count)
    result))

(defun active-p (player)
  "Return whether this player still owns a live SDL device."
  (plusp (player-device player)))

(defun close-player (player)
  "Close this device and balance its audio-subsystem reference exactly once."
  (declare (values))
  (when (active-p player)
    (close-device (player-device player))
    (setf (player-device player) 0)
    (quit-audio #x10))
  (values))

(defun position-beat (player)
  "Map consumed frames through queued timeline segments, including loop changes."
  (let* ((queued (if (active-p player) (/ (queued-size (player-device player)) 4) 0))
         (played (max 0 (- (player-sent player) queued))))
    (loop :while (and (cdr (player-history player))
                      (<= (car (second (player-history player))) played))
          :do (pop (player-history player)))
    (let* ((segment (first (player-history player)))
           (frame (if segment (+ (cdr segment) (- played (car segment)))
                      (player-cursor player))))
      (* (/ frame (player-rate player)) (/ (player-tempo player) 60)))))

(defun set-cycle (player enabled start end)
  "Change future queued playback without replacing the device or rewinding it."
  (declare (values))
  (setf (player-loop-p player) enabled
        (player-range-start player)
        (round (* start (player-rate player) (/ 60 (player-tempo player))))
        (player-range-end player)
        (if enabled (round (* end (player-rate player) (/ 60 (player-tempo player))))
            (player-frames player))
        (player-drained-at player) nil)
  (when (and enabled
             (not (<= (player-range-start player) (player-cursor player)
                      (1- (player-range-end player)))))
    (setf (player-cursor player) (player-range-start player)))
  (values))

(defun pump (player song)
  "Keep roughly 93 ms queued; return NIL once a nonlooping range has drained."
  (when (active-p player)
    (position-beat player)
    (loop :repeat 4
          :while (and (< (queued-size (player-device player)) (* 4096 4))
                      (or (player-loop-p player)
                          (< (player-cursor player) (player-range-end player))))
          :do (when (>= (player-cursor player) (player-range-end player))
                (setf (player-cursor player) (player-range-start player)))
          (let* ((count (min 1024 (- (player-range-end player)
                                     (player-cursor player))))
                 (samples (mix-block player song count)))
            (cffi:with-foreign-object (buffer :float count)
              (dotimes (i count)
                (setf (cffi:mem-aref buffer :float i) (aref samples i)))
              (when (minusp (queue-audio (player-device player) buffer (* count 4)))
                (error 'audio-error :message (last-error))))))
    (if (or (player-loop-p player)
            (< (player-cursor player) (player-range-end player))
            (plusp (queued-size (player-device player))))
        t
        ;; Let the last hardware buffer finish before closing the device.
        (let ((now (get-internal-real-time)))
          (unless (player-drained-at player)
            (setf (player-drained-at player) now))
          (< (/ (- now (player-drained-at player)) internal-time-units-per-second)
             (/ 1024 (player-rate player)))))))

(defun open-player (song start end loop-p metronome)
  "Render dry stems and open a lazily loaded SDL2 queue without Lisp callbacks."
  (let ((player (prepare-player song start end loop-p metronome))
        (initialized nil)
        (success nil))
    (unwind-protect
         (progn
           (handler-case
               (or *library*
                   (setf *library*
                         (cffi:load-foreign-library
                          (or (uiop:getenv "LUI_DAW_AUDIO_LIBRARY") 'sdl-audio))))
             (error (condition)
               (error 'audio-error :message (format nil "Install SDL2 audio: ~A" condition))))
           (main-ready)
           (when (minusp (init-audio #x10))
             (error 'audio-error :message (last-error)))
           (setf initialized t)
           (cffi:with-foreign-object (spec '(:struct audio-spec))
             (dotimes (i (cffi:foreign-type-size '(:struct audio-spec)))
               (setf (cffi:mem-aref spec :uint8 i) 0))
             (cffi:with-foreign-slots
                 ((frequency format channels samples) spec (:struct audio-spec))
               (setf frequency (player-rate player)
                     format #+big-endian #x9120 #-big-endian #x8120
                     channels 1 samples 1024))
             (setf (player-device player)
                   (open-device (cffi:null-pointer) 0 spec (cffi:null-pointer) 0)))
           (unless (active-p player)
             (error 'audio-error :message (last-error)))
           (pump player song)
           (pause-device (player-device player) 0)
           (setf success t)
           player)
      (unless success
        (if (active-p player) (close-player player)
            (when initialized (quit-audio #x10)))))))
