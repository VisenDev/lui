(defpackage #:lui.docs
  (:use #:cl #:lui #:lui.layout #:lui.frame)
  (:export #:main #:make-docs #:*entries*))
(in-package #:lui.docs)

(defvar *entries* nil
  "Generated public API entries, loaded before constructing the browser.")

(defparameter *guides*
  '((:start "Getting started"
     "LUI draws the same immediate-mode interface on native windows, the browser, and a terminal. Load the backend you want, then pass a drawing function to lui:run."
     "(asdf:load-system \"lui/wayland\")
(let ((name \"Common Lisp\"))
  (lui:run
   (lambda ()
     (setf name (lui:text-field :name name))
     (when (lui:button :hello \"Say hello\")
       (format t \"Hello ~A!~%\" name)))))"
     "Other optional native systems include lui/x11, lui/win32, lui/cocoa, and lui/terminal. The browser backend is compiled with JSCL rather than loaded as an ASDF system. Core LUI has no dependencies. Native graphical backends use CFFI, zpb-ttf, and platform libraries. The raw terminal adds CFFI; plain terminal output remains dependency-free."
     "Use make demo for the gallery, make docs for this browser, and make test for the detected platform. Backend availability depends on which systems are loaded; an explicit :backend argument selects one.")
    (:frames "Frames and state"
     "Keep application state in ordinary lexical variables or structures. A drawing function declares the current interface on every frame; it does not create a persistent widget object."
     "(defun make-counter ()
  (let ((count 0))
    (lambda ()
      (lui:label (format nil \"Count: ~D\" count))
      (when (lui:button :increment \"Increment\")
        (incf count)))))"
     "Give interactive controls stable, unique IDs. Reuse an ID across frames for the same logical control; changing it creates fresh editing/focus state. Duplicate IDs in a frame are errors. Conditional declarations add or remove controls immediately."
     "lui.frame:frame-time returns this frame's clock snapshot. lui.frame:request-frame schedules another redraw, optionally after a delay in seconds. Prefer requesting a deadline for timers over a busy loop; terminal redraws can otherwise stay idle.")
    (:widgets "Controls and options"
     "Buttons return true when activated. Text fields, sliders, and checkboxes return their current value: assign it back to your model. Tabs, cells, and list items accept :selected-p for visible selection. Panels contain other declarations."
     "(lui:panel (lui:opt :padding (lui:units 1))
  (setf enabled (lui:checkbox :enabled enabled \"Enabled\"))
  (setf volume
        (lui:slider :volume volume
                    (lui:opt :minimum 0 :maximum 1)))
  (lui:button :save \"Save\"
              (lui:opt :disabled-p (not enabled))))"
     "Pass optional styling/layout settings in one explicit lui:opt form. An omitted option inherits the collection default; an explicit NIL remains an explicit value. Common settings include :width, :height, :padding, :foreground, :background, :font-size, and :disabled-p."
     "Canvas commands provide simple shared circles and rectangles. A custom :painter can draw through a native renderer, while :web-style customizes its DOM counterpart. Such extensions must supply equivalent behavior on each backend they support.")
    (:layout "Layout and scrolling"
     "Rows arrange children horizontally; columns arrange them vertically. A fixed size uses backend coordinates, grow distributes available space, and fit measures content. Use lui:units for spacing that adapts to terminal cells and graphical pixels."
     "(lui.frame:row (:width (lui.layout:grow)
                :gap (lui:units 1))
  (lui:panel (lui:opt :width (lui.layout:fixed (lui:units 24))
                       :height (lui.layout:grow) :scroll-p t)
    (lui:label \"Navigation\"))
  (lui:panel (lui:opt :width (lui.layout:grow)
                       :height (lui.layout:grow))
    (lui:label \"Content\")))"
     "Container :padding reserves an inner content area. :gap separates children; :align controls the main axis and :cross-align controls the other axis. :clip-p clips children to the padded content area. :scroll-p adds scrolling with the same clipping rules."
     "A scrolling viewport needs a bounded size. Nested scrollers pass wheel input to an ancestor when they cannot scroll further. lui.frame:previous-box exposes completed geometry; lui.frame:scroll-position and scroll-to support application-controlled navigation. Virtualize very large lists instead of declaring every row.")
    (:toolkits "Collections"
     "Glass, Motif, and Garnet expose the same public controls. Glass uses rounded translucent surfaces; Motif uses solid beveled controls; Garnet uses high-contrast square shapes, hard shadows, and bold monospace text. A window background remains opaque."
     "(lui:with-toolkit (:motif)
  (lui:button :ok \"OK\"))
(lui:with-toolkit (:garnet)
  (lui:label \"A different collection\"))"
     "lui:with-toolkit chooses defaults and control implementations for a lexical drawing scope. Nested scopes restore the previous collection. lui:current-toolkit returns the current name; lui:toolkit-defaults exposes its inherited options."
     "Custom collections register defaults, a parent, control overrides, and optional web styling. Use lui:define-collection or lui:register-toolkit; the API reference shows their exact signatures. Backend implementations may approximate optical effects differently: X11 and Wayland share the OpenGL renderer through GLX/EGL, while Cocoa uses whole-window material.")
    (:input "Input and inspection"
     "Tab and Shift-Tab move keyboard focus. Enter and Space activate a focused button, checkbox, or tab; Space inserts a space in an editor. Pointer clicks do not display a keyboard focus ring. Arrow keys navigate tabs."
     "Text editing uses Readline shortcuts: Ctrl-A/E move to the beginning/end, Ctrl-B/F move by character, Alt-B/F move by word, Ctrl-D deletes, Ctrl-H backspaces, Ctrl-K/U/W kill text, and Ctrl-Y yanks it. Ctrl-Shift-A or Command-A selects all where supported. Ctrl-D does not quit."
     "Load the optional lui/debug system and call (lui.debug:set-enabled t) on a toggle action in your drawing function to attach an inspector to the current context. It displays the completed application tree, bounds, clipping, sizing, style, and text. Call (lui.debug:set-enabled nil) to close it. Inspector nodes are excluded from its own tree."
     "Clipboard and IME completeness vary by backend; full text shaping is not implemented. Native Wayland, X11, Windows, Cocoa, browser DOM, and raw terminal input use their own platform facilities. Check the project's current test matrix before assuming an untested platform configuration is verified.")
    (:backends "Backends and running"
     "Native: load lui/wayland or lui/x11 on Linux, lui/win32 on Windows, or lui/cocoa on macOS. X11 uses GLX and Wayland uses EGL with the shared OpenGL renderer; Windows and macOS use their native drawing/compositing APIs. Fonts are loaded from the system. OpenGL's offscreen system is useful for rendering tests and is not a separate interactive window backend."
     "Browser: make web-demo compiles the same gallery callback with JSCL and serves it locally. The DOM backend uses browser text metrics and native HTML inputs. make docs-html builds build/docs.html as a standalone offline documentation page; open or host that file directly. No Canvas renderer is required."
     "Terminal: make terminal-demo loads the optional raw backend, handling input, mouse, resize, ANSI colors, and restoration on exit. Plain noninteractive terminal rendering needs only portable Common Lisp. Terminal coordinates are cells; graphical coordinates are pixels."
     "Build commands use GNU Make, Bash, and SBCL. Python is used by the existing integration tests and local web server. make test PLATFORM=core runs portable checks; native, gl, and platform-specific targets cover additional paths. See README for configuration, source registry setup, and the verified platform matrix.")))

(defstruct browser
  (toolkit :glass :type symbol)
  (entries #() :type vector)
  (packages nil :type list)
  (guide :start :type (or null symbol))
  (package nil :type (or null string))
  (query "" :type string)
  (matches nil :type list)
  (selected nil :type (or null integer)))

(defun entry-title (entry)
  (format nil "~A:~A" (getf entry :package) (getf entry :name)))

(defun matches-query-p (entry query)
  (or (zerop (length query))
      (some (lambda (key)
              (search query (or (getf entry key) "") :test #'char-equal))
            '(:name :package :signature :documentation))))

(defun update-matches (state)
  (setf (browser-matches state)
        (loop :for entry :across (browser-entries state) :for index :from 0
              :when (and (or (null (browser-package state))
                             (string= (browser-package state)
                                      (getf entry :package)))
                         (matches-query-p entry (browser-query state)))
              :collect index))
  (unless (member (browser-selected state) (browser-matches state))
    (setf (browser-selected state) (first (browser-matches state))))
  (scroll-to :docs-entries 0 0)
  (scroll-to :docs-detail 0 0))

(defun navigation (state)
  (lui:panel (lui:opt :id :docs-navigation
                      :width (fixed (min (units 28)
                                         (* 0.3 (context-width *context*))))
                      :height (grow) :scroll-p t :padding (units 1)
                      :gap (units 0.5) :opacity 1 :frost 0)
    (lui:label "Guides")
    (dolist (guide *guides*)
      (when (lui:list-item (list :docs-guide (first guide))
                           (if (< (context-width *context*) (units 90))
                               (case (first guide)
                                 (:start "Start") (:frames "Frames")
                                 (:widgets "Controls") (:layout "Layout")
                                 (:toolkits "Styles") (:input "Input")
                                 (:backends "Backends"))
                               (second guide))
                           (lui:opt :width (grow)
                                    :selected-p
                                    (eq (browser-guide state) (first guide))))
        (setf (browser-guide state) (first guide))
        (scroll-to :docs-detail 0 0)))
    (lui:label "API reference")
    (dolist (package (cons nil (browser-packages state)))
      (when (lui:list-item (list :docs-package package)
                           (or package "All packages")
                           (lui:opt :width (grow)
                                    :selected-p
                                    (and (null (browser-guide state))
                                         (equal package
                                                (browser-package state)))))
        (setf (browser-guide state) nil (browser-package state) package)
        (update-matches state)))))

(defun entry-list (state height)
  (lui:panel (lui:opt :id :docs-entries :width (grow) :height height
                      :scroll-p t :padding (units 0.5) :opacity 1 :frost 0)
    (let* ((matches (browser-matches state)) (size (units 3))
           (offset (nth-value 1 (scroll-position :docs-entries)))
           (viewport (previous-box :docs-entries))
           (start (max 0 (floor offset size)))
           (end (min (length matches)
                     (+ start 2 (ceiling (if viewport (box-height viewport)
                                             (units 18)) size)))))
      (emit (make-element
             :height (fixed (* (min start (length matches)) size))))
      (loop :for index :in (subseq matches (min start (length matches)) end)
            :for entry := (aref (browser-entries state) index)
            :do (when (lui:list-item
                       (list :docs-entry index)
                       (if (browser-package state) (getf entry :name)
                           (entry-title entry))
                       (lui:opt :width (grow) :height (fixed size)
                                :selected-p (= index
                                               (browser-selected state))))
                  (setf (browser-selected state) index)
                  (scroll-to :docs-detail 0 0)))
      (emit (make-element :height (fixed (* (- (length matches) end) size))))
      (when (null matches) (lui:label "No matching entries.")))))

(defun detail (state)
  (lui:panel (lui:opt :id :docs-detail :width (grow) :height (grow)
                      :scroll-p t :padding (units 1) :gap (units 1)
                      :opacity 1 :frost 0)
    (if (browser-guide state)
        (let ((guide (assoc (browser-guide state) *guides*)))
          (lui:label (second guide)
                     (lui:opt :width (grow) :font-weight :bold))
          (dolist (paragraph (cddr guide))
            (lui:label paragraph
                       (lui:opt :width (grow)
                                :font-family
                                (if (and (plusp (length paragraph))
                                         (char= (char paragraph 0) #\())
                                    :monospace :sans-serif)))))
        (let ((index (browser-selected state)))
          (if index
              (let ((entry (aref (browser-entries state) index)))
                (lui:label (entry-title entry)
                           (lui:opt :width (grow) :font-weight :bold))
                (lui:label (string-downcase
                            (symbol-name (getf entry :kind :function))))
                (lui:label (or (getf entry :signature) "")
                           (lui:opt :width (grow) :font-family :monospace))
                (lui:label (or (getf entry :documentation)
                               "No docstring is available for this entry.")
                           (lui:opt :width (grow))))
              (lui:label "Choose an API entry from the list."))))))

(defun draw-docs (state)
  (with-toolkit ((browser-toolkit state))
    (lui:panel (lui:opt :width (grow) :height (grow)
                        :background
                        (case (toolkit-surface (browser-toolkit state))
                          (:motif "#b8b8b8") (:garnet "#ffffff")
                          (otherwise "#202430"))
                        :opacity 1 :frost 0 :radius 0
                        :padding (units 1) :gap (units 1))
      (lui:label "LUI documentation"
                 (lui:opt :font-weight :bold :width (grow)))
      (row (:width (grow) :height (grow) :gap (units 1))
        (navigation state)
        (column (:width (grow) :height (grow) :gap (units 1))
          (lui:label "Search API")
          (let ((query (lui:text-field :docs-search (browser-query state)
                                       (lui:opt :width (grow)))))
            (unless (equal query (browser-query state))
              (setf (browser-query state) query (browser-guide state) nil)
              (update-matches state)))
          (unless (browser-guide state)
            (lui:label (format nil "~D API entries"
                               (length (browser-matches state))))
            (entry-list state
                        (fixed (min (units 15)
                                    (* 0.3 (context-height *context*))))))
          (detail state))))))

(defun make-docs (&key (toolkit :glass) (entries *entries*))
  "Return a fresh documentation browser drawing function for ENTRIES."
  (let* ((entries (append (remove-if-not
                           (lambda (entry)
                             (string= (getf entry :package) "lui")) entries)
                          (remove-if
                           (lambda (entry)
                             (string= (getf entry :package) "lui")) entries)))
         (state (make-browser
                 :toolkit toolkit :entries (coerce entries 'vector)
                 :packages (sort (remove-duplicates
                                  (mapcar (lambda (entry)
                                            (getf entry :package))
                                          entries)
                                  :test #'string=)
                                 #'string<))))
    (setf (browser-matches state)
          (loop :for index :below (length entries) :collect index)
          (browser-selected state) (when entries 0))
    (lambda () (draw-docs state))))

(defun main (&key backend width height (interactive t))
  "Open a fresh documentation browser on a loaded backend."
  (run (make-docs) :backend backend :title "LUI documentation"
       :width width :height height :interactive interactive))
