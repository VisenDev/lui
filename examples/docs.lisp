(defpackage #:lui.docs
  (:use #:cl)
  (:export #:main #:make-docs #:*entries*))
(in-package #:lui.docs)

(defvar *entries* nil
  "Generated public API entries, loaded before constructing the browser.")

(defparameter *guides*
  '((:start "Getting started"
      "LUI draws the same immediate-mode interface on native windows, the browser, and a terminal. Load lui to register the backends for your host, then pass a drawing function to lui:run."
     "(asdf:load-system \"lui\")
(lui:run
 (lambda ()
   (let ((name (lui:text-field (lui:opt :default-value \"Common Lisp\"))))
     (when (lui:button \"Say hello\")
       (format t \"Hello ~A!~%\" name)))))"
      "For portable layout and widgets, load lui/core. It has no external dependencies. To load a single backend, use its system, such as lui/x11 or lui/wayland. Browser builds use JSCL or ECL/Emscripten; the standalone documentation uses ECL/WebAssembly. Native graphics use zpb-ttf, CFFI, and platform libraries, with Xlib/GLX for X11 windowing and rendering. All terminal output uses lui/terminal and uncursed."
      "Use make demo for the gallery, make docs for this browser, and make test for the detected platform. Backend availability depends on which systems are loaded; an explicit :backend argument selects one.")
    (:debug "Debugger"
      "Show debugger opens this window's layout debugger. Close dismisses it. Each window owns its debugger state."
      "The tree shows the previous completed application frame. Click a row for details; - / + collapses or expands containers. Tree and details scroll independently. Debugger controls are excluded from their own tree."
      "Hover a tree row to outline bounds in orange and clipping in cyan. Highlights pass input through. Offscreen and clipped badges describe visibility, rather than errors."
      "Selecting a tree row gives its properties more height. Drag the top edge of the properties pane up or down to resize it. Drag it to the bottom, click ×, or click the selected row again to close the pane. With the divider focused, Up and Down adjust its height, Home enlarges it, and End closes it. Read the property names on the left and their current values on the right. Compare Bounds with Clip to see how much of a widget is visible, or compare Width and Height with Bounds to see the result of its sizing rules."
      "Drag the left edge to resize the debugger. From the keyboard, Tab to its rail and use Left/Right to adjust the width or Home/End to choose its minimum or maximum."
     "(asdf:load-system \"lui/debug\")
;; Inside an ordinary draw callback:
(when (lui:button \"Show debugger\" (lui:opt :id :debug))
  (lui.debug:set-debugger-enabled t))"
      "Call lui.debug:set-debugger-enabled on an action. lui.debug:debugger-enabled-p reads the current context; both APIs also accept an explicit context. Stable IDs preserve inspection across frames; anonymous nodes use position-based identity, and vanished selections are cleared.")
    (:frames "Frames and state"
      "Widget values are retained by default. Use OPT :default-value to initialize a field, checkbox, slider, combobox, or date picker once. Use :value when your application model owns the value instead. A drawing function still declares the interface every frame; layout nodes remain frame-local."
     "(defun make-counter ()
  (let ((count 0))
    (lambda ()
      (lui:label (format nil \"Count: ~D\" count))
      (when (lui:button \"Increment\" (lui:opt :id :increment))
        (incf count)))))"
      "Control macros generate stable call-site IDs. In loops use OPT :id with a stable item key (numbers are valid), or WITH-KEY around a reusable group. Keys are combined with the call site and enclosing scope. Index keys follow positions; stable item keys follow reordered items. Duplicate resolved IDs are errors. Removing a widget for a completed frame releases its state; recompiling its call site creates a fresh identity."
      "lui:frame-time returns this frame's clock snapshot. lui:request-frame schedules another redraw, optionally after a delay in seconds. Prefer requesting a deadline for timers over a busy loop; idle windows redraw at :min-fps (default 1). Set :max-fps (default 240) on lui:run to cap active rendering. Input wakes the window and explicit deadlines support animations.")
    (:positioning "Manual positioning"
      "Automatic widgets participate in row or column layout. Manual widgets do not change sibling positions or FIT container sizes. Their content is still measured, so a button can fit its text without automatic placement. Run make manual-demo for a standalone example."
      "Use :position :absolute with :offset-x and :offset-y for coordinates relative to the immediate parent's padded content origin. This form moves with ancestor scrolling. Use :position :fixed with the same offsets for fixed logical client-surface coordinates. Both forms obey ancestor clipping; parent-scroll-position exposes the current parent's scroll offsets for explicit compensation."
      "To reserve space, give an ordinary automatic container a size and put manual widgets inside it. Moving a manual child does not change that reserved space."
      "(lui:column (lui:opt :height (lui:fixed (lui:units 8)))
  (lui:button \"Manual inside a reserved region\"
    (lui:opt :position :absolute
             :offset-x (lui:units 2) :offset-y (lui:units 1))))
(lui:label \"I follow the reserved region\")")
    (:widgets "Controls and options"
      "Buttons return true when activated. Value controls return their value and a changed flag; their resolved ID is the third value. With OPT :value, assign the returned value back to your model. With :default-value or no value option, LUI retains it. Tabs, cells, and list items accept :selected-p for visible selection. Panels contain other declarations."
     "(lui:panel (lui:opt :padding (lui:units 1))
  (setf enabled (lui:checkbox \"Enabled\" (lui:opt :id :enabled :value enabled)))
  (setf volume
        (lui:slider (lui:opt :id :volume :value volume :minimum 0 :maximum 1)))
  (lui:button \"Save\" (lui:opt :id :save :disabled-p (not enabled))))"
      "Pass optional styling/layout settings in one explicit lui:opt form. An omitted option inherits the toolkit default; an explicit NIL remains an explicit value. Common settings include :width, :height, :padding, :foreground, :background, :font-size, and :disabled-p."
      "Canvas commands provide shared drawing primitives. A custom :painter takes the same renderer and layout element on the desktop and in the browser.")
    (:layout "Layout and scrolling"
     "Rows arrange children horizontally; columns arrange them vertically. A fixed size uses backend coordinates, grow distributes available space, and fit measures content. Use lui:units for spacing that adapts to terminal cells and graphical pixels."
     "(lui:row (lui:opt :width (lui:grow)
                :height (lui:grow) :gap (lui:units 1))
  (lui:panel (lui:opt :id :navigation
                       :width (lui:fixed (lui:units 24))
                       :height (lui:grow)
                       :scroll-p t :scrollbar-p t)
    (lui:label \"Navigation\"))
  (lui:panel (lui:opt :width (lui:grow)
                       :height (lui:grow))
    (lui:label \"Content\")))"
     "lui:spacer reserves empty space without painting. Use (lui:spacer (lui:opt :width (lui:grow))) in a row, or :height (lui:grow) in a column, to push siblings apart. Use fixed sizes for explicit spacing. (lui:hr) and (lui:vr) draw horizontal and vertical rules; their long axis grows, their thickness defaults to one backend coordinate, and :foreground overrides the palette border color. Container :padding reserves an inner content area. :gap separates children; :align controls the main axis and :cross-align controls the other axis. :clip-p clips children to the padded content area. :scroll-p adds scrolling with the same clipping rules."
     "Scrolling panels show a scrollbar by default. :scrollbar-p NIL hides it; :scrollbar-width customizes the reserved track width in backend coordinates. The default is 12 graphical pixels or one terminal cell. Drag the thumb to move continuously, or click the track above/below it to page by a viewport. Wheel scrolling supports momentum; nested scrollers pass unused motion to an ancestor."
     "A scrolling viewport needs a bounded size. Nested scrollers pass wheel input to an ancestor when they cannot scroll further. lui:previous-box exposes completed geometry; lui:scroll-position and scroll-to support application-controlled navigation. Virtualize very large lists instead of declaring every row.")
    (:toolkits "Toolkits"
      "The lui package contains application controls, layout, palettes, toolkit registration, and events. Palette accessors live in lui.palette; toolkit registration, rendering policies, and resolved defaults live in lui.toolkit. Both are included in lui/core. Everyday palette construction, presets, and palette/toolkit scopes stay in lui. Built-in defaults belong to their own packages, such as lui.qt:*qt-defaults*. Other specialized APIs live in lui.font (font configuration and metrics), lui.draw (custom painting and geometry), lui.debug (inspection), lui.terminal (snapshots), and lui.pdf (PDF output); load the corresponding optional systems before calling them. Choose a toolkit below the heading to try its widgets independently of the page style. Glass uses rounded translucent surfaces; Motif uses solid beveled controls; Garnet uses high-contrast square shapes, hard shadows, and bold monospace text. macOS uses warm surfaces, rounded controls, subtle borders, and blue accents; Qt uses restrained raised desktop controls. Cycle palette to try Default, Light, Dark, Ocean, and Forest on the page and live samples. A window background remains opaque."
     "(lui:with-toolkit (:motif)
  (lui:button \"OK\" (lui:opt :id :ok)))
(lui:with-toolkit (:garnet)
  (lui:label \"A different toolkit\"))"
      "lui:with-toolkit chooses defaults and control implementations for a lexical drawing scope. Nested scopes restore the previous toolkit. Use lui:with-palette with :ocean to apply a built-in color theme without changing geometry. lui:available-palettes lists the presets. lui:current-toolkit returns the current name; lui.toolkit:toolkit-defaults exposes its inherited options."
      "Custom toolkits register defaults, a parent, control overrides, and shared geometry and painting callbacks. Use lui.toolkit:define-toolkit or lui.toolkit:register-toolkit; the API reference shows their exact signatures. Backend implementations may approximate optical effects differently: X11 and Wayland share the OpenGL renderer through GLX/EGL, while Cocoa uses whole-window material.")
    (:input "Input and inspection"
     "Tab and Shift-Tab move keyboard focus. Enter and Space activate a focused button, checkbox, or tab; Space inserts a space in an editor. Pointer clicks do not display a keyboard focus ring. Arrow keys navigate tabs."
     "When implementing a draggable control, handle :cancel by clearing its drag state. event-buttons reports the physical buttons on pointer motion when the backend knows them. Zero means all buttons are up, bit 0 means primary, bit 1 means secondary, and NIL means unknown."
     "Text editing uses Readline shortcuts: Ctrl-A/E move to the beginning/end, Ctrl-B/F move by character, Alt-B/F move by word, Ctrl-D deletes, Ctrl-H backspaces, Ctrl-K/U/W kill text, and Ctrl-Y yanks it. Ctrl-Shift-A or Command-A selects all where supported. Ctrl-D does not quit."
     "Load the optional lui/debug system and call (lui.debug:set-debugger-enabled t) on a toggle action in your drawing function to attach a debugger to the current context. It displays the completed application tree, bounds, clipping, sizing, style, and text. Call (lui.debug:set-debugger-enabled nil) to close it. Debugger nodes are excluded from its own tree."
     "Clipboard and IME completeness vary by backend; full text shaping is not implemented. Native Wayland, X11, Windows, Cocoa, browser canvas, and raw terminal input use their own platform facilities. Check the project's current test matrix before assuming an untested platform configuration is verified.")
    (:backends "Backends and running"
     "Native: load lui/wayland or lui/x11 on Linux, lui/win32 on Windows, or lui/cocoa on macOS. X11 uses GLX and Wayland uses EGL with the shared OpenGL renderer; Windows and macOS use native drawing/compositing APIs. Fonts are loaded from the system. The offscreen OpenGL system also supports rendering tests."
     "Browser: make web-demo compiles the same gallery callback with JSCL and serves it locally. The web backend uses a high-DPI canvas for widgets and selectable HTML text for visible labels. Use make docs for the native docs browser, make docs-html for a standalone ECL/WebAssembly build/docs.html, and make docs-pages to refresh docs/index.html for hosting."
     "Terminal: make terminal-demo loads lui/terminal. Uncursed handles terminal cells, Unicode widths, colors, input decoding, and incremental output; LUI maps widgets and events onto it. Plain snapshots also require lui/terminal. Terminal coordinates are cells; graphical coordinates are pixels."
     "Build commands use GNU Make, Bash, and SBCL. Python is used by the existing integration tests and local web server. make test PLATFORM=core runs portable checks; native, gl, and platform-specific targets cover additional paths. See AGENTS.md for configuration, source registry setup, and platform validation guidance.")))

(defstruct browser
  (clicks 0 :type integer) (panel-clicks 0 :type integer)
  (date nil :type (or null string))
  (checked-p t :type boolean) (cell-p nil :type boolean)
  (text "Edit this example" :type string) (value 0.4 :type real)
  (tab :one :type symbol) (item :one :type symbol)
  (circles '((4 4)) :type list)
  (sample :qt :type symbol)
  (toolkit :qt :type symbol)
  (palette :default :type symbol)
  (entries #() :type vector)
  (packages nil :type list)
  (guide :start :type (or null symbol))
  (symbols-p nil :type boolean)
  (package nil :type (or null string))
  (query "" :type string)
  (row-key nil :type list) (rows #() :type vector)
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
  (setf (browser-row-key state) nil)
  (setf (browser-matches state)
        (loop :for entry :across (browser-entries state) :for index :from 0
              :when (and (or (null (browser-package state))
                             (string= (browser-package state)
                                      (getf entry :package)))
                         (matches-query-p entry (browser-query state)))
              :collect index))
  (unless (member (browser-selected state) (browser-matches state))
    (setf (browser-selected state) (first (browser-matches state))))
  (lui:scroll-to :docs-entries 0 0)
  (lui:scroll-to :docs-detail 0 0))

(defun navigation-width ()
  (min (lui:units (if (< (lui.frame:context-width lui.frame:*context*)
            (lui:units 105)) 18 28))
       (* 0.3 (lui.frame:context-width lui.frame:*context*))))

(defun reference-width ()
  (if (>= (lui.frame:context-width lui.frame:*context*) (lui:units 80))
      (min (lui:units 40)
           (* 0.44 (- (lui.frame:context-width lui.frame:*context*)
                      (navigation-width) (lui:units 4))))
      (- (lui.frame:context-width lui.frame:*context*) (navigation-width)
        (lui:units 3))))

(defun wrap-symbol (text columns)
  (format nil "~{~A~^~%~}"
          (loop :with start := 0
                :for end := (min (length text) (+ start columns))
                :for delimiter :=
                (when (< end (length text))
                  (position-if (lambda (char) (find char "-:")) text
                               :start start :end end :from-end t))
                :for stop := (if delimiter (1+ delimiter) end)
                :while (< start (length text))
                :collect (subseq text start stop)
                :do (setf start stop))))

(defun symbol-rows (state)
  (let* ((width (reference-width))
         (key (list width (lui:current-toolkit) lui.toolkit:*toolkit-revision*
            lui:*unit*
                    (lui.frame:context-text-mode-p lui.frame:*context*))))
    (unless (equal key (browser-row-key state))
      (let* ((defaults (lui.toolkit:toolkit-defaults))
             (measure (lui.frame:context-measure lui.frame:*context*))
             (text-p (lui.frame:context-text-mode-p lui.frame:*context*))
             (inset (if text-p 0 24)) (gutter (if text-p 1 12))
             (available (max 1 (- width (lui:units 1) gutter inset)))
             (top 0))
        (flet ((probe (text)
                 (funcall measure
                          (lui.widgets:make-widget
                           :kind :label :text text :font-family :monospace
                           :font-size (getf defaults :font-size 16)
                           :font-weight (getf defaults :font-weight :normal))
                          nil)))
          (multiple-value-bind (advance line-height) (probe "M")
            (let ((columns (max 1 (floor available (max 1 advance)))))
              (setf (browser-rows state)
                    (coerce
                     (loop :for index :in (browser-matches state)
                           :for entry := (aref (browser-entries state) index)
                           :for title := (if (browser-package state)
                                             (getf entry :name)
                                             (entry-title entry))
                           :for caption := (wrap-symbol title columns)
                           :for height :=
                           (+ (if text-p 1 12)
                              (* line-height
                                 (1+ (count #\Newline caption))))
                           :collect (prog1 (list index caption top height)
                                      (incf top height)))
                     'vector)))))
        (setf (browser-row-key state) key)))
    (browser-rows state)))

(defun navigation (state)
  (lui:panel (lui:opt :id :docs-navigation
                      :width (lui:fixed (navigation-width))
                      :height (lui:grow) :scroll-p (not
          (lui.frame::context-page-height-p lui.frame:*context*))
                      :padding (lui:units 1)
                      :gap (lui:units 0.5) :opacity 1 :frost 0)
    (lui:label "Guides")
    (dolist (guide *guides*)
      (when
        (lui:list-item
          (if (< (lui.frame:context-width lui.frame:*context*) (lui:units
                  105))
                               (case (first guide)
                                 (:start "Start") (:debug "Debugger")
                                 (:frames "Frames") (:positioning "Positioning")
                                 (:widgets "Controls") (:layout "Layout")
                                 (:toolkits "Toolkits") (:input "Input")
                                 (:backends "Backends"))
                               (second guide))
          (lui:opt
            :id (list :docs-guide (first guide))
            :width (lui:grow)
            :selected-p (eq (browser-guide state) (first guide))))
        (setf (browser-guide state) (first guide)
              (browser-symbols-p state) nil)
        (lui:scroll-to :docs-detail 0 0)))
    (when
      (lui:list-item
        "Live widgets"
        (lui:opt
          :id '(:docs-guide :previews)
          :width (lui:grow)
          :selected-p (eq (browser-guide state) :previews)))
      (setf (browser-guide state) :previews
            (browser-symbols-p state) nil)
      (lui:scroll-to :docs-detail 0 0))
    (lui:label "API reference")
    (dolist (package (cons nil (browser-packages state)))
      (when
        (lui:list-item
                           (or package "All packages")
          (lui:opt
            :id (list :docs-package package)
            :width (lui:grow)
                                    :selected-p
                                    (and (null (browser-guide state))
                                         (equal package
                                                (browser-package state)))))
        (setf (browser-guide state) nil (browser-package state) package
              (browser-symbols-p state) t)
        (update-matches state)))))

(defun select-reference (state)
  ;; Apply input before virtualization can omit a row from the new viewport.
  (loop :for resolved :across (lui:activated-ids)
        :for id = (lui:widget-key resolved) :do
    (when (and (consp id) (eq (first id) :docs-entry)
               (integerp (second id)) (null (cddr id))
               (member (second id) (browser-matches state)))
      (setf (browser-selected state) (second id)
            (browser-guide state) nil
            (browser-symbols-p state) nil)
      (lui:scroll-to :docs-detail 0 0)
      (when (lui.frame::context-page-height-p lui.frame:*context*)
            (setf (lui.frame::context-requested-page-top lui.frame:*context*)
            0))
      (lui:request-frame))))

(defun entry-list (state height)
  (lui:panel (lui:opt :id :docs-entries :width (lui:grow) :height height
                      :scroll-p (not (lui.frame::context-page-height-p
            lui.frame:*context*))
                      :padding (lui:units 0.5) :opacity 1 :frost 0)
    (let* ((rows (symbol-rows state)) (count (length rows))
           (viewport (lui:previous-box :docs-entries))
           (page-p (lui.frame::context-page-height-p lui.frame:*context*))
           (offset (if page-p
                       (if viewport
                           (- (lui.frame::context-page-top
                    lui.frame:*context*)
                              (lui:box-y viewport) (lui:units 0.5))
                           0)
                       (nth-value 1 (lui:scroll-position :docs-entries))))
           (bottom (+ offset (if page-p
                                 (lui.frame::context-viewport-height
                  lui.frame:*context*)
                                 (if viewport (lui:box-height viewport)
                  (lui:units 18)))))
           (start (max 0 (1- (or (position-if
                                  (lambda (row)
                                    (> (+ (third row) (fourth row)) offset))
                                  rows) count))))
           (end (min count (1+ (or (position-if
                                    (lambda (row) (>= (third row) bottom))
                                    rows :start start) count))))
           (total (if (plusp count)
                      (+ (third (aref rows (1- count)))
                         (fourth (aref rows (1- count)))) 0)))
      (lui.frame:emit (lui.layout:make-element :height (lui:fixed (if (< start
                  count)
                                             (third (aref rows start))
                                             total))))
      (loop :for i :from start :below end
            :for (index caption top height) := (aref rows i)
            :do
        (lui:list-item
          caption
          (lui:opt
            :id (list :docs-entry index)
            :width (lui:grow)
            :height (lui:fixed height)
                          :font-family :monospace
                          :selected-p
                          (and (null (browser-guide state))
                               (= index (browser-selected state))))))
      (lui.frame:emit (lui.layout:make-element
             :height (lui:fixed (- total (if (plusp end)
                                         (+ (third (aref rows (1- end)))
                                            (fourth (aref rows (1- end))))
                                         0)))))
      (when (zerop count) (lui:label "No matching entries.")))))

(defparameter *preview-kinds*
  '(("DATE-PICKER" . :date-picker)
    ("LABEL" . :label) ("BUTTON" . :button) ("TAB" . :tab)
    ("CHECKBOX" . :checkbox) ("SLIDER" . :slider)
    ("TEXT-FIELD" . :text-field) ("CELL" . :cell)
    ("LIST-ITEM" . :list-item) ("GAUGE" . :gauge) ("CANVAS" . :canvas)
    ("PANEL" . :panel) ("ROW" . :row) ("COLUMN" . :column)
    ("SPACER" . :spacer) ("HR" . :hr) ("VR" . :vr)))

(defun canvas-preview (state)
  (let ((box (lui:previous-box :docs-preview-canvas)))
    (when box
      (loop for event across (lui.frame:events-for :docs-preview-canvas) do
        (when (and (eq (lui:event-kind event) :press)
                   (eq (lui:event-button event) :primary))
          (push (list (/ (- (lui:event-x event) (lui:box-x box)) lui:*unit*)
                      (/ (- (lui:event-y event) (lui:box-y box)) lui:*unit*))
                (browser-circles state)))))
    (lui:canvas
                (loop :for (x y) :in (browser-circles state)
            :collect (list :circle (lui:units x) (lui:units y) (lui:units 1)
                                     "#258bff" "#a7caff"))
      (lui:opt
        :id :docs-preview-canvas
        :width (lui:grow)
        :height (lui:fixed (lui:units 8))
                         :background "#ffffff")))
  (lui:label "Click the canvas to add a circle." (lui:opt :width (lui:grow))))

(defun preview (state kind)
  (lui:label (format nil "Live preview: ~A" (string-downcase
                                             (symbol-name kind)))
             (lui:opt :width (lui:grow) :font-weight :bold))
  (case kind
    (:date-picker
      (setf (browser-date state)
        (lui:date-picker (lui:opt :id :docs-date :value (browser-date
                state)))))
    (:label (lui:label "A label wraps naturally as the window narrows."
                       (lui:opt :width (lui:grow))))
    (:button
      (when
        (lui:button "Try this button" (lui:opt :id :docs-preview-button))
       (incf (browser-clicks state)))
     (lui:label (format nil "Button clicks: ~D" (browser-clicks state))))
    (:checkbox
     (setf (browser-checked-p state)
        (lui:checkbox
          "Enable the example"
          (lui:opt
            :id :docs-preview-checkbox
            :value (browser-checked-p state)))))
    (:slider
     (setf (browser-value state)
        (lui:slider
          (lui:opt
            :id :docs-preview-slider
            :value (browser-value state)
            :width (lui:grow))))
      (lui:label (format nil "Value: ~D%" (round (* 100 (browser-value
                  state))))))
    (:text-field
     (setf (browser-text state)
        (lui:text-field
          (lui:opt
            :id :docs-preview-text
            :value (browser-text state)
            :width (lui:grow))))
     (lui:label (format nil "~D characters" (length (browser-text state)))))
    (:tab
     (lui:row (lui:opt :width (lui:grow) :gap (lui:units 0.5))
       (dolist (item '(:one :two))
          (when
            (lui:tab
                        (if (eq item :one) "First tab" "Second tab")
              (lui:opt
                :id (list :docs-preview-tab item)
                :selected-p (eq item (browser-tab state))))
           (setf (browser-tab state) item)
           (lui:request-frame))))
     (lui:label (if (eq (browser-tab state) :one)
                    "First page is selected." "Second page is selected.")))
    (:list-item
     (dolist (item '(:one :two))
        (when
          (lui:list-item
                            (if (eq item :one) "First item" "Second item")
            (lui:opt
              :id (list :docs-preview-item item)
              :width (lui:grow)
              :selected-p (eq item (browser-item state))))
         (setf (browser-item state) item)
         (lui:request-frame))))
    (:cell
      (when
        (lui:cell
          "Cell A1"
          (lui:opt
            :id :docs-preview-cell
            :width (lui:fixed (lui:units 16))
                              :selected-p (browser-cell-p state)))
       (setf (browser-cell-p state) (not (browser-cell-p state)))
       (lui:request-frame)))
    (:gauge
      (lui:gauge
        (browser-value state)
        (lui:opt :id :docs-preview-gauge :width (lui:grow)))
      (when
        (lui:button "Advance progress" (lui:opt :id :docs-preview-progress))
       (setf (browser-value state)
             (if (>= (browser-value state) 1) 0
                 (min 1 (+ (browser-value state) 0.2))))
       (lui:request-frame)))
    (:canvas (canvas-preview state))
    (:spacer
     (lui:row (lui:opt :width (lui:grow))
       (lui:label "Left")
       (lui:spacer (lui:opt :width (lui:grow)))
       (lui:label "Right")))
    (:hr (lui:hr))
    (:vr
     (lui:row (lui:opt :width (lui:grow) :gap (lui:units 1))
       (lui:label "Before")
       (lui:vr)
       (lui:label "After")))
    (:panel
      (lui:panel (lui:opt :width (lui:grow) :padding (lui:units 1) :gap
            (lui:units 0.5))
       (lui:label "A panel groups and styles its children."
                  (lui:opt :width (lui:grow)))
        (when (lui:button "Panel action" (lui:opt :id
                                           :docs-preview-panel))
         (incf (browser-panel-clicks state)))
       (lui:label (format nil "Panel actions: ~D"
                          (browser-panel-clicks state)))))
    (:row
        (lui:row (lui:opt :width (lui:grow) :gap (lui:units 1) :cross-align
          :center)
          (lui:label "Left" (lui:opt :width (lui:grow)))
          (lui:label "Center" (lui:opt :width (lui:grow)))
          (lui:label "Right" (lui:opt :width (lui:grow)))))
    (:column
        (lui:column (lui:opt :width (lui:grow) :gap (lui:units 0.5))
          (lui:label "First child")
          (lui:label "Second child")
          (lui:label "Third child")))))

(defparameter *toolkit-packages*
  '(("lui.glass" . :glass) ("lui.motif" . :motif) ("lui.garnet" . :garnet)
    ("lui.macos" . :macos) ("lui.qt" . :qt)))

(defun toolkit-sample (state toolkit)
  (lui:with-toolkit (toolkit)
    (lui:panel (lui:opt :width (lui:grow) :padding (lui:units 1) :gap
          (lui:units 1)
                        :opacity 1)
      (lui:label (case toolkit (:macos "macOS") (:qt "Qt")
                   (otherwise (string-capitalize (symbol-name toolkit)))))
      (when (lui:button "Try this button" (lui:opt :id
                                            :docs-sample-button))
        (incf (browser-clicks state)))
      (setf (browser-checked-p state)
        (lui:checkbox
          "Enable the example"
          (lui:opt :id :docs-sample-check :value (browser-checked-p state))))
      (lui:label (format nil "Button clicks: ~D" (browser-clicks state))))))

(defun entry-preview-kind (entry)
  (when (member (getf entry :package)
                '("lui" "lui.glass" "lui.motif" "lui.garnet" "lui.macos" "lui.qt" "lui.frame")
                :test #'string=)
    (cdr (assoc (getf entry :name) *preview-kinds* :test #'string-equal))))

(defun detail (state)
  (lui:panel (lui:opt :id :docs-detail :width (lui:grow) :height (lui:grow)
                      :scroll-p (not (lui.frame::context-page-height-p
            lui.frame:*context*)) :padding (lui:units 1) :gap (lui:units 1)
                      :opacity 1 :frost 0)
    (cond
      ((eq (browser-guide state) :previews)
       (lui:label "Interactive widgets and containers"
                  (lui:opt :width (lui:grow) :font-weight :bold))
       (dolist (pair *preview-kinds*) (preview state (cdr pair))))
      ((browser-guide state)
       (let ((guide (assoc (browser-guide state) *guides*)))
         (lui:label (second guide)
                    (lui:opt :width (lui:grow) :font-weight :bold))
         (when (eq (browser-guide state) :toolkits)
           (lui:row (lui:opt :width (lui:grow) :gap (lui:units 0.5))
             (dolist (pair *toolkit-packages*)
               (let ((name (cdr pair)))
                 (when
                    (lui:tab
                                (case name (:macos "macOS") (:qt "Qt")
                        (otherwise (string-capitalize (symbol-name name))))
                      (lui:opt
                        :id (list :docs-sample name)
                        :selected-p (eq name (browser-sample state))))
                   (setf (browser-sample state) name)))))
           (toolkit-sample state (browser-sample state)))
         (when (eq (browser-guide state) :debug)
           (when
              (lui:button
                "Open debugger"
                (lui:opt
                  :id :docs-open-debug
                  :disabled-p (lui.debug:debugger-enabled-p)))
             (lui.debug:set-debugger-enabled t)))
         (dolist (paragraph (cddr guide))
           (lui:label paragraph
                      (lui:opt :width (lui:grow)
                               :font-family
                               (if (and (plusp (length paragraph))
                                        (char= (char paragraph 0) #\())
                                   :monospace :sans-serif))))))
      (t
       (let ((index (browser-selected state)))
         (if index
             (let ((entry (aref (browser-entries state) index)))
               (lui:label (entry-title entry)
                          (lui:opt :width (lui:grow) :font-weight :bold))
               (lui:label (string-downcase
                           (symbol-name (getf entry :kind :function))))
               (lui:label (or (getf entry :signature) "")
                          (lui:opt :width (lui:grow) :font-family :monospace))
               (lui:label (or (getf entry :documentation)
                              "No docstring is available for this entry.")
                          (lui:opt :width (lui:grow)))
               (let ((kind (entry-preview-kind entry))
                     (toolkit (cdr (assoc (getf entry :package)
                                          *toolkit-packages* :test #'equal))))
                 (cond (kind (lui:with-toolkit ((or toolkit
                            (lui:current-toolkit)))
                               (preview state kind)))
                       ((and toolkit (string= "*DEFAULTS*" (getf entry
                            :name)))
                        ;; (toolkit-sample state toolkit)
                        ))))
             (lui:label "Choose an API entry from the list.")))))))

(defun search-reference (state)
  (lui:label "Search API")
  (let ((query
        (lui:text-field
          (lui:opt
            :id :docs-search
            :value (browser-query state)
            :width (lui:grow)))))
    (unless (equal query (browser-query state))
      (setf (browser-query state) query (browser-guide state) nil
            (browser-symbols-p state) t)
      (update-matches state)))
  (lui:label (format nil "~D API entries" (length (browser-matches state)))))

(defun references (state)
  (lui:column (lui:opt :width (lui:fixed (reference-width)) :height (lui:grow)
                  :gap (lui:units 0.5))
    (search-reference state)
    (entry-list state (lui:grow))))

(defun draw-docs (state)
  (select-reference state)
  (lui:with-toolkit ((browser-toolkit state))
   (lui:with-palette ((browser-palette state))
    (lui:panel (lui:opt :width (lui:grow) :height (lui:grow)
                        :background
                        (let ((colors (lui.toolkit:toolkit-palette)))
                            (getf colors :window-background (getf colors
                  :background)))
                        :opacity 1 :frost 0 :radius 0
                        :padding (lui:units 1) :gap (lui:units 1))
      (lui:row (lui:opt :width (lui:grow) :gap (lui:units 1) :cross-align
        :center)
        (lui:label "LUI documentation"
                   (lui:opt :font-weight :bold :width (lui:grow)))
        (lui:label (ecase (browser-toolkit state)
                     (:glass "Toolkit: Glass") (:motif "Toolkit: Motif")
                       (:garnet "Toolkit: Garnet") (:macos "Toolkit: macOS")
                (:qt "Toolkit: Qt")))
          (when (lui:button "Cycle toolkit" (lui:opt :id
                                              :docs-toolkit))
          (setf (browser-toolkit state)
                (case (browser-toolkit state)
                    (:glass :motif) (:motif :garnet) (:garnet :macos) (:macos
                    :qt) (otherwise :glass)))
          (lui:request-frame))
          (when (lui:button "Show debugger" (lui:opt :id
                                              :docs-debug))
          (lui.debug:set-debugger-enabled t)))
      (lui:row (lui:opt :width (lui:grow) :gap (lui:units 1) :cross-align
        :center)
          (lui:label (format nil "Palette: ~A" (string-capitalize (symbol-name
                    (browser-palette state)))))
          (when (lui:button "Cycle palette" (lui:opt :id
                                              :docs-palette))
          (let ((names (lui:available-palettes)))
            (setf (browser-palette state)
                    (aref names (mod (1+ (position (browser-palette state)
                          names)) (length names)))))
          (lui:request-frame)))
      (lui:label (lui.frame::frame-rate-label))
      (lui:row (lui:opt :width (lui:grow) :height (lui:grow) :gap (lui:units
        1))
        (navigation state)
          (if (>= (lui.frame:context-width lui.frame:*context*) (lui:units
                  80))
            (progn (references state) (detail state))
            (lui:column (lui:opt :width (lui:grow) :height (lui:grow) :gap
              (lui:units
                    0.5))
              (search-reference state)
              (when
                (lui:button
                                (if (browser-symbols-p state)
                                    "Read selected" "Browse symbols")
                  (lui:opt :id :docs-symbols :width (lui:grow)))
                (setf (browser-symbols-p state)
                      (not (browser-symbols-p state))))
              (if (browser-symbols-p state)
                  (entry-list state (lui:grow))
                  (detail state)))))))))

(defun make-docs (&key (toolkit :qt) (entries *entries*))
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
  (lui:run (make-docs) :backend backend :title "LUI documentation"
       :width width :height height :interactive interactive))
