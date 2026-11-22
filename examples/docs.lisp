(defpackage #:%lui.docs
  (:use #:cl)
  (:export #:main #:make-docs #:*entries*))
(in-package #:%lui.docs)

(defvar *entries* nil
  "Generated public API entries, loaded before constructing the browser.")

(defparameter *guides*
  '((:start "Getting started"
      "LUI supports immediate-mode interfaces and an optional data-driven retained UI layer on top of the same core. Its layout and widgets run on native windows, the browser, and a terminal. Load lui to register the backends for your host, then pass a drawing function to lui:run."
     "(asdf:load-system \"lui\")
(lui:run
 (lambda ()
   (let ((name (lui:text-field :default-value \"Common Lisp\")))
     (when (lui:button \"Say hello\")
       (format t \"Hello ~A!~%\" name)))))"
      "For portable layout and widgets, load lui/core. It has no external dependencies. To load a single backend, use its system, such as lui/x11 or lui/wayland. Browser builds use JSCL or ECL/Emscripten; the standalone documentation uses ECL/WebAssembly. Native graphics use zpb-ttf, CFFI, and platform libraries, with Xlib/GLX for X11 windowing and rendering. All terminal output uses lui/terminal and uncursed."
      "Use make demo for the gallery, make retained-demo for the data-driven playground, make docs for this browser, and make test for the detected platform. Backend availability depends on which systems are loaded; an explicit :backend argument selects one.")
    (:retained "Retained UI"
      "Load lui/retained alongside your backend to describe an interface as reusable Lisp data. Call lui.retained:draw inside the callback passed to lui:run. The tree can be declared once with DEFPARAMETER and edited by ordinary functions; it can also be reconstructed each frame. LUI still solves layout and routes input each frame."
      "(asdf:load-system \"lui\")
(asdf:load-system \"lui/retained\")

(defparameter *greeting* (list :label \"Hello!\"))
(defun say-hello ()
  (setf (second *greeting*) \"Hello from retained data!\"))

(defparameter *ui*
  (list (list :column (list :gap '(:units 1))
              *greeting*
              (list :button \"Say hello\" :id :hello
                    :on-activate 'say-hello))))

(lui:run (lambda () (lui.retained:draw *ui*)))"
      "For editor completion, construct nodes with lui.retained:list and explicit keywords: (lui.retained:list :button :text \"Hello\" :on-activate 'say-hello). Containers use :children with a list of nodes. The constructor exposes the supported keyword names in its argument list for SLIME and returns ordinary data. Use CL:LIST to assemble the outer forest. The original format still works: leaves contain a keyword kind, the usual positional arguments, and keyword options. Containers contain a kind, an options plist, then child nodes. Ordinary styling options such as :padding, :foreground, :background, :font-size and :font-weight pass through to LUI. Numeric spacing accepts (:units NUMBER), resolved for the active backend each frame. Sizing options accept actual objects such as (lui:grow), evaluated when constructing the data; DRAW never evaluates Lisp forms."
      "Use :id keys for siblings that can move. Without keys, identity follows position. Supply distinct DRAW :id values for multiple trees in one parent. :default-value initializes LUI-owned control state; :value supplies application-owned state. Removing a control for a completed frame releases its owned state."
      ":on-activate takes a zero-argument function; :on-change receives the new value. Either can be a symbol naming a function: its SYMBOL-FUNCTION is looked up when dispatched, so redefining a function updates existing trees. DRAW queues callbacks during traversal, then invokes them in order after successful traversal and requests another frame. Callbacks can directly edit the tree: changes appear next frame, with no application callback queue required. A traversal error discards queued callbacks; a callback error stops dispatch without rolling back earlier edits."
      "Run make retained-demo (or make retained-demo PLATFORM=terminal) to try nested layouts, editable keyed rows, live data changes, toolkit/palette switching, and FPS. This optional module has no additional core dependencies. Its standalone demo currently has native and terminal launchers; browser application builds must explicitly include the retained module.")
    (:debug "Debugger"
      "Show debugger opens this window's layout debugger. Close dismisses it. Each window owns its debugger state."
      "The tree shows the previous completed application frame. Click a row for details; - / + collapses or expands containers. Tree and details scroll independently. Debugger controls are excluded from their own tree."
      "Hover a tree row to outline bounds in orange and clipping in cyan. Highlights pass input through. Offscreen and clipped badges describe visibility, rather than errors."
      "Selecting a tree row gives its properties more height. Drag the top edge of the properties pane up or down to resize it. Drag it to the bottom, click ×, or click the selected row again to close the pane. With the divider focused, Up and Down adjust its height, Home enlarges it, and End closes it. Read the property names on the left and their current values on the right. Compare Bounds with Clip to see how much of a widget is visible, or compare Width and Height with Bounds to see the result of its sizing rules."
      "Drag the left edge to resize the debugger. From the keyboard, Tab to its rail and use Left/Right to adjust the width or Home/End to choose its minimum or maximum."
     "(asdf:load-system \"lui/debug\")
;; Inside an ordinary draw callback:
(when (lui:button \"Show debugger\" :id :debug)
  (lui.debug:set-debugger-enabled t))"
      "Call lui.debug:set-debugger-enabled on an action. lui.debug:debugger-enabled-p reads the current context; both APIs also accept an explicit context. Stable IDs preserve inspection across frames; anonymous nodes use position-based identity, and vanished selections are cleared.")
    (:frames "Frames and state"
      "Widget values are retained by default. Use :default-value to initialize a field, checkbox, slider, combobox, or date picker once. Use :value when your application model owns the value instead. A drawing function still declares the interface every frame; layout nodes remain frame-local."
     "(defun make-counter ()
  (let ((count 0))
    (lambda ()
      (lui:label (format nil \"Count: ~D\" count))
      (when (lui:button \"Increment\" :id :increment)
        (incf count)))))"
      "Widget macros, including containers and labels, generate stable call-site IDs. In loops use :id with a stable item key (numbers are valid), or WITH-KEY around a reusable group. Default IDs are scoped to the enclosing container and WITH-KEY group. Index keys follow positions; stable item keys follow reordered items. Duplicate resolved IDs are errors. Removing a widget for a completed frame releases its state; recompiling its call site creates a fresh identity."
      "lui:frame-time returns this frame's clock snapshot. lui:request-frame schedules another redraw, optionally after a delay in seconds. Prefer requesting a deadline for timers over a busy loop; idle windows redraw at :min-fps (default 1). Set :max-fps (default 240) on lui:run to cap active rendering. Input wakes the window and explicit deadlines support animations.")
    (:positioning "Manual positioning"
      "Automatic widgets participate in row or column layout. Manual widgets do not change sibling positions or FIT container sizes. Their content is still measured, so a button can fit its text without automatic placement. Run make manual-demo for a standalone example."
      "Use :position :absolute with :offset-x and :offset-y for coordinates relative to the immediate parent's padded content origin. This form moves with ancestor scrolling. Use :position :fixed with the same offsets for fixed logical client-surface coordinates. Both forms obey ancestor clipping; parent-scroll-position exposes the current parent's scroll offsets for explicit compensation."
      "To reserve space, give an ordinary automatic container a size and put manual widgets inside it. Moving a manual child does not change that reserved space."
      "(lui:column (:height (lui:fixed (lui:units 8)))
  (lui:button \"Manual inside a reserved region\"
    :position :absolute
    :offset-x (lui:units 2) :offset-y (lui:units 1)))
(lui:label \"I follow the reserved region\")")
    (:widgets "Controls and options"
      "Buttons return true when activated. Value controls return their value and a changed flag; their resolved ID is the third value. With :value, assign the returned value back to your model. With :default-value or no value option, LUI retains it. Tabs, cells, and list items accept :selected-p for visible selection. Panels contain other declarations."
     "(lui:panel (:padding (lui:units 1))
  (setf enabled (lui:checkbox \"Enabled\" :id :enabled :value enabled))
  (setf volume
        (lui:slider :id :volume :value volume :minimum 0 :maximum 1))
  (lui:button \"Save\" :id :save :disabled-p (not enabled)))"
      "Pass styling and layout keywords directly to controls, or group them before a container body. Use :options for a computed property list. Explicit keywords take precedence. An omitted option inherits the toolkit default; an explicit NIL remains an explicit value. Common settings include :width, :height, :padding, :foreground, :background, :font-size, and :disabled-p."
      "Canvas commands provide shared drawing primitives. A custom :painter takes the same renderer and layout element on the desktop and in the browser.")
    (:menus "Menus and floating content"
      "MENU-BAR groups root menus and direct MENU-ITEM actions. Direct actions use compact menu styling with hover feedback and activate like buttons. MENU opens on click or hover and may contain MENU-ITEM actions, separators, or nested menus. Selecting an action closes the chain. Disabled items are skipped by keyboard navigation."
      "(lui:menu-bar ()
  (lui:menu \"File\" ()
    (when (lui:menu-item \"New\") (new-document))
    (lui:menu \"Export\" ()
      (when (lui:menu-item \"PDF\") (export-pdf))))
  (when (lui:menu-item \"Customers\") (show-customers)))"
      "Up/Down and Home/End move among enabled items. Right opens a submenu; Left returns to its parent or changes the root menu. Escape closes one level. Tab leaves the menu, and clicking outside dismisses it."
      "FLOATING-EXPANDER accepts arbitrary content, including value controls that stay open while edited. Nest expanders to open child panes beside their parent. Set :open-on-hover-p to enable hover opening; :popup-width and :popup-height constrain the pane. The body is evaluated only while open, with its IDs scoped to the trigger. Menus and expanders return open state, changed flag, and resolved ID."
      "SPINNER is a noninteractive loading indicator. Declare it while work is pending; it schedules its own animation frames. :disabled-p pauses it, and removing it stops its redraw requests. Use :foreground, :width, and :height to customize it.")
    (:dialogs "Messages and confirmations"
     "POPUP queues a message once and redraws it until OK or Escape. Call it in response to an error on the UI thread, inside the target window's frame context. Messages are queued in order and capture the current toolkit and palette."
     "(lui:popup \"Could not save the file.\" :title \"Save failed\")"
     "CONFIRM is immediate mode: declare it every frame while awaiting the user's decision. It returns NIL while waiting, :CONFIRM when accepted, or :CANCEL on Cancel or Escape. Stop declaring it after a decision. Declare at most one confirmation per frame; queued messages wait behind it."
     "(when deleting-p
  (case (lui:confirm \"Delete this order?\" :confirm-label \"Delete\")
    (:confirm (setf deleting-p nil) (delete-order order))
    (:cancel (setf deleting-p nil))))"
     "Both are modal overlays inside the current window. Outside clicks do nothing, Tab cycles inside the dialog, and previous focus is restored on close. Confirmations initially focus Cancel. Omission closes a confirmation without generating an answer. Long messages scroll independently of the title and action buttons. Dialog text remains selectable for copying error details.")
    (:layout "Layout and scrolling"
     "Rows arrange children horizontally; columns arrange them vertically. A fixed size uses backend coordinates, grow distributes available space, and fit measures content. Use lui:units for spacing that adapts to terminal cells and graphical pixels."
     "(lui:row (:width (lui:grow)
           :height (lui:grow) :gap (lui:units 1))
  (lui:panel (:id :navigation
              :width (lui:fixed (lui:units 24))
              :height (lui:grow)
              :scroll-p t :scrollbar-p t)
    (lui:label \"Navigation\"))
  (lui:panel (:width (lui:grow) :height (lui:grow))
    (lui:label \"Content\")))"
     "In a table, :gap separates rows and :column-gap separates columns. Cell :padding insets the widgets inside that cell."
     "(lui:table (:gap 8 :column-gap 12)
  (lui:table-row ()
    (lui:table-cell (:padding 4)
      (lui:label \"Name\"))
    (lui:table-cell (:padding 4)
      (lui:label \"Status\"))))"
     "lui:spacer reserves empty space without painting. Use (lui:spacer :width (lui:grow)) in a row, or :height (lui:grow) in a column, to push siblings apart. Use fixed sizes for explicit spacing. (lui:hr) and (lui:vr) draw horizontal and vertical rules; their long axis grows, their thickness defaults to one backend coordinate, and :foreground overrides the palette border color. Container :padding reserves an inner content area. :gap separates children; :align controls the main axis and :cross-align controls the other axis. :clip-p clips children to the padded content area. :scroll-p adds scrolling with the same clipping rules."
     "Scrolling panels show a scrollbar by default. :scrollbar-p NIL hides it; :scrollbar-width customizes the reserved track width in backend coordinates. The default is 12 graphical pixels or one terminal cell. Drag the thumb to move continuously, or click the track above/below it to page by a viewport. Wheel scrolling supports momentum; nested scrollers pass unused motion to an ancestor."
     "A scrolling viewport needs a bounded size. A panel can scroll with its default call-site ID. Nested scrollers pass wheel input to an ancestor when they cannot scroll further. lui:previous-box exposes completed geometry; lui:scroll-position and scroll-to support application-controlled navigation. Virtualize very large lists instead of declaring every row.")
    (:toolkits "Toolkits"
      "The lui package contains application controls, layout, palettes, toolkit registration, and events. Palette accessors live in lui.palette; toolkit registration, rendering policies, and resolved defaults live in lui.toolkit. Both are included in lui/core. Internal-only packages have a leading %, such as %lui.frame. In dual-use packages, only internal exported symbols have a leading %, such as lui.toolkit:%find-toolkit. These internal interfaces are not application APIs. Everyday palette construction, presets, and palette/toolkit scopes stay in lui. Built-in defaults belong to their own packages, such as lui.qt:*qt-defaults*. Other specialized APIs live in lui.font (font configuration and metrics), lui.draw (custom painting and geometry), lui.debug (inspection), lui.terminal (snapshots), and lui.pdf (PDF output); load the corresponding optional systems before calling them. Choose a toolkit below the heading to try its widgets independently of the page style. Glass uses rounded translucent surfaces; Motif uses solid beveled controls; Garnet uses high-contrast square shapes, hard shadows, and bold monospace text. macOS uses warm surfaces, rounded controls, subtle borders, and blue accents; Qt uses restrained raised desktop controls. Cycle palette to try Default, Light, Dark, Ocean, and Forest on the page and live samples. A window background remains opaque."
     "(lui:with-toolkit (:motif)
  (lui:button \"OK\" :id :ok))
(lui:with-toolkit (:garnet)
  (lui:label \"A different toolkit\"))"
      "lui:with-toolkit chooses defaults and control implementations for a lexical drawing scope. Nested scopes restore the previous toolkit. Use lui:with-palette with :ocean to apply a built-in color theme without changing geometry. lui:available-palettes lists the presets. lui:current-toolkit returns the current name; lui.toolkit:toolkit-defaults exposes its inherited options."
      "Custom toolkits register defaults, a parent, control overrides, and shared geometry and painting callbacks. Use lui.toolkit:define-toolkit or lui.toolkit:register-toolkit; the API reference shows their exact signatures. Backend implementations may approximate optical effects differently: X11 and Wayland share the OpenGL renderer through GLX/EGL, while Cocoa uses whole-window material.")
    (:input "Input and inspection"
     "Tab and Shift-Tab move keyboard focus. Enter and Space activate a focused button, checkbox, or tab; Space inserts a space in an editor. Pointer clicks do not display a keyboard focus ring. Arrow keys navigate tabs."
     "When implementing a draggable control, handle :cancel by clearing its drag state. event-buttons reports the physical buttons on pointer motion when the backend knows them. Zero means all buttons are up, bit 0 means primary, bit 1 means secondary, and NIL means unknown."
     "Keycodes are self-valued constants in lui.key: use (lui:key-pressed-p lui.key:enter), rather than keyword keycodes. Enter remains observable while activating a focused control. Key polling is independent of focus and event consumption. lui.key:key is the key type; lui.key:char->key and lui.key:key->char provide US-layout character conversions. Always qualify key constants with lui.key:."
     "Text editing uses Readline shortcuts: Ctrl-A/E move to the beginning/end, Ctrl-B/F move by character, Alt-B/F move by word, Ctrl-D deletes, Ctrl-H backspaces, Ctrl-K/U/W kill text, and Ctrl-Y yanks it. Ctrl-Shift-A or Command-A selects all where supported. Ctrl-D does not quit."
     "Load the optional lui/debug system and call (lui.debug:set-debugger-enabled t) on a toggle action in your drawing function to attach a debugger to the current context. It displays the completed application tree, bounds, clipping, sizing, style, and text. Call (lui.debug:set-debugger-enabled nil) to close it. Debugger nodes are excluded from its own tree."
     "Clipboard and IME completeness vary by backend; full text shaping is not implemented. Native Wayland, X11, Windows, Cocoa, browser canvas, and raw terminal input use their own platform facilities. Check the project's current test matrix before assuming an untested platform configuration is verified.")
    (:backends "Backends and running"
     "Native: load lui/wayland or lui/x11 on Linux, lui/win32 on Windows, or lui/cocoa on macOS. X11 uses GLX and Wayland uses EGL with the shared OpenGL renderer; Windows and macOS use native drawing/compositing APIs. Font lookup searches lui.font:*font-directories* using the family/weight filenames in lui.font:*font-names*. LUI_FONT_DIR adds a preferred search directory. Pass a TrueType path to open-font or set lui.font:*font-path* (or LUI_FONT) to override the base face, and set lui.font:*font-paths* for additional family/weight faces. The offscreen OpenGL system also supports rendering tests."
     "Browser: make web-demo compiles the same gallery callback with JSCL and serves it locally. The web backend uses a high-DPI canvas for widgets and selectable HTML text for visible labels. Use make docs for the native docs browser, make docs-html for a standalone ECL/WebAssembly build/docs.html, and make docs-pages to refresh docs/index.html for hosting."
     "Terminal: make terminal-demo loads lui/terminal. Uncursed handles terminal cells, Unicode widths, colors, input decoding, and incremental output; LUI maps widgets and events onto it. Plain snapshots also require lui/terminal. Terminal coordinates are cells; graphical coordinates are pixels."
     "Build commands use GNU Make, Bash, and SBCL. Python is used by the existing integration tests and local web server. make test PLATFORM=core runs portable checks; native, gl, and platform-specific targets cover additional paths. See AGENTS.md for configuration, source registry setup, and platform validation guidance.")))

(defstruct browser
  (demo (%lui.example.demo:make-demo) :type function)
  (demo-p nil :type boolean)
  (clicks 0 :type integer) (panel-clicks 0 :type integer)
  (date nil :type (or null string))
  (confirm-p nil :type boolean)
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
  (min (lui:units (if (< (lui:frame-width)
            (lui:units 105)) 18 28))
       (* 0.3 (lui:frame-width))))

(defun reference-width ()
  (if (>= (lui:frame-width) (lui:units 80))
      (min (lui:units 40)
           (* 0.44 (- (lui:frame-width)
                      (navigation-width) (lui:units 4))))
      (- (lui:frame-width) (navigation-width)
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
         (key (list width (lui:current-toolkit)
                    (lui.toolkit:toolkit-revision) lui:*unit*
                    (lui:text-mode-p))))
    (unless (equal key (browser-row-key state))
      (let* ((text-p (lui:text-mode-p))
             (inset (if text-p 0 24)) (gutter (if text-p 1 12))
             (available (max 1 (- width (lui:units 1) gutter inset)))
             (top 0))
        (flet ((probe (text)
                 (lui:measure-label text :font-family :monospace)))
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
  (lui:panel (:id :docs-navigation
              :width (lui:fixed (navigation-width))
              :height (lui:grow) :scroll-p (not
          (lui:page-scroll-p))
              :padding (lui:units 1)
              :gap (lui:units 0.5) :opacity 1 :frost 0)
    (lui:label "Guides")
    (dolist (guide *guides*)
      (when
        (lui:list-item
          (if (< (lui:frame-width) (lui:units
                  105))
                               (case (first guide)
                                 (:start "Start") (:retained "Retained UI") (:debug "Debugger")
                                 (:frames "Frames") (:positioning "Positioning")
                                 (:widgets "Controls") (:layout "Layout")
                                 (:menus "Menus") (:dialogs "Dialogs")
                                 (:toolkits "Toolkits") (:input "Input")
                                 (:backends "Backends")
                                 (otherwise (second guide)))

                               ;; else
                               (second guide))
          :id (list :docs-guide (first guide))
          :width (lui:grow)
          :selected-p (eq (browser-guide state) (first guide)))
        (setf (browser-guide state) (first guide)
              (browser-symbols-p state) nil)
        (lui:scroll-to :docs-detail 0 0)))
    (when
      (lui:list-item
        "Live widgets"
        :id '(:docs-guide :previews)
        :width (lui:grow)
        :selected-p (eq (browser-guide state) :previews))
      (setf (browser-guide state) :previews
            (browser-symbols-p state) nil)
      (lui:scroll-to :docs-detail 0 0))
    (lui:label "API reference")
    (dolist (package (cons nil (browser-packages state)))
      (when
        (lui:list-item
                           (or package "All packages")
          :id (list :docs-package package)
          :width (lui:grow)
          :selected-p
                                    (and (null (browser-guide state))
                                         (equal package
                                                (browser-package state))))
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
      (when (lui:page-scroll-p)
        (lui:scroll-page-to 0))
      (lui:request-frame))))

(defun entry-list (state height)
  (lui:panel (:id :docs-entries :width (lui:grow) :height height
              :scroll-p (not (lui:page-scroll-p))
              :padding (lui:units 0.5) :opacity 1 :frost 0)
    (let* ((rows (symbol-rows state)) (count (length rows))
           (viewport (lui:previous-box :docs-entries))
           (page-p (lui:page-scroll-p))
           (offset (if page-p
                       (if viewport
                           (- (lui:page-scroll-position)
                              (lui:box-y viewport) (lui:units 0.5))
                           0)
                       (nth-value 1 (lui:scroll-position :docs-entries))))
           (bottom (+ offset (if page-p
                                 (lui:viewport-height)
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
      (lui:spacer :height (lui:fixed (if (< start count)
                                           (third (aref rows start)) total)))
      (loop :for i :from start :below end
            :for (index caption top height) := (aref rows i)
            :do
        (lui:list-item
          caption
          :id (list :docs-entry index)
          :width (lui:grow)
          :height (lui:fixed height)
          :font-family :monospace
          :selected-p
                          (and (null (browser-guide state))
                               (= index (browser-selected state)))))
      (lui:spacer :height (lui:fixed (- total (if (plusp end)
                                               (+ (third (aref rows (1- end)))
                                                  (fourth (aref rows (1- end))))
                                               0))))
      (when (zerop count) (lui:label "No matching entries.")))))

(defparameter *preview-kinds*
  '(("DATE-PICKER" . :date-picker)
    ("LABEL" . :label) ("BUTTON" . :button) ("TAB" . :tab)
    ("CHECKBOX" . :checkbox) ("SLIDER" . :slider)
    ("TEXT-FIELD" . :text-field) ("CELL" . :cell)
    ("LIST-ITEM" . :list-item) ("GAUGE" . :gauge) ("CANVAS" . :canvas)
    ("PANEL" . :panel) ("ROW" . :row) ("COLUMN" . :column)
    ("SPACER" . :spacer) ("HR" . :hr) ("VR" . :vr)
    ("SPINNER" . :spinner) ("MENU" . :menu) ("MENU-BAR" . :menu)
    ("POPUP" . :popup) ("CONFIRM" . :confirm)
    ("MENU-ITEM" . :menu) ("FLOATING-EXPANDER" . :floating-expander)))

(defun canvas-preview (state)
  (let ((box (lui:previous-box :docs-preview-canvas)))
    (when box
      (loop for event across (lui:events-for :docs-preview-canvas) do
        (when (and (eq (lui:event-kind event) :press)
                   (eq (lui:event-button event) :primary))
          (push (list (/ (- (lui:event-x event) (lui:box-x box)) lui:*unit*)
                      (/ (- (lui:event-y event) (lui:box-y box)) lui:*unit*))
                (browser-circles state)))))
    (lui:canvas
                (loop :for (x y) :in (browser-circles state)
            :collect (list :circle (lui:units x) (lui:units y) (lui:units 1)
                                     "#258bff" "#a7caff"))
      :id :docs-preview-canvas
      :width (lui:grow)
      :height (lui:fixed (lui:units 8))
      :background "#ffffff"))
  (lui:label "Click the canvas to add a circle." :width (lui:grow)))

(defun preview (state kind)
  (lui:label (format nil "Live preview: ~A" (string-downcase
                                             (symbol-name kind)))
    :id kind :width (lui:grow) :font-weight :bold)
  (case kind
    (:date-picker
      (setf (browser-date state)
        (lui:date-picker :id :docs-date :value (browser-date
                state))))
    (:label (lui:label "A label wraps naturally as the window narrows."
              :width (lui:grow)))
    (:button
      (when
        (lui:button "Try this button" :id :docs-preview-button)
       (incf (browser-clicks state)))
     (lui:label (format nil "Button clicks: ~D" (browser-clicks state))))
    (:checkbox
     (setf (browser-checked-p state)
        (lui:checkbox
          "Enable the example"
          :id :docs-preview-checkbox
          :value (browser-checked-p state))))
    (:slider
     (setf (browser-value state)
        (lui:slider
          :id :docs-preview-slider
          :value (browser-value state)
          :width (lui:grow)))
      (lui:label (format nil "Value: ~D%" (round (* 100 (browser-value
                  state))))))
    (:text-field
     (setf (browser-text state)
        (lui:text-field
          :id :docs-preview-text
          :value (browser-text state)
          :width (lui:grow)))
     (lui:label (format nil "~D characters" (length (browser-text state)))))
    (:tab
     (lui:row (:width (lui:grow) :gap (lui:units 0.5))
       (dolist (item '(:one :two))
          (when
            (lui:tab
                        (if (eq item :one) "First tab" "Second tab")
              :id (list :docs-preview-tab item)
              :selected-p (eq item (browser-tab state)))
           (setf (browser-tab state) item)
           (lui:request-frame))))
     (lui:label (if (eq (browser-tab state) :one)
                    "First page is selected." "Second page is selected.")))
    (:list-item
     (dolist (item '(:one :two))
        (when
          (lui:list-item
                            (if (eq item :one) "First item" "Second item")
            :id (list :docs-preview-item item)
            :width (lui:grow)
            :selected-p (eq item (browser-item state)))
         (setf (browser-item state) item)
         (lui:request-frame))))
    (:cell
      (when
        (lui:cell
          "Cell A1"
          :id :docs-preview-cell
          :width (lui:fixed (lui:units 16))
          :selected-p (browser-cell-p state))
       (setf (browser-cell-p state) (not (browser-cell-p state)))
       (lui:request-frame)))
    (:gauge
      (lui:gauge
        (browser-value state)
        :id :docs-preview-gauge :width (lui:grow))
      (when
        (lui:button "Advance progress" :id :docs-preview-progress)
       (setf (browser-value state)
             (if (>= (browser-value state) 1) 0
                 (min 1 (+ (browser-value state) 0.2))))
       (lui:request-frame)))
    (:spinner
     (lui:row ()
       (lui:spinner)
       (lui:label "Loading")))
    (:menu
     (lui:menu-bar ()
       (lui:menu "File" ()
         (when (lui:menu-item "New") (incf (browser-value state)))
         (lui:menu "Export" ()
           (when (lui:menu-item "PDF") (incf (browser-value state)))))
       (lui:menu "Edit" ()
         (lui:menu-item "Unavailable" :disabled-p t))
       (when (lui:menu-item "Customers") (incf (browser-value state))))
     (lui:label (format nil "Actions: ~D" (round (browser-value state)))))
    (:popup
     (when (lui:button "Show error")
       (lui:popup "Could not save the file." :title "Save failed")))
    (:confirm
     (when (lui:button "Delete example")
       (setf (browser-confirm-p state) t))
     (when (browser-confirm-p state)
       (case (lui:confirm "Delete this order?" :confirm-label "Delete")
         (:confirm
          (setf (browser-confirm-p state) nil)
          (incf (browser-clicks state)))
         (:cancel (setf (browser-confirm-p state) nil))))
     (lui:label (format nil "Confirmed: ~D" (browser-clicks state))))
    (:floating-expander
     (lui:floating-expander "Options" ()
       (lui:label "Ordinary controls in a floating pane")
       (setf (browser-value state)
             (lui:slider :value (browser-value state)
               :width (lui:fixed (lui:units 20))))
       (lui:floating-expander "More options" ()
         (lui:label "Nested floating content"))))
    (:canvas (canvas-preview state))
    (:spacer
     (lui:row (:width (lui:grow))
       (lui:label "Left")
       (lui:spacer :width (lui:grow))
       (lui:label "Right")))
    (:hr (lui:hr))
    (:vr
     (lui:row (:width (lui:grow) :gap (lui:units 1))
       (lui:label "Before")
       (lui:vr)
       (lui:label "After")))
    (:panel
      (lui:panel (:width (lui:grow) :padding (lui:units 1) :gap
            (lui:units 0.5))
       (lui:label "A panel groups and styles its children."
         :width (lui:grow))
        (when (lui:button "Panel action" :id
                                           :docs-preview-panel)
         (incf (browser-panel-clicks state)))
       (lui:label (format nil "Panel actions: ~D"
                          (browser-panel-clicks state)))))
    (:row
        (lui:row (:width (lui:grow) :gap (lui:units 1) :cross-align
          :center)
          (lui:label "Left" :width (lui:grow))
          (lui:label "Center" :width (lui:grow))
          (lui:label "Right" :width (lui:grow))))
    (:column
        (lui:column (:width (lui:grow) :gap (lui:units 0.5))
          (lui:label "First child")
          (lui:label "Second child")
          (lui:label "Third child")))))

(defparameter *toolkit-packages*
  '(("lui.glass" . :glass) ("lui.motif" . :motif) ("lui.garnet" . :garnet)
    ("lui.macos" . :macos) ("lui.qt" . :qt)))

(defun toolkit-sample (state toolkit)
  (lui:with-toolkit (toolkit)
    (lui:panel (:width (lui:grow) :padding (lui:units 1) :gap
          (lui:units 1)
                :opacity 1)
      (lui:label (case toolkit (:macos "macOS") (:qt "Qt")
                   (otherwise (string-capitalize (symbol-name toolkit)))))
      (when (lui:button "Try this button" :id
                                            :docs-sample-button)
        (incf (browser-clicks state)))
      (setf (browser-checked-p state)
        (lui:checkbox
          "Enable the example"
          :id :docs-sample-check :value (browser-checked-p state)))
      (lui:label (format nil "Button clicks: ~D" (browser-clicks state))))))

(defun entry-preview-kind (entry)
  (when (member (getf entry :package)
                '("lui" "lui.glass" "lui.motif" "lui.garnet"
                  "lui.macos" "lui.qt")
                :test #'string=)
    (cdr (assoc (getf entry :name) *preview-kinds* :test #'string-equal))))

(defun detail (state)
  (lui:panel (:id :docs-detail :width (lui:grow) :height (lui:grow)
              :scroll-p (not (lui:page-scroll-p)) :padding (lui:units 1) :gap (lui:units 1)
              :opacity 1 :frost 0)
    (cond
      ((eq (browser-guide state) :previews)
       (lui:label "Interactive widgets and containers"
         :width (lui:grow) :font-weight :bold)
       ;; Related API entries share one example in the combined gallery.
       (dolist (kind (remove-duplicates (mapcar #'cdr *preview-kinds*)
                                        :from-end t))
         (preview state kind)))
      ((browser-guide state)
       (let ((guide (assoc (browser-guide state) *guides*)))
         (lui:label (second guide)
           :width (lui:grow) :font-weight :bold)
         (when (eq (browser-guide state) :toolkits)
           (lui:row (:width (lui:grow) :gap (lui:units 0.5))
             (dolist (pair *toolkit-packages*)
               (let ((name (cdr pair)))
                 (when
                    (lui:tab
                                (case name (:macos "macOS") (:qt "Qt")
                        (otherwise (string-capitalize (symbol-name name))))
                      :id (list :docs-sample name)
                      :selected-p (eq name (browser-sample state)))
                   (setf (browser-sample state) name)))))
           (toolkit-sample state (browser-sample state)))
         (when (eq (browser-guide state) :debug)
           (when
              (lui:button
                "Open debugger"
                :id :docs-open-debug
                :disabled-p (lui.debug:debugger-enabled-p))
             (lui.debug:set-debugger-enabled t)))
         (dolist (paragraph (cddr guide))
           (lui:label paragraph
             :id paragraph :width (lui:grow)
             :font-family
                               (if (and (plusp (length paragraph))
                                        (char= (char paragraph 0) #\())
                                   :monospace :sans-serif)))))
      (t
       (let ((index (browser-selected state)))
         (if index
             (let ((entry (aref (browser-entries state) index)))
               (lui:label (entry-title entry)
                 :width (lui:grow) :font-weight :bold)
               (lui:label (string-downcase
                           (symbol-name (getf entry :kind :function))))
               (lui:label (or (getf entry :signature) "")
                 :width (lui:grow) :font-family :monospace)
               (lui:label (or (getf entry :documentation)
                              "No docstring is available for this entry.")
                 :width (lui:grow))
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
          :id :docs-search
          :value (browser-query state)
          :width (lui:grow))))
    (unless (equal query (browser-query state))
      (setf (browser-query state) query (browser-guide state) nil
            (browser-symbols-p state) t)
      (update-matches state)))
  (lui:label (format nil "~D API entries" (length (browser-matches state)))))

(defun references (state)
  (lui:column (:width (lui:fixed (reference-width)) :height (lui:grow)
               :gap (lui:units 0.5))
    (search-reference state)
    (entry-list state (lui:grow))))

(defun draw-reference (state)
  (select-reference state)
  (lui:with-toolkit ((browser-toolkit state))
   (lui:with-palette ((browser-palette state))
    (lui:panel (:width (lui:grow) :height (lui:grow)
                :background
                        (let ((colors (lui.toolkit:toolkit-palette)))
                            (getf colors :window-background (getf colors
                  :background)))
                :opacity 1 :frost 0 :radius 0
                :padding (lui:units 1) :gap (lui:units 1))
      (lui:row (:width (lui:grow) :gap (lui:units 1) :cross-align
        :center)
        (lui:label "LUI documentation"
          :font-weight :bold :width (lui:grow))
        (when (lui:button "View Full Demo" :id :docs-demo)
          (setf (browser-demo-p state) t))
        (when (lui:button "Show Debugger" :id :docs-debug)
          (lui.debug:set-debugger-enabled t)))
      (lui:row (:width (lui:grow) :gap (lui:units 3)
                :cross-align :center)
        (lui:row (:gap (lui:units 1) :cross-align :center)
          (lui:label (ecase (browser-toolkit state)
                      (:glass "Toolkit: Glass") (:motif "Toolkit: Motif")
                      (:garnet "Toolkit: Garnet") (:macos "Toolkit: macOS")
                      (:qt "Toolkit: Qt")))
          (when (lui:button "Cycle Toolkit" :id :docs-toolkit)
            (setf (browser-toolkit state)
                  (case (browser-toolkit state)
                    (:glass :motif) (:motif :garnet) (:garnet :macos)
                    (:macos :qt) (otherwise :glass)))
            (lui:request-frame)))
        (lui:row (:gap (lui:units 1) :cross-align :center)
          (lui:label (format nil "Palette: ~A"
                             (string-capitalize
                              (symbol-name (browser-palette state)))))
          (when (lui:button "Cycle Palette" :id :docs-palette)
            (let ((names (lui:available-palettes)))
              (setf (browser-palette state)
                    (aref names
                          (mod (1+ (position (browser-palette state) names))
                               (length names)))))
            (lui:request-frame))))
      (lui:label (lui:frame-rate-label))
      (lui:row (:width (lui:grow) :height (lui:grow) :gap (lui:units
        1))
        (navigation state)
          (if (>= (lui:frame-width) (lui:units
                  80))
            (progn (references state) (detail state))
            (lui:column (:width (lui:grow) :height (lui:grow) :gap
              (lui:units
                    0.5))
              (search-reference state)
              (when
                (lui:button
                                (if (browser-symbols-p state)
                                    "Read selected" "Browse symbols")
                  :id :docs-symbols :width (lui:grow))
                (setf (browser-symbols-p state)
                      (not (browser-symbols-p state))))
              (if (browser-symbols-p state)
                  (entry-list state (lui:grow))
                  (detail state)))))))))

(defun draw-docs (state)
  "Draw the reference or the shared gallery, preserving both models."
  (if (browser-demo-p state)
      (lui:column (:width (lui:grow) :height (lui:grow))
        (when (lui:button "Back to documentation"
                :id :docs-back)
          (setf (browser-demo-p state) nil))
        (funcall (browser-demo state)))

      ;; else
      (draw-reference state)))

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
