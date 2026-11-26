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
      "Load lui/retained alongside your backend to describe an interface as mutable structures. Call lui.retained:draw inside the callback passed to lui:run. A tree can be declared once with DEFPARAMETER and edited through typed slot accessors. LUI still solves layout and routes input each frame."
      "(asdf:load-system \"lui\")
(asdf:load-system \"lui/retained\")

(defparameter *greeting*
  (lui.retained:make-label \"Hello!\"))
(defun say-hello ()
  (setf (lui.retained:label-text *greeting*)
        \"Hello from retained data!\"))

(defparameter *ui*
  (lui.retained:make-column :gap (lui:units 1)
   :children
   (cl:vector
    *greeting*
    (lui.retained:make-button \"Say hello\"
                       :on-activate 'say-hello))))

(lui:run (lambda () (lui.retained:draw *ui*)))"
      "Each widget has its own standard DEFSTRUCT and constructor: MAKE-LABEL, MAKE-BUTTON, MAKE-TEXT-FIELD, MAKE-SLIDER, MAKE-COLUMN and so on. Constructors take the same required arguments in the same order as immediate controls: (make-label text &key ...), (make-radio choice text &key ...), (make-searchable-combobox choices &key ...), (make-gauge fraction &key ...) and (make-canvas commands &key ...). Remaining options are keywords. SLIME can show the arguments specific to that widget. Use SETF with LABEL-TEXT, BUTTON-ON-ACTIVATE, TEXT-FIELD-VALUE, SLIDER-MINIMUM or COLUMN-CHILDREN. Unrelated slots are absent: a button has no children or slider limits. Shared placement and appearance slots remain available through each widget's accessors. NODE is only the common base type, with no constructor or kind slot. The package nickname LUIR is available. Containers accept a single child node or a vector of nodes, for example (luir:make-column :children (luir:make-label \"Hello\")); use CL:VECTOR for multiple children or an empty collection. DRAW accepts a single root or a vector of roots. The generic NODE constructor and list forms are retired."
      "All nodes accept :visible-p, defaulting to T. Create a spinner with (luir:make-spinner :visible-p nil), then use (setf (luir:visible-p spinner) t) to show it. Hidden subtrees occupy no layout space, receive no input and schedule no animation. Their stored objects remain intact, but focus, capture and scoped LUI-owned state are cleaned up as when controls are removed. Use (setf (luir:children status) spinner) to replace any container's children, or (setf (luir:children status) (vector)) to clear it. CHILDREN applies to containers, not leaves; existing per-container accessors also remain available."
      "Unkeyed nodes preserve their object identity when reordered within the same parent. Reconstructing an unkeyed node creates a new widget. Use :id to share identity between reconstructed nodes, and keep those keys unique among siblings. A node cannot appear twice in the same parent. Containers scope identities, so moving a node to another parent starts new state. Supply distinct DRAW :id values for separate trees in the same scope."
      "Value slots update automatically to the current control result before any callbacks run, even without ON-CHANGE. Retained value slots have sensible defaults even before the first DRAW: text fields and searchable comboboxes use the empty string, sliders use 0, checkboxes use NIL (unchecked), radio controls use NIL (initial selection), and date pickers use NIL (no date). A submit callback can read current values directly. Omitting :value uses scoped LUI-owned state initialized by DEFAULT-VALUE. Supplying a non-NIL :value or editing the slot supplies an application value; assigning NIL returns to owned state. Automatic write-back preserves ownership, including NIL results. A node shared across scopes exposes its last drawn value. Other option slots default to NIL; assigning NIL restores defaults, including boolean options. Removing a control for a completed frame releases its owned state. LUI:UNITS returns a typed deferred amount, so (lui:units 1) works in padding and other dimensions even when the tree is built at load time. The active backend resolves it during declaration without changing the stored value. Width and height accept numbers, units, or sizing policies such as (lui:grow) and (lui:fixed (lui:units 4)). FIT and GROW bounds also accept units. Plain numbers remain backend coordinates; use LUI:RESOLVE-UNITS explicitly when numeric arithmetic is needed."
      ":on-activate takes a zero-argument function; :on-change receives the new value. Either may be a symbol: SYMBOL-FUNCTION is looked up at dispatch, so redefinitions affect existing nodes. DRAW queues callbacks during traversal, then invokes them in order after successful traversal and requests another frame. Callbacks may update slots or replace children; changes appear next frame. Traversal errors discard queued callbacks, and callback errors stop dispatch without undoing earlier edits."
      "Run make retained-demo (or make retained-demo PLATFORM=terminal) to try nested layouts, editable keyed rows, live slot changes, toolkit/palette switching, and FPS. The module has no additional core dependencies. Browser application builds must explicitly include it. Structures avoid decoding list nodes during drawing; this is not a cross-backend performance guarantee.")
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
     "All layout containers (row, column, panel, table, table-row and table-cell) accept :clickable-p, :disabled-p and :accessible-name. Browser actions use :accessible-name, falling back to the declared ID. Disabled descendants block ancestor clicks while their enabled children remain interactive. Every container returns two values: activation and its resolved ID; BODY values are discarded. Clickable containers activate on primary-button release over the captured target, or Enter/Space after Tab focus. Their hit area includes padding, gaps and passive descendants, clipped to visible bounds. The deepest interactive child wins; activation never bubbles. :disabled-p disables only the container and blocks clicks through to clickable ancestors; children remain independently enabled. Clicks preserve keyboard focus by default. Keyboard focus gets an outline graphically and underlining in the terminal."
     "(lui:table (:column-gap 12)
  (when (lui:table-row (:id customer-id :clickable-p t)
          (lui:table-cell () (lui:label customer-name))
          (lui:table-cell () (lui:label customer-email)))
    (open-customer customer-id)))"
     "Retained containers share this behavior: :on-activate implies clickability; :clickable-p t enables it without a callback. Callbacks take no arguments and run after successful DRAW traversal, so edits appear next frame. Each container exposes mutable CLICKABLE-P, DISABLED-P and ON-ACTIVATE accessors."
     "(luir:make-table-row
 :id customer-id
 :on-activate (lambda () (open-customer customer-id))
 :children
 (vector
  (luir:make-table-cell :children (luir:make-label customer-name))
  (luir:make-table-cell :children (luir:make-label customer-email))))"
     "In a table, :gap separates rows and :column-gap separates columns. Cell :padding insets the widgets inside that cell."
     "(lui:table (:gap 8 :column-gap 12)
  (lui:table-row ()
    (lui:table-cell (:padding 4)
      (lui:label \"Name\"))
    (lui:table-cell (:padding 4)
      (lui:label \"Status\"))))"
     "lui:spacer reserves empty space without painting. Use (lui:spacer :width (lui:grow)) in a row, or :height (lui:grow) in a column, to push siblings apart. Use fixed sizes for explicit spacing. (lui:hr) and (lui:vr) draw horizontal and vertical rules; their long axis grows, their thickness defaults to one backend coordinate, and :foreground overrides the palette border color. Container :padding reserves an inner content area. Built-in graphical panels default to 2 units of padding so child backgrounds do not cover their borders. Explicit :padding takes precedence, including zero for edge-to-edge contents. Custom toolkits can set :panel-options, for example (:padding 3), without changing ordinary controls or terminal layout. :gap separates children; :align controls the main axis and :cross-align controls the other axis. :clip-p clips children to the padded content area. :scroll-p adds scrolling with the same clipping rules."
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
     "Native labels and editors support double-click word selection and triple-click paragraph selection (paragraphs end at newlines). Dragging after a repeated click extends by that unit. A label drag may start in nearby empty space inside its containing layout, including below the text. Right-click opens Copy/Paste using the same toolkit menus as application menus; Paste is disabled for labels and Copy requires a selection. Escape or an outside click dismisses the menu. Pass :context-menu-p nil to lui:run to disable the default native menu. Ctrl-C/V (Command-C/V on macOS) use the system clipboard; Ctrl-Y remains the editor kill-buffer command."
     "Text editing uses Readline shortcuts: Ctrl-A/E move to the beginning/end, Ctrl-B/F move by character, Alt-B/F move by word, Ctrl-D deletes, Ctrl-H backspaces, Ctrl-K/U/W kill text, and Ctrl-Y yanks it. Ctrl-Shift-A or Command-A selects all where supported. Ctrl-D does not quit."
     "Load the optional lui/debug system and call (lui.debug:set-debugger-enabled t) on a toggle action in your drawing function to attach a debugger to the current context. It displays the completed application tree, bounds, clipping, sizing, style, and text. Call (lui.debug:set-debugger-enabled nil) to close it. Debugger nodes are excluded from its own tree."
     "Clipboard and IME completeness vary by backend; full text shaping is not implemented. Native Wayland, X11, Windows, Cocoa, browser canvas, and raw terminal input use their own platform facilities. Check the project's current test matrix before assuming an untested platform configuration is verified.")
    (:fonts "Loading native fonts"
     "Load a native backend before evaluating forms that mention lui.font. For example, evaluate (ql:quickload :lui/x11) first on X11, or (ql:quickload :lui/wayland) on Wayland. Loading lui/core or lui/demo alone does not load native fonts or a window backend. A reader error saying the LUI.FONT package does not exist means this loading step is missing; evaluate it separately before reading the configuration forms."
     "On Linux, start with the ordinary run call after loading the backend; font discovery is automatic. The native system loads font-discovery on Linux only. Fontconfig must be available for its system matching fallback; configured file and directory lookup still works when that matching is unavailable."
     "(lui:run (lambda () (lui:label \"Hello world\")) :backend :x11)"
     "Native font lookup first checks specific filenames directly in configured directories, then searches their subdirectories. On Linux it also searches /usr/share/fonts/, /usr/share/Fonts/, /usr/local/share/fonts/, ~/.fonts/, and $XDG_DATA_HOME/fonts/ (default ~/.local/share/fonts/). Fonts under TTF/ are found automatically, including /usr/share/Fonts/TTF/. No font setup is needed when a supported font is installed there. For fonts elsewhere, add a search root before calling lui:run. Linux paths are case-sensitive; use the actual path casing."
     "(pushnew #p\"/usr/share/Fonts/TTF/\"
         lui.font:*font-directories* :test #'equal)
(lui:run (lambda () (lui:label \"Hello world\")) :backend :x11)"
     "Use the directory that actually exists on your machine. The default candidate names include DejaVuSans.ttf, DejaVuSans-Bold.ttf, DejaVuSansMono.ttf, and DejaVuSansMono-Bold.ttf, as well as Liberation and Arial/Courier alternatives. Inspect lui.font:*font-names* for the complete mapping. If filename search finds nothing, Linux uses the font-discovery library and Fontconfig to match installed fonts by family and weight, accepting only standalone TrueType files readable by LUI. Set lui.font:*font-discovery-p* to NIL to disable this step. LUI does not load or call font-discovery on macOS, where its CoreText backend can crash; directory search and explicit overrides remain available there. Windows also keeps directory search. For other filenames on those platforms, set *font-names* or provide explicit file overrides below. You can instead set the LUI_FONT_DIR environment variable before starting Lisp to add one search directory."
     "Lookup order: *font-path* then LUI_FONT override the base face. Otherwise each family/weight checks *font-paths*, direct candidate filenames, recursive directory candidates, then Linux system discovery. Explicit paths are authoritative: a missing override is an error, not a request to substitute a different font. The directory example above is optional for standard Linux locations."
     "To select a specific base TrueType file, bind lui.font:*font-path* around the entire lui:run call, or SETF it before opening the window. Check the file with PROBE-FILE first; NIL means that path was not found. LUI_FONT is the equivalent environment variable, used when *font-path* is NIL."
     "(probe-file #p\"/usr/share/Fonts/TTF/DejaVuSans.ttf\")
(let ((lui.font:*font-path*
        #p\"/usr/share/Fonts/TTF/DejaVuSans.ttf\"))
  (lui:run (lambda () (lui:label \"Hello world\")) :backend :x11))"
     "The base override covers normal sans-serif text only. Bold and monospace faces are resolved separately when requested, so configure their directory too, or supply explicit family/weight overrides in lui.font:*font-paths*. This is an association list whose keys are (family weight) lists and whose values are file pathnames or strings. For example, after loading the backend:"
     "(setf lui.font:*font-paths*
      '(((:sans-serif :normal) .
         #p\"/usr/share/Fonts/TTF/DejaVuSans.ttf\")
        ((:sans-serif :bold) .
         #p\"/usr/share/Fonts/TTF/DejaVuSans-Bold.ttf\")
        ((:monospace :normal) .
         #p\"/usr/share/Fonts/TTF/DejaVuSansMono.ttf\")
        ((:monospace :bold) .
         #p\"/usr/share/Fonts/TTF/DejaVuSansMono-Bold.ttf\")))"
     "Replace these paths with existing TrueType files. A No TrueType font for (:SANS-SERIF :NORMAL) error means the base search found no candidate; the same error for another family/weight identifies the additional face to configure. Configure fonts before opening a window and reopen it after changes: faces are cached for the window lifetime. lui:run manages opening and closing its fonts; applications normally do not need to call open-font themselves. Browser fonts use browser font families, and terminal fonts are chosen by the terminal emulator; these native file settings do not change either.")
    (:backends "Backends and running"
     "Native: load lui/wayland or lui/x11 on Linux, lui/win32 on Windows, or lui/cocoa on macOS. X11 uses GLX and Wayland uses EGL with the shared OpenGL renderer; Windows and macOS use native drawing/compositing APIs. Font lookup searches lui.font:*font-directories* using the family/weight filenames in lui.font:*font-names*. LUI_FONT_DIR adds a preferred search directory. After direct matches, lookup searches subdirectories and the standard Linux system/user font roots, then uses font-discovery/Fontconfig on Linux if needed. Pass a TrueType path to open-font or set lui.font:*font-path* (or LUI_FONT) to override the base face, and set lui.font:*font-paths* for additional family/weight faces. The offscreen OpenGL system also supports rendering tests."
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
  (let ((count (if (< (lui:frame-width)
                      (lui:resolve-units (lui:units 105)))
                   18
                   ;; else
                   28)))
    (min (lui:resolve-units (lui:units count))
         (* 0.3 (lui:frame-width)))))

(defun reference-width ()
  (if (>= (lui:frame-width) (lui:resolve-units (lui:units 80)))
      (min (lui:resolve-units (lui:units 40))
           (* 0.44 (- (lui:frame-width)
                      (navigation-width) (lui:resolve-units (lui:units 4)))))
      (- (lui:frame-width) (navigation-width)
        (lui:resolve-units (lui:units 3)))))

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
             (available (max 1 (- width (lui:resolve-units (lui:units 1)) gutter inset)))
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
          (if (< (lui:frame-width) (lui:resolve-units (lui:units
                  105)))
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
                              (lui:box-y viewport) (lui:resolve-units (lui:units 0.5)))
                           0)
                       (nth-value 1 (lui:scroll-position :docs-entries))))
           (bottom (+ offset (if page-p
                                 (lui:viewport-height)
                                 (if viewport (lui:box-height viewport)
                  (lui:resolve-units (lui:units 18))))))
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
            :collect (list :circle (lui:resolve-units (lui:units x))
                           (lui:resolve-units (lui:units y))
                           (lui:resolve-units (lui:units 1))
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
          (if (>= (lui:frame-width) (lui:resolve-units (lui:units
                  80)))
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
