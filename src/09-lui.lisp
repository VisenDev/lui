(defpackage #:lui
  (:use #:cl #:%lui.fn #:%lui.widgets #:%lui.frame)
  (:import-from #:lui.palette
                #:palette #:palette-p #:make-palette #:available-palettes
                #:call-with-palette #:with-palette #:+palette-default+
                #:+palette-light+ #:+palette-dark+ #:+palette-ocean+
                #:+palette-forest+)
  (:import-from #:lui.toolkit
                #:register-toolkit #:toolkit-defaults #:define-toolkit
                #:current-toolkit #:call-with-toolkit #:with-toolkit
                #:control #:%*toolkit* #:%*toolkit-definition* #:%find-toolkit
                #:%override #:%without-option)
  (:import-from #:%lui.conditions
                #:lui-error #:configuration-error #:backend-error #:font-error
                #:frame-state-error #:error-operation #:error-setting
                #:error-value
                #:error-backend #:error-font-request)
  (:import-from #:%lui.layout
                #:units #:units-p #:units-count #:resolve-units #:*unit*
                #:position-mode
                #:object-id #:point #:contour #:contours #:sizing #:fit #:grow
                #:fixed #:percent #:box
                #:make-box #:box-x #:box-y #:box-width #:box-height
                #:element-box
                #:element-content)
  (:import-from #:%lui.frame
                #:frame-rate-limit #:set-frame-rate-limit
           #:frame-rate-label #:frame-width #:frame-height #:text-mode-p
           #:focused-widget #:focus-visible-p #:events-for #:page-scroll-p
           #:page-scroll-position #:viewport-height #:scroll-page-to
           #:previous-frame-box
                #:call-with-frame #:call-with-key
                #:with-frame #:frame-time #:request-frame
                #:previous-box
                #:parent-scroll-position #:scroll-position #:scroll-to
                #:activated-p #:activated-ids
                #:hovered-p
                #:event #:event-kind #:event-x #:event-y #:event-id
                #:event-value
                #:event-key #:event-button #:event-buttons #:event-clicks
                #:event-dragging-p)
  (:import-from #:%lui.widgets
                #:declare-widget #:widget-text)
  ;; Application controls and layout live here; specialized APIs are exported
  ;; by their owning font, drawing, debugger, and backend packages.
  (:export
           #:frame-rate-limit #:set-frame-rate-limit
           #:frame-rate-label #:frame-width #:frame-height #:text-mode-p
           #:focused-widget #:focus-visible-p #:events-for #:page-scroll-p
           #:page-scroll-position #:viewport-height #:scroll-page-to
           #:previous-frame-box #:measure-label
           #:lui-error #:configuration-error #:backend-error #:font-error
           #:frame-state-error #:error-operation #:error-setting
           #:error-value #:error-backend #:error-font-request
           #:key-pressed-p #:text-input-event #:visible-span #:list-index
           #:reveal-rect #:take-events #:event-targets #:reset-editor
           #:edit-value #:mount #:unmount #:refresh #:position-mode
           #:object-id #:point #:contour #:contours #:sizing #:fit #:grow
           #:fixed #:percent #:box #:make-box #:box-x #:box-y #:box-width
           #:box-height #:element-box #:element-content #:row #:column
           #:with-frame #:frame-time #:request-frame #:previous-box
           #:parent-scroll-position #:scroll-position #:scroll-to
           #:activated-p #:activated-ids #:hovered-p #:event #:event-kind
           #:event-x #:event-y #:event-id #:event-value #:event-key
           #:event-button #:event-buttons #:event-clicks #:event-dragging-p
           #:declare-widget #:widget-text #:run #:register-backend
           #:available-backends #:units #:units-p #:units-count
           #:resolve-units
           #:*backend* #:call-with-frame
           #:call-with-key #:call-with-toolkit #:call-with-palette #:*unit*
           #:with-toolkit #:with-palette #:widget-color #:current-toolkit
           #:available-palettes #:palette #:palette-p #:make-palette
           #:+palette-default+ #:+palette-light+ #:+palette-dark+
           #:+palette-ocean+ #:+palette-forest+ #:control #:table
           #:table-row #:table-cell #:with-key #:widget-key #:widget-id
           #:focus-widget #:panel #:label #:spacer #:hr #:vr #:button
           #:tab #:checkbox #:radio #:slider #:text-field #:cell
           #:list-item #:gauge #:spinner #:canvas #:date-picker
           #:searchable-combobox
           #:popup #:confirm
           #:menu-bar #:menu #:menu-item #:floating-expander
           #:%*default-backend-function*))
(in-package #:lui)

(defvar *backends* (make-hash-table :test 'eq))
(defvar %*default-backend-function* nil
  "A thunk that returns default backend when called.")
(defvar *backend* nil "Default backend override; NIL selects an available backend.")
(fn (register-backend function) ((name symbol) (runner function))
  "Install a runner function under NAME; normally called by a backend."
  (setf (gethash name *backends*) runner))

(fn (available-backends (vector symbol)) ()
  "Return a vector of backend names registered in this Lisp image."
  (let ((results (make-array 1 :element-type 'symbol :initial-element nil
                             :adjustable t :fill-pointer 0)))
    (maphash (lambda (name runner)
               (declare (ignore runner))
               (vector-push-extend name results))
             *backends*)
    results))

(fn (run t)
    ((draw function) &key ((backend symbol) *backend*) ((title string) "LUI")
     ((width (or null real)) nil) ((height (or null real)) nil)
     ((interactive boolean) t) ((min-fps real) 1) ((max-fps (or null real)) 240))
  "Run the same immediate-mode DRAW function on any registered backend.
Backend-specific window, DOM, input, frame, and lifetime management stay in LUI.
WIDTH/HEIGHT are optional backend coordinates; omit them for sensible defaults.
MIN-FPS sets idle redraws per second. MAX-FPS caps input and animation frames;
NIL removes the active limit.
Display/compositor scheduling can still constrain presentation.
INTERACTIVE NIL renders one frame (useful for tests and terminal snapshots)."
  (assert (< 0 min-fps))
  (assert (or (null max-fps) (<= min-fps max-fps)))
  (let* ((%lui.frame:*min-fps* min-fps)
         (%lui.frame:*max-fps* max-fps)
         (name (or backend
                   (and %*default-backend-function*
                        (funcall %*default-backend-function*))
                   (loop :for backend :across (available-backends)
                         :return backend)))
         (runner (gethash name *backends*)))
    (unless runner
      (error '%lui.conditions:configuration-error
             :setting :backend :value name
             :operation :run
             :format-control "Backend ~S is not loaded. Available: ~S"
             :format-arguments (list name (available-backends))))
    (funcall runner draw :title title :width width :height height
             :interactive interactive)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *widget-option-groups*
    '((placement id width height padding position offset-x offset-y)
      (flow align cross-align clip-p scroll-p scrollbar-p scrollbar-width)
      (focus interactive-p keyboard-focus-p pointer-focus-p)
      (activation clickable-p disabled-p)
      (appearance foreground background palette radius frost font-size
                   font-family font-weight opacity accent painter terminal-label
                   terminal-border accessible-name)
      (value value default-value))
    "Shared keyword sets for the public widget signatures."))

(fn (merge-widget-options list) ((options list))
  "Apply explicit widget keywords before a supplied options plist."
  (append (%without-option :options options) (getf options :options)))

(defmacro define-widget-options (name arguments groups keys doc &body body)
  "Define a widget signature. A final &BODY marker groups container keywords."
  (let* ((container (member '&body arguments))
         (positional (remove '&body arguments))
         (keywords (append (loop :for group :in groups
                                 :append (cdr (assoc group *widget-option-groups*)))
                           keys '(options)))
         (signature (list* '&rest 'forms '&key keywords)))
    `(defmacro ,name (,@positional
                     ,@(if container (list signature '&body 'body) signature))
       ,(if (member 'activation groups)
            (concatenate 'string doc
              "
:CLICKABLE-P enables pointer/keyboard activation. :DISABLED-P disables only
this container. Interactive descendants win; activation does not bubble.
Return activation and resolved ID as two values, ignoring BODY values.")
            ;; else
            doc)
       (declare (ignore ,@keywords))
       (let ((options (if (loop :for key :in forms :by #'cddr
                               :thereis (eq key :options))
                          (list 'merge-widget-options (cons 'list forms))
                          ;; else
                          (cons 'list forms))))
         ,@body))))

(fn (container-result (values boolean object-id))
    ((node %lui.layout:element))
  "Return this container's activation and resolved ID after declaring its body.
Clickable containers use release activation and keyboard focus. Interactive
children take precedence; activation never bubbles. Disabled containers block
ancestor clicks while leaving their children enabled. Body values are ignored."
  (let ((id (%lui.layout:element-id node))
        (widget (element-content node)))
    (when (%lui.layout:element-clickable-p node)
      (setf (%lui.layout:element-focus-color node)
            (if (widget-p widget) (widget-accent widget)
                ;; else
                (palette-color (lui.toolkit:toolkit-palette) :accent))))
    (values (and (%lui.layout:element-clickable-p node)
                 (%lui.layout:element-interactive-p node)
                 (activated-p id)) id)))

(define-widget-options row (&body) (placement flow focus activation) (gap)
  "Lay out BODY horizontally. Child identities are scoped to this container;
use a distinct :ID or WITH-KEY scope for each repeated instance."
  `(let ((*parent* (emit
                   (apply #'%lui.layout:make-element :direction :row
                          (container-options ',(gensym "ROW")
                                             ,options)))))
     ,@body
     (container-result *parent*)))

(define-widget-options column (&body) (placement flow focus activation) (gap)
  "Lay out BODY vertically. Child identities are scoped to this container;
use a distinct :ID or WITH-KEY scope for each repeated instance."
  `(let ((*parent* (emit
                   (apply #'%lui.layout:make-element :direction :column
                          (container-options ',(gensym "COLUMN")
                                             ,options)))))
     ,@body
     (container-result *parent*)))

(define-widget-options panel (&body) (placement flow focus activation appearance)
    (gap direction)
  "Draw a styled container and attach widgets declared in BODY as children.
Graphical padding defaults to the toolkit's :panel-options (2 for built-ins),
keeping child backgrounds inside the border. Explicit :padding overrides it.
The call site supplies a stable ID, including for scrolling panels.
Use a distinct :ID or WITH-KEY scope for each repeated instance."
  `(let ((%lui.frame:*parent*
          (%lui.widgets:declare-panel
           %*toolkit*
           (append (%lui.frame:container-options
                    ',(gensym "PANEL") ,options)
                   (toolkit-defaults
                    %*toolkit*
                    (unless (context-text-mode-p *context*) :panel))))))
     ,@body
     (container-result *parent*)))

(fn (widget-options list) ((options list))
  "Remove identity and value ownership options before backend declaration."
  (loop :for (key value) :on options :by #'cddr
        :unless (member key '(:id :value :default-value))
        :append (list key value)))

(fn (widget-option-p boolean) ((key symbol) (options list))
  "Distinguish an explicitly supplied option, including NIL, from an omitted one."
  (loop :for option :in options :by #'cddr :thereis (eq option key)))

(fn (owned-widget-value t) ((id object-id) (options list) (default t))
  "Resolve a controlled value or initialize retained state exactly once."
  (if (widget-option-p :value options)
      (getf options :value)
      ;; else
      (multiple-value-bind (value present)
          (gethash id (context-values *context*))
        (if present value (getf options :default-value default)))))

(fn (invoke-widget (values t t t))
    ((function function) (site symbol) (arguments list) (options list)
     (value-p boolean) (default t))
  "Resolve identity and owned values, invoke the control, and return its ID third."
  (let* ((id (call-site-id site options))
         (appearance (widget-options options))
         (value (when value-p (owned-widget-value id options default))))
    (multiple-value-bind (result changed)
        (apply function id
               (append (when value-p (list value)) arguments
                       (list appearance)))
      (when value-p
        (setf (gethash id (context-values *context*)) result
              changed (not (equal value result))))
      (values result changed id))))

(defmacro define-widget (name arguments keys doc)
  "Define a call-site macro over the corresponding typed internal control function."
  (let ((internal (intern (concatenate 'string "%" (symbol-name name))))
        (value-p (not (null (member 'value arguments))))
        (public (remove 'id (remove 'value arguments)))
        (default (case name
                   ((text-field searchable-combobox) "")
                   (slider 0)
                   (otherwise nil))))
    `(define-widget-options ,name ,public
          (placement appearance ,@(when value-p '(value)))
          ,keys
       ,doc
       (list 'invoke-widget (list 'function ',internal)
             (list 'quote (gensym ,(symbol-name name)))
             (list* 'list (list ,@public)) options ,value-p ,default))))

(defmacro define-control (name args keys doc &body body)
  "Define a public widget macro and a typed implementation with resolved identity."
  (let ((kind (intern (symbol-name name) :keyword))
        (internal (intern (concatenate 'string "%" (symbol-name name)))))
    `(progn
       (fn (,internal t)
           (,@(mapcar (lambda (argument)
                        (list argument
                              (case argument
                                (id 'object-id) (text 'string)
                                (fraction 'real) (commands 'list)
                                (otherwise t)))) args)
            &optional ((options list) nil))
       ,doc
       (let* ((entry (or %*toolkit-definition* (%find-toolkit %*toolkit*)))
              (custom (%override ,kind entry)))
         (if custom (funcall custom ,@args options)
             ;; else
             (let ((style %*toolkit*))
               (multiple-value-bind (defaults palette) (toolkit-defaults
                                                        %*toolkit* ,kind)
                 (declare (ignorable palette))
                   ,@body)))))
       (define-widget ,name ,args (disabled-p ,@keys) ,doc))))

(define-control label (id text) ()
  "Display selectable text. Use :ID for repeated labels at one call site.
Width determines wrapping."
  (apply #'declare-widget :label style id text (append options defaults)))

(define-control button (id text) ()
  "Return true on activation. :id supplies an instance key. Return the ID third."
  (apply #'declare-widget :button style id text (append options defaults)))

(define-widget-options spacer () (placement) ()
  "Reserve empty layout space without painting or focus.
Use :width (grow) in a row or :height (grow) in a column to push siblings apart.
Fixed dimensions reserve a specific amount; :padding adds space on every side.
The default size is zero. For padding around children, use ROW or COLUMN."
  `(%lui.frame:emit
    (apply #'%lui.layout:make-element
           (container-options ',(gensym "SPACER") ,options))))

(define-control hr (id) ()
  "Draw a noninteractive horizontal rule, growing in width and one coordinate thick.
:height sets thickness; :width controls length. :foreground sets its color."
  (apply #'declare-widget :hr style id ""
         (append options (list :width (grow) :height (fixed 1)
                               :foreground (palette-color palette :border))
                 defaults)))

(define-control vr (id) ()
  "Draw a noninteractive vertical rule, growing in height and one coordinate thick.
:width sets thickness; :height controls length. :foreground sets its color."
  (apply #'declare-widget :vr style id ""
         (append options (list :width (fixed 1) :height (grow)
                               :foreground (palette-color palette :border))
                 defaults)))

(fn (selectable boolean)
    ((kind symbol) (style symbol) (id object-id) (text string) (options list)
     (defaults list))
  "Declare a selectable control and return whether it was activated."
  ;; Extract selection while removing its public option in one pass. Preserve
  ;; GETF's first-value rule, including an explicitly supplied NIL.
  (let ((selected nil)
        (selected-seen nil)
        (appearance nil))
    (do ((tail options (cddr tail))) ((null tail))
      (cond ((eq (car tail) :selected-p)
             (unless selected-seen
               (setf selected (cadr tail) selected-seen t)))
            (t
             (push (car tail) appearance)
             (push (cadr tail) appearance))))
    (apply #'declare-widget kind style id text :value selected
           (nreconc appearance defaults))))

(define-control tab (id text) (selected-p)
  "Declare a tab. Supply :selected-p and update the page on activation."
  (selectable :tab style id text options defaults))

(define-control list-item (id text) (selected-p)
  "Declare a selectable row and return activation. The caller owns selection."
  (selectable :list-item style id text options defaults))

(define-widget-options table (&body) (placement flow focus activation)
    (gap column-gap)
  "Lay out TABLE-ROWs with shared content-sized columns.
:GAP separates rows; :COLUMN-GAP separates columns. Accepts layout options."
  `(let ((%lui.frame:*parent*
          (%lui.frame:emit
           (apply #'%lui.layout:make-element
                  :direction :column :table-p t
                  (%lui.frame:container-options
                   ',(gensym "TABLE") ,options)))))
     ,@body
     (container-result *parent*)))

(define-widget-options table-row (&body) (placement flow focus activation)
    ()
  "Declare a table row.
Each direct child occupies one column by default. TABLE sets the gaps."
  `(let ((%lui.frame:*parent*
          (%lui.frame:emit
           (apply #'%lui.layout:make-element :direction :row
                  (%lui.frame:container-options
                   ',(gensym "TABLE-ROW") ,options)))))
     ,@body
     (container-result *parent*)))

(define-widget-options table-cell (&body) (placement flow focus activation)
    (gap column-span)
  "Group widgets in a table cell.
:PADDING insets the cell contents; :GAP separates its children.
:COLUMN-SPAN defaults to one. Height grows and content clips by default."
  `(let ((%lui.frame:*parent*
          (%lui.frame:emit
           (apply #'%lui.layout:make-element :direction :column
                  (append (%lui.frame:container-options
                           ',(gensym "TABLE-CELL") ,options)
                          (list :height (%lui.layout:grow) :clip-p t))))))
     ,@body
     (container-result *parent*)))

(define-control cell (id text) (selected-p)
  "Display a compact grid cell. Use :selected-p to mark the active cell."
  (selectable :cell style id text options
              (list* :background (%lui.widgets:palette-color palette
                                                             :cell-background
                                                             "#ffffff")
                     :foreground (%lui.widgets:palette-color palette
                                                             :cell-foreground
                                                             "#202430")
                     defaults)))

(define-control checkbox (id value text) ()
  "Return the boolean, change flag, and ID. :default-value initializes owned state.
Use :value for application-owned state; the default is NIL."
  (value-widget :checkbox style id value text (append options defaults)))

(define-control radio (id value choice text) ()
  "Return the selected choice, change flag, and ID. Share :value across a group.
Without :value, each control retains its own value, initially :default-value or NIL."
  (value-widget :radio style id value text
                (list* :choice choice (append options defaults))))

(define-control slider (id value) (minimum maximum step text)
  "Return the number, change flag, and ID. It accepts :minimum, :maximum and :step.
:default-value initializes owned state (default 0); :value is controlled."
  (value-widget :slider style id value (getf options :text "")
                (append (%without-option :text options) defaults)))

(define-control text-field (id value) (placeholder password-p)
  "Return text, a change flag, and the resolved ID. Text is retained by default.
:default-value initializes the string once (default empty); :value supplies
application-owned text each frame. :password-p masks presentation and copying.
Owned state is discarded when this widget is absent from a completed frame."
  (value-widget :text-field style id value (getf options :placeholder "")
                (append (%without-option :placeholder options) defaults)))

(define-control gauge (id fraction) ()
  "Display a read-only progress fraction, clamped to the range zero to one."
  (apply #'declare-widget :gauge style id "" :value (max 0 (min 1 fraction))
         (append options defaults)))

(define-control spinner (id) ()
  "Display an animated, noninteractive loading indicator while declared.
:width and :height set its size; :foreground sets its color. The default
is two spacing units square, or one terminal cell. :disabled-p pauses it.
No timer is retained after the spinner disappears from the frame."
  (let* ((disabled (getf options :disabled-p))
         (size (if (context-text-mode-p *context*)
                   1
                   ;; else
                   (resolve-units (units 2))))
         (phase (if disabled 0 (mod (floor (* 10 (frame-time))) 8))))
    ;; Schedule only the next animation step; absence stops future requests.
    (unless disabled (request-frame 0.1f0))
    (apply #'declare-widget :spinner style id "" :value phase
           (append options
                   (list :width (fixed size) :height (fixed size)
                         :foreground (palette-color palette :accent)
                         :accessible-name "Loading")
                   defaults))))

(define-control canvas (id commands) ()
  "Display circle commands (kind x y radius stroke fill) in local coordinates."
  (apply #'declare-widget :canvas style id "" :value commands
         (append options defaults)))

;; Toolkit-local convenience macros expand to the application controls above.
;; The registry and this extension symbol are owned by LUI.TOOLKIT.
(defmacro define-toolkit (name defaults panel-name &rest names)
  "Register NAME and define toolkit-local widget macros with the LUI signatures."
  (let ((functions '(label button tab checkbox radio slider text-field cell
                     list-item gauge canvas))
        (args '((text) (text) (text) (text) (choice text)
                () () (text) (text) (fraction) (commands))))
    `(progn
       (register-toolkit ,name :defaults (lambda () ,defaults))
       ,@(loop :for local :in names :for function :in functions :for a :in
               args
               :collect
               `(defmacro ,local (,@a &rest options)
                  (list 'with-toolkit (list ,name)
                    (list* ',function ,@a options))))
       (defmacro ,panel-name (options &body body)
         (list 'with-toolkit (list ,name) (list* 'panel options body))))))

(defstruct picker-state
  (year 2000 :type integer) (month 1 :type integer)
  (open-p nil :type boolean) months-p
  (draft "" :type string) value)

(defstruct (combobox-state (:include edit-state))
  open-p focused-p filter-p highlight)

(fn (combobox-matches (vector (cons integer string))) ((query string)
                                                       (choices sequence)
                                                       (limit (integer 1 *)))
  "Return source-index/label pairs matching QUERY, limited to LIMIT choices."
  ;; Keep the source index for IDs so filtering never retargets a pointer event.
  (let ((index 0)
        (count 0)
        matches)
    (block collect
      (map nil (lambda (choice)
                 (when (search query choice :test #'char-equal)
                   (push (cons index choice) matches)
                   (when (= (incf count) limit) (return-from collect)))
                 (incf index))
           choices))
    (make-array count :element-type '(cons integer string) :initial-contents
                (nreverse matches))))

(fn (anchored-popup %lui.layout:element)
    ((id object-id) (anchor %lui.layout:element) (options list)
     &key ((side (member :below :right)) :below)
     ((content-width-p boolean) nil))
  "Declare a floating popup whose geometry is constrained to ANCHOR."
  (let ((*parent* (%lui.layout:make-element)))
    (let ((pane
           (declare-panel
            %*toolkit*
            (append options
                    (list :id id :position :absolute :opacity 1 :scroll-p t
                         :scrollbar-p nil :clip-p t :interactive-p t
                         :keyboard-focus-p nil :padding (units 1))
                    (toolkit-defaults)))))
      (setf (%lui.layout:element-popup-anchor pane) anchor
            (%lui.layout:element-popup-side pane) side
            (%lui.layout:element-popup-content-width-p pane) content-width-p)
      (push pane (%lui.frame:context-popups *context*))
      pane)))

(fn (dialog-buttons (member nil :confirm :cancel))
    ((id object-id) (confirm-label string) (cancel-label (or null string)))
  "Declare dialog actions and return the selected keyword, if any."
  (let ((answer nil))
    (row (:gap (units 1) :width (grow) :align :end)
      (when (and cancel-label
                 (%button (list id :cancel) cancel-label nil))
        (setf answer :cancel))
      (when (%button (list id :confirm) confirm-label nil)
        (setf answer :confirm)))
    answer))

(fn (dialog-body (member nil :confirm :cancel))
    ((id object-id) (text string) (title string)
     (confirm-label string) (cancel-label (or null string)))
  "Build a bounded dialog with scrolling text and visible actions."
  (let ((answer nil))
    (panel (:id (list id :pane)
                :width (fixed (min (context-width *context*)
                                   (resolve-units (units 50))))
                :height (fit 0 (context-viewport-height *context*))
                :padding (units 1) :gap (units 1) :opacity 1
                :clip-p t :accessible-name title)
      (unless (zerop (length title))
        (%label (list id :title) title (list :font-weight :bold)))
      (column (:id (list id :text) :width (grow) :height (grow)
                   :clip-p t :scroll-p t)
        (%label (list id :message) text (list :width (grow))))
      (setf answer (dialog-buttons id confirm-label cancel-label)))
    answer))

(fn (draw-dialog (member nil :confirm :cancel))
    ((id object-id) (text string) (title string)
     (confirm-label string) (cancel-label (or null string)))
  "Declare one modal surface and return NIL, :CONFIRM, or :CANCEL."
  (when (context-modal-declared-p *context*)
    (error 'configuration-error :operation :confirm :setting :modal
           :value id :format-control "Declare only one confirmation per frame."))
  (let* ((previous (context-modal *context*))
         (opening (not (and previous
                            (equal id (%lui.layout:element-id previous)))))
         (*parent* (%lui.layout:make-element))
         (surface
           (emit (%lui.layout:make-element
                  :id id :position :fixed
                  :width (fixed (context-width *context*))
                  :height (fixed (context-viewport-height *context*))
                  :align :center :cross-align :center :clip-p t
                  :interactive-p t :keyboard-focus-p nil
                  :pointer-focus-p nil)))
         (answer nil))
    (let ((*parent* surface))
      (setf answer (dialog-body id text title confirm-label cancel-label)))
    (when (some (lambda (event) (eq (event-key event) lui.key:escape))
                (events-for id))
      (setf answer :cancel))

    ;; Capture focus once; redeclarations preserve the user's chosen button.
    (unless previous
      (setf (context-modal-focus *context*) (context-focus *context*)))
    (setf (context-modal *context*) surface
          (context-modal-declared-p *context*) (null answer))
    (when opening
      (setf (context-active *context*) nil
            (context-hover *context*) nil
            (context-selection *context*) nil
            (context-floating-path *context*) #()))
    (unless (modal-member-p *context* (context-focus *context*))
      (setf (context-focus *context*)
            (list id (if cancel-label :cancel :confirm))
            (context-focus-visible-p *context*) t))
    (when answer (request-frame))
    answer))

(defmacro confirm (text &key (title "Confirm") (confirm-label "OK")
                            (cancel-label "Cancel") (id nil id-p))
  "Declare a modal confirmation each frame while awaiting an answer.
Return :CONFIRM, :CANCEL (including Escape), or NIL while waiting. Stop declaring
it after an answer. IDs use call-site identity, WITH-KEY scopes, and optional ID.
Only one confirmation may be declared per frame; retained messages wait behind
it. Outside clicks do nothing, Tab stays inside, and Cancel initially has focus.
TITLE, CONFIRM-LABEL, and CANCEL-LABEL are strings. This is an in-window overlay."
  `(draw-dialog (call-site-id ',(gensym "CONFIRM")
                             ,(when id-p `(list :id ,id)))
                ,text ,title ,confirm-label ,cancel-label))

(fn (draw-messages (values)) ()
  "Draw the oldest retained message when no confirmation owns the surface."
  (unless (or (context-modal-declared-p *context*)
              (let ((modal (context-modal *context*)))
                (and modal
                     (eq modal (gethash (%lui.layout:element-id modal)
                                        (context-ids *context*))))))
    (let ((pending (first (context-messages *context*))))
      (when (and pending (funcall pending))
        (pop (context-messages *context*))
        (request-frame))))
  (values))

(fn (popup (values)) ((text string) &key ((title string) "Message"))
  "Queue TEXT once for an automatically redrawn modal message with an OK button.
Call on the UI thread inside the target window's draw function or UI callback
with an active frame context. Messages persist until OK or Escape and are shown
in arrival order, after any application confirmation. Outside clicks do nothing.
Capture the message, title, toolkit, and palette at the call; do not call every
frame for the same error. Closing the window discards its pending messages."
  (let ((id (gensym "MESSAGE"))
        (message (copy-seq text))
        (caption (copy-seq title))
        (toolkit (current-toolkit))
        (palette (apply #'make-palette
                        (nth-value 1 (toolkit-defaults)))))
    (setf (context-message-draw *context*) #'draw-messages
          (context-messages *context*)
          (nconc (context-messages *context*)
                 (list (lambda ()
                         (with-toolkit (toolkit)
                           (with-palette (palette)
                             (draw-dialog id message caption "OK" nil)))))))
    (request-frame))
  (values))

(defstruct floating-state
  (id nil :type object-id)
  (parent nil :type object-id)
  (group nil :type object-id)
  (menu-p nil :type boolean)
  (hover-p nil :type boolean)
  (hover-open-p nil :type boolean)
  (opened-by-hover-p nil :type boolean)
  (last-open-p nil :type boolean)
  (focus-edge nil :type (member nil :first :last))
  (items #() :type (vector object-id)))

(defvar *floating-parent* nil)
(defvar *menu-bar* nil)

(fn (floating-state-for (or null floating-state))
    ((context context) (id object-id))
  "Find retained expander state without confusing it with another control kind."
  (let ((state (gethash id (context-state context))))
    (when (floating-state-p state) state)))

(fn (floating-popup-id list) ((id object-id))
  "Derive a stable popup identity from its trigger's resolved identity."
  (list id :floating-popup))

(fn (floating-depth (or null integer))
    ((context context) (state floating-state))
  "Return STATE's level when its parent is open, or NIL for a closed parent."
  (if (floating-state-parent state)
      (let ((parent (position (floating-state-parent state)
                               (context-floating-path context) :test #'equal)))
        (when parent (1+ parent)))

      ;; else
      0))

(fn (floating-open-p boolean) ((context context) (id object-id))
  "Whether ID owns one level of the active floating-content chain."
  (not (null (position id (context-floating-path context) :test #'equal))))

(fn (forget-floating-pane (values))
    ((context context) (pane %lui.layout:element))
  "Remove identities from a closed pane, including children declared after closing."
  (%lui.layout:walk-elements pane
    (lambda (node)
      (when (%lui.layout:element-id node)
        (remhash (%lui.layout:element-id node) (context-ids context)))))
  (values))

(fn (discard-floating-popups (values)) ((context context))
  "Remove closed panes declared this frame, including their detached descendants."
  (let ((path (context-floating-path context))
        (kept nil))
    ;; Parents are declared first; their removal also invalidates child anchors.
    (dolist (pane (reverse (context-popups context)))
      (let* ((id (%lui.layout:element-id pane))
             (anchor (%lui.layout:element-popup-anchor pane))
             (closed (and (consp id) (consp (cdr id))
                           (eq (second id) :floating-popup)
                           (not (find (first id) path :test #'equal)))))
        (if (or closed
                (and anchor
                     (not (gethash (%lui.layout:element-id anchor)
                                   (context-ids context)))))
            (forget-floating-pane context pane)

            ;; else
            (push pane kept))))
    (setf (context-popups context) kept))
  (values))

(fn (open-floating (values))
    ((context context) (state floating-state)
     &optional ((edge (member nil :first :last)) nil)
     ((hover boolean) nil))
  "Open STATE, replacing its siblings and descendants, and request initial focus."
  (let ((depth (floating-depth context state))
        (old (context-floating-path context)))
    (unless depth (return-from open-floating (values)))
    (unless (floating-open-p context (floating-state-id state))
      (setf (floating-state-opened-by-hover-p state) hover))
    (let ((path (make-array (1+ depth) :element-type 'object-id
                                      :initial-element nil)))
      (replace path old :end1 depth :end2 depth)
      (setf (aref path depth) (floating-state-id state)
            (context-floating-path context) path
            (floating-state-focus-edge state) edge
            (context-focus context) (floating-state-id state)
            (context-focus-visible-p context) (not (null edge))))
    (discard-floating-popups context)
    (request-frame))
  (values))

(fn (close-floating (values))
    ((context context) (depth integer) &optional ((restore boolean) t))
  "Close DEPTH and its descendants, optionally returning focus to its trigger."
  (let ((path (context-floating-path context)))
    (when (< depth (length path))
      (when restore (setf (context-focus context) (aref path depth)))
      (loop :for i :from depth :below (length path)
            :for state = (floating-state-for context (aref path i))
            :when state :do (setf (floating-state-focus-edge state) nil))
      (setf (context-floating-path context) (subseq path 0 depth))
      (discard-floating-popups context)
      (request-frame)))
  (values))

(fn (floating-owner (or null floating-state))
    ((context context) (id object-id))
  "Find the deepest open pane that owns ID or uses it as its trigger."
  (let ((path (context-floating-path context)))
    (loop :for i :downfrom (1- (length path)) :to 0
          :for state = (floating-state-for context (aref path i))
          :when (and state
                     (or (equal id (floating-state-id state))
                         (find id (floating-state-items state) :test #'equal)))
            :return state)))

(fn (menu-group-ids (vector object-id))
    ((context context) (group object-id))
  "Collect enabled root menus in their declared order within GROUP."
  (let ((ids (make-array 0 :element-type 'object-id
                         :adjustable t :fill-pointer 0)))
    (when (context-root context)
      (%lui.layout:walk-elements (context-root context)
        (lambda (node)
          (let ((state (floating-state-for context
                                          (%lui.layout:element-id node))))
            (when (and state (floating-state-menu-p state)
                       (null (floating-state-parent state))
                       (equal group (floating-state-group state))
                       (%lui.layout:element-interactive-p node))
              (vector-push-extend (floating-state-id state) ids))))))
    ids))

(fn (cycle-root-menu boolean) ((context context) (step integer))
  "Move to an adjacent root menu in the same bar, wrapping past either end."
  (let* ((path (context-floating-path context))
         (root (when (plusp (length path))
                 (floating-state-for context (aref path 0))))
         (ids (when root (menu-group-ids context
                                         (floating-state-group root)))))
    (when (and ids (> (length ids) 1))
      (let* ((index (or (position (aref path 0) ids :test #'equal) 0))
             (next (aref ids (mod (+ index step) (length ids)))))
        (open-floating context (floating-state-for context next) :first))
      t)))

(fn (navigate-menu-items (values))
    ((context context) (state floating-state) (key symbol))
  "Move focus through a menu's enabled items and remember an edge for first open."
  (let* ((items (floating-state-items state))
         (count (length items))
         (index (position (context-focus context) items :test #'equal)))
    (if (zerop count)
        (setf (floating-state-focus-edge state)
              (if (member key '(lui.key:up lui.key:end)) :last :first))

        ;; else
        (let ((next (case key
                      (lui.key:home 0)
                      (lui.key:end (1- count))
                      (lui.key:up (if index (mod (1- index) count) (1-
                                                                    count)))
                      (otherwise (if index (mod (1+ index) count) 0)))))
          (setf (context-focus context) (aref items next))))
    (setf (context-focus-visible-p context) t)
    (request-frame))
  (values))

(fn (tab-from-floating (values)) ((context context) (backward boolean))
  "Leave the menu chain without tabbing into its soon-to-be-removed popup nodes."
  (let* ((path (context-floating-path context))
         (root (aref path 0)))
    (setf (context-focus context) root
          (context-focus-visible-p context) t)
    (focus-next context backward
      (lambda (node)
        (let ((owner (floating-owner context (%lui.layout:element-id node))))
          (and owner (not (equal root (%lui.layout:element-id node)))))))
    (close-floating context 0 nil))
  (values))

(fn (menu-key-input boolean)
    ((context context) (key symbol) (trigger (or null floating-state)))
  "Navigate an open menu without taking editing keys from embedded fields."
  (let ((owner (floating-owner context (context-focus context)))
        (depth (length (context-floating-path context))))
    (unless (and owner (floating-state-menu-p owner)
                 (not (text-field-focused-p context)))
      (return-from menu-key-input nil))

    (case key
      ((lui.key:up lui.key:down lui.key:home lui.key:end)
       (navigate-menu-items context owner key) t)
      (lui.key:left
       (if (> depth 1)
           (close-floating context (1- depth))
           ;; else
           (cycle-root-menu context -1))
       t)
      (lui.key:right
       (if (and trigger (floating-state-parent trigger))
           (open-floating context trigger :first)
           ;; else
           (cycle-root-menu context 1))
       t)
      (otherwise nil))))

(fn (floating-key-input boolean) ((context context) (key symbol))
  "Handle shared expander opening/dismissal, then delegate menu navigation."
  (let ((trigger (floating-state-for context (context-focus context)))
        (depth (length (context-floating-path context))))
    (cond
      ;; All expanders can open from their focused trigger.
      ((and trigger (member key '(lui.key:up lui.key:down lui.key:right))
            (not (floating-open-p context (floating-state-id trigger))))
       (open-floating context trigger (if (eq key lui.key:up) :last :first))
       t)

      ((zerop depth) nil)

      ;; Escape closes one level even when the pane contains ordinary controls.
      ((eq key lui.key:escape)
       (close-floating context (1- depth))
       t)

      (t (menu-key-input context key trigger)))))

(fn (floating-hit-p boolean)
    ((context context) (x real) (y real)
     &optional ((depth integer) 0))
  "Whether a pointer is inside any open pane or its owning trigger."
  (loop :for i :from depth :below (length (context-floating-path context))
        :for id = (aref (context-floating-path context) i)
        :thereis
        (some (lambda (key)
                (let ((node (gethash key (context-ids context))))
                  (and node
                       (%lui.frame:contains-p
                        (%lui.layout:element-clip node) x y))))
              (list id (floating-popup-id id)))))

(fn (dismiss-hovered-floating (values))
    ((context context) (event event))
  "Close hover-opened panes once the pointer leaves their trigger and descendants."
  (loop :for i :below (length (context-floating-path context))
        :for state = (floating-state-for
                      context (aref (context-floating-path context) i))
        :when (and state (floating-state-opened-by-hover-p state)
                   (not (floating-hit-p context
                                        (event-x event) (event-y event) i)))
          :do (close-floating context i nil) (return))
  (values))

(fn (floating-pointer-move (values)) ((context context) (event event))
  "Switch open menus on hover and keep focus aligned with the pointed item."
  (dismiss-hovered-floating context event)
  (let* ((id (%lui.frame:hit context (event-x event) (event-y event)))
         (trigger (floating-state-for context id))
         (owner (floating-owner context id)))
    (cond
      ((and trigger (floating-state-hover-open-p trigger)
            (not (equal id (context-hover context))))
       (open-floating context trigger nil t))

      ((and owner (floating-state-menu-p owner)
            (not (equal id (floating-state-id owner))))
       (let ((depth (position (floating-state-id owner)
                              (context-floating-path context) :test #'equal)))
         (close-floating context (1+ depth) nil))
       (setf (context-focus context) id
             (context-focus-visible-p context) nil))))
  (values))

(fn (floating-input (or null event))
    ((context context) (event event) (resized boolean))
  "Route floating-menu input before ordinary activation and focus processing."
  (let ((*context* context))
    (when (and (eq (event-kind event) :key)
               (floating-key-input context (event-key event)))
      (return-from floating-input nil))
    (when (plusp (length (context-floating-path context)))
      (case (event-kind event)
        (:tab
         (tab-from-floating context (eq (event-key event) lui.key:backward))
         (return-from floating-input nil))
        (:cancel (close-floating context 0))
        (:press
         (when (and (not resized)
                    (not (floating-hit-p context
                                          (event-x event) (event-y event))))
           (close-floating context 0)))
        (:move
         (unless resized (floating-pointer-move context event)))
        (otherwise nil))))
  event)

(fn (floating-control-options list) ((options list))
  "Remove expander-only options before declaring its ordinary trigger control."
  (loop :for (key value) :on (widget-options options) :by #'cddr
        :unless (member key '(:open-on-hover-p :popup-width :popup-height))
          :append (list key value)))

(fn (floating-items (vector object-id)) ((pane %lui.layout:element))
  "Collect enabled focusable content without entering detached child popups."
  (let ((items (make-array 0 :element-type 'object-id
                           :adjustable t :fill-pointer 0)))
    (%lui.layout:walk-elements pane
      (lambda (node)
        (when (and (%lui.layout:element-interactive-p node)
                   (%lui.layout:element-keyboard-focus-p node))
          (vector-push-extend (%lui.layout:element-id node) items))))
    items))

(fn (finish-floating-pane (values))
    ((state floating-state) (pane %lui.layout:element))
  "Retain keyboard targets and reveal the focused item after declaring a pane."
  (let ((items (floating-items pane))
        (edge (floating-state-focus-edge state)))
    (setf (floating-state-items state) items)
    (when (and edge (plusp (length items)))
      (setf (context-focus *context*)
            (aref items (if (eq edge :last) (1- (length items)) 0))
            (context-focus-visible-p *context*) t
            (floating-state-focus-edge state) nil))

    ;; Keyboard navigation must expose rows beyond a constrained popup height.
    (when (find (context-focus *context*) items :test #'equal)
      (setf (%lui.layout:element-popup-reveal pane)
            (gethash (context-focus *context*) (context-ids *context*)))))
  (values))

(fn (draw-floating-pane (values))
    ((state floating-state) (options list) (draw function))
  "Declare floating content beside its trigger and scope its child identities."
  (let* ((id (floating-state-id state))
         (anchor (gethash id (context-ids *context*)))
         (pane (anchored-popup
                (floating-popup-id id) anchor
                (list :width (getf options :popup-width (fit))
                     :height (getf options :popup-height (fit))
                     :padding (if (context-text-mode-p *context*)
                                  1
                                  ;; else
                                  (resolve-units (units 0.5f0)))
                     :gap 0)
                :side (if (floating-state-parent state) :right :below)
                :content-width-p t)))
    ;; The popup is detached from normal flow, but owns its body's key scope.
    (let ((*parent* pane)
          (*floating-parent* id))
      (call-with-key id draw))

    (cond
      ((floating-open-p *context* id)
       (finish-floating-pane state pane))

      ;; User code may keep declaring children after an action closes the pane.
      (t
       (forget-floating-pane *context* pane)
       (discard-floating-popups *context*))))
  (values))

(fn (floating-trigger t)
    ((state floating-state) (text string) (options list))
  "Draw a regular toolkit control with popup state and an accessible caption."
  (let* ((nested (not (null (floating-state-parent state))))
         (menu (floating-state-menu-p state))
         (id (floating-state-id state))
         (open (floating-open-p *context* id))
         (caption (cond (nested (concatenate 'string text " ▸"))
                        (menu text)
                        (t (concatenate 'string text " ▾"))))
         (appearance
           (append (floating-control-options options)
                   (list :accessible-name text
                         :popup-kind (if menu :menu :dialog)
                         :expanded-p open)
                   (when nested (list :width (grow))))))
    (if (or menu nested)
        (%list-item id caption (append (list :selected-p open) appearance))
        ;; else
        (%button id caption appearance))))

(fn (invoke-floating (values boolean boolean object-id))
    ((site symbol) (text string) (options list) (draw function) (menu boolean))
  "Resolve an expander's state, declare its trigger, and conditionally draw its body."
  (when (and *floating-parent*
             (not (floating-open-p *context* *floating-parent*)))
    (return-from invoke-floating (values nil nil nil)))
  (let* ((id (call-site-id site options))
         (state (or (floating-state-for *context* id)
                    (make-floating-state :id id)))
         (hover (hovered-p id))
         (before (floating-state-last-open-p state))
         (disabled (getf options :disabled-p)))
    ;; Refresh the trigger's parent and opening policy for this frame.
    (setf (gethash id (context-state *context*)) state
          (context-popup-input *context*) #'floating-input
          (floating-state-parent state) *floating-parent*
          (floating-state-group state) *menu-bar*
          (floating-state-menu-p state) menu
          (floating-state-hover-open-p state)
          (not (null (getf options :open-on-hover-p menu))))

    ;; Activation toggles; a hover edge opens without repeatedly reopening.
    (let ((activated (floating-trigger state text options)))
      (cond
        (disabled
         (when (floating-open-p *context* id)
           (close-floating *context* (floating-depth *context* state))))

        (activated
         (if (floating-open-p *context* id)
             (close-floating *context* (floating-depth *context* state))
             ;; else
             (open-floating *context* state)))

        ((and hover (not (floating-state-hover-p state))
              (floating-state-hover-open-p state))
         (open-floating *context* state nil t))))
    (setf (floating-state-hover-p state) hover)

    ;; Declare children only while their trigger belongs to the open path.
    (if (floating-open-p *context* id)
        (draw-floating-pane state options draw)
        ;; else
        (setf (floating-state-items state) #()))

    ;; Body actions may close the pane; publish its final state to the renderer.
    (let* ((open (floating-open-p *context* id))
           (node (gethash id (context-ids *context*)))
           (widget (when node (element-content node))))
      (when (widget-p widget)
        (setf (widget-expanded-p widget) open)
        (when (eq (widget-kind widget) :list-item)
          (setf (widget-value widget) open)))
      (setf (floating-state-last-open-p state) open)
      (values open (not (eql open before)) id))))

(define-widget-options floating-expander (text &body) (placement appearance)
    (disabled-p open-on-hover-p popup-width popup-height)
  "Show BODY in a floating pane when its caption is activated.
Nested expanders open beside their parent. :open-on-hover-p also enables
hover opening and closing when the pointer leaves the trigger and popup chain.
:popup-width and :popup-height constrain the pane. BODY IDs are scoped to this
expander. Return open state, changed flag, and resolved ID."
  `(invoke-floating ',(gensym "EXPANDER") ,text ,options
                    (lambda () ,@body) nil))

(define-widget-options menu (text &body) (placement appearance)
    (disabled-p open-on-hover-p popup-width popup-height)
  "Declare a click/hover dropdown menu; nested menus open beside their parent.
Use MENU-ITEM for actions and MENU for submenus. Arrow keys navigate, Escape
closes one level, and Tab or an outside click dismisses the chain. Options
and return values match FLOATING-EXPANDER; hover opening defaults to true."
  `(invoke-floating ',(gensym "MENU") ,text ,options (lambda () ,@body) t))

(fn (invoke-menu-bar (values))
    ((site symbol) (options list) (draw function))
  "Group root menus with toolkit-defined framing and keyboard cycling."
  (let* ((id (call-site-id site options))
         (*menu-bar* id)
         (defaults (toolkit-defaults %*toolkit* :menu-bar))
         (border (getf defaults :border-p))
         (appearance (lui.toolkit:%without-option :border-p defaults))
         (layout (append (list :id id :direction :row)
                         (widget-options options)
                         (when border appearance)
                         (list :width (grow) :padding 0 :gap 0)))
         (*parent* (if border
                       (declare-panel %*toolkit* layout)
                       ;; else
                       (%lui.frame:emit
                        (apply #'%lui.layout:make-element
                         (%lui.layout:resolve-layout-options layout))))))
    (call-with-key id draw))
  (values))

(define-widget-options menu-bar (&body) (placement flow focus appearance)
    (gap)
  "Lay out root menus in a row with toolkit-defined framing (beveled in Motif).
Accept ROW options. Direct MENU-ITEM children act as compact action buttons.
Left/Right cycle enabled menus in this bar."
  `(invoke-menu-bar ',(gensym "MENU-BAR") ,options (lambda () ,@body)))

(fn (%menu-item boolean) ((id object-id) (text string)
                          &optional ((options list) nil))
  "Declare a menu action in a bar or floating pane and dismiss on activation."
  (unless (or *floating-parent* *menu-bar*)
    (error 'configuration-error :operation :menu-item :setting :parent
           :value nil :format-control
           "MENU-ITEM requires a MENU-BAR, MENU, or FLOATING-EXPANDER."))
  (let* ((selected (and *floating-parent*
                        (equal id (context-focus *context*))))
         (activated
           (%list-item id text
                       (append options
                               (list :width (if *floating-parent* (grow) (fit))
                                    :selected-p selected)))))
    (when activated (close-floating *context* 0))
    (not (null activated))))

(define-widget menu-item (id text) (disabled-p selected-p)
  "Return true when this menu action is selected, then dismiss the menu chain.
Use directly in MENU-BAR for a compact action with menu-style hover feedback,
or inside MENU/FLOATING-EXPANDER for a popup action. Bar actions use intrinsic
width and support button-style pointer and keyboard activation.
:disabled-p disables it. The third return value is its resolved ID.")

(fn (combobox-popup (values))
    ((id object-id) (matches (vector (cons integer string)))
     (index (or null integer)) (anchor %lui.layout:element)
     (reveal (or null event)))
  "Declare the filtered combobox choices with stable source-index IDs."
  (let* ((pane (anchored-popup (list id :popup) anchor nil))
         (*parent* pane))
    (loop :for match :across matches :for i :from 0
          :for row-id := (list id
                               :choice
                               (car
                                match))
          :do (%list-item row-id (cdr match)
                         (list :width (%lui.layout:grow) :selected-p
                           (eql i
                             index)))
          (let ((row (gethash row-id (%lui.frame:context-ids *context*))))
            (setf (%lui.layout:element-keyboard-focus-p row) nil)
            (when (and reveal (eql index i))
              (setf (%lui.layout:element-popup-reveal pane) row)))))
  (values))

(fn (completion-navigation-p boolean) ((event event))
  "Recognize up/down keyboard events that navigate completion choices."
  (and (eq :key (event-kind event))
       (not (null (member (event-key event) '(lui.key:up lui.key:down))))))

(fn (completion-next-index (or null integer))
    ((matches sequence) (index (or null integer)) (last integer)
     (event event))
  "Advance the highlighted completion index, retaining NIL for an empty result set."
  (when (plusp (length matches))
    (if (eq lui.key:down (event-key event))
        (min last (1+ (or index -1)))
        ;; else
        (max 0 (1- (or index (1+ last)))))))

(fn (combobox-completion (or null string))
    ((id object-id) (state combobox-state) (text string) (choices sequence)
     (limit (integer 1 *)) (events (vector event))
     (anchor %lui.layout:element))
  "Apply autocomplete navigation or selection to the combobox editor state."
  (let ((navigate (find-if #'completion-navigation-p events)))
    (unless (or navigate (combobox-state-open-p state))
      (return-from combobox-completion nil))

    (let* ((filter (if (combobox-state-filter-p state) text ""))
           (matches (combobox-matches filter choices limit))
           (last (1- (length matches)))
           (old (and (combobox-state-open-p state)
                     (combobox-state-highlight state)))
           (index (and (plusp (length matches)) old (min old last))))
      ;; Apply keyboard input in order, committing only a highlighted match.
      (loop :for event :across events :do
        (case (event-kind event)
          (:key
           (case (event-key event)
             ((lui.key:up lui.key:down)
              (setf (combobox-state-open-p state) t
                    index (completion-next-index matches index last event)))
             (lui.key:escape (setf (combobox-state-open-p state) nil))
             (otherwise nil)))

          (:activate
           (when (combobox-state-open-p state)
             (setf (combobox-state-open-p state) nil)
             (return-from combobox-completion
               (and index (cdr (aref matches index))))))
          (otherwise nil)))
      (setf (combobox-state-highlight state) index)

      ;; A dismissed or empty popup has no pointer selection to resolve.
      (unless (and (plusp (length matches)) (combobox-state-open-p state))
        (return-from combobox-completion nil))
      (let ((clicked (find-if
                      (lambda (match)
                        (activated-p (list id :choice (car match))))
                      matches)))
        (when clicked
          (setf (combobox-state-open-p state) nil)
          (return-from combobox-completion (cdr clicked))))

      (combobox-popup id matches index anchor navigate)))
  nil)

(fn (%searchable-combobox (values t boolean))
    ((id object-id) (value (or null string)) (choices sequence) &optional
     ((options list) nil))
  "Edit a string, returning the text and a change flag just like TEXT-FIELD.
Suggestions open on focus or typing. Up/Down highlight a suggestion and
Enter accepts it. Escape dismisses the suggestions and keeps the typed text."
  (let* ((text (or value ""))
         (state (or (gethash id (context-state *context*))
                    (setf (gethash id (context-state *context*))
                          (make-combobox-state :cursor (length text) :anchor
                                               (length text)))))
         (limit (getf options :max-results 20))
         (focused (and (not (getf options :disabled-p)) (equal id
                                                               (context-focus
                                                                *context*))))
         (events (events-for id))
         (press (%lui.frame:context-pointer-press *context*))
         (popup-box (previous-box (list id :popup)))
         (edited (%text-field id text (%without-option :max-results options)))
         (anchor (gethash id (%lui.frame:context-ids *context*)))
         (result (if (string= edited text) value edited)))
    (check-type limit (integer 1 *))

    ;; Focus and typing decide whether suggestions open and filter.
    (cond ((not focused) (setf (combobox-state-open-p state) nil))
          ((or (not (combobox-state-focused-p state)) (find :press events
                                                            :key
                                                            #'event-kind))
           (setf (combobox-state-open-p state) t (combobox-state-filter-p
                                                  state) nil
                                                  (combobox-state-highlight
                                                   state) nil))
          ((and press (not (and popup-box (%lui.frame:contains-p popup-box
                                                                 (event-x
                                                                  press)
                                                                 (event-y
                                                                  press)))))
           (setf (combobox-state-open-p state) nil)))

    ;; Remember focus for the next frame before resolving popup input.
    (setf (combobox-state-focused-p state) focused)
    (when (and focused (not (string= edited text)))
      (setf (combobox-state-open-p state) t (combobox-state-filter-p state) t
            (combobox-state-highlight state) nil))
    (when focused
      (let ((choice (combobox-completion id state edited choices limit events
                                         anchor)))
        (when choice
          (setf result choice (edit-state-anchor state) (length choice)
                (edit-state-cursor state) (length choice))
          (let ((widget (%lui.layout:element-content anchor)))
            (when (and (widget-p widget) (eq :text-field (widget-kind
                                                          widget)))
              (setf (widget-value widget) choice)))
          (request-frame))))
    (values result (not (equal result value)))))

(fn (month-days (integer 28 31)) ((year integer) (month (integer 1 12)))
  "Return the number of days in MONTH of YEAR, including leap-year February."
  (if (= month 2)
      (if (and (zerop (mod year 4))
               (or (not (zerop (mod year 100))) (zerop (mod year 400))))
          29
          ;; else
          28)

      ;; else
      (if (member month '(4 6 9 11)) 30 31)))

(deftype date-parts () '(vector integer 3))

(fn (make-date-parts date-parts) ((year integer) (month integer) (day
                                                                  integer))
  "Validate numeric year/month/day parts and construct the date representation."
  (make-array 3 :element-type 'integer :initial-contents (list year month
                                                               day)))

(fn (parse-picker-date (or null date-parts)) ((text (or null string)))
  "Parse YYYY-MM-DD or MM/DD/YYYY into a year/month/day vector, checking leap years."
  (when (and (stringp text) (= 10 (length text)))
    (flet ((number-at (start end)
             (when (every #'digit-char-p (subseq text start end))
               (parse-integer text :start start :end end))))
      (multiple-value-bind (year month day)
          (cond ((and (char= (char text 4) #\-) (char= (char text 7) #\-))
                 (values (number-at 0 4) (number-at 5 7) (number-at 8 10)))
                ((and (char= (char text 2) #\/) (char= (char text 5) #\/))
                 (values (number-at 6 10) (number-at 0 2) (number-at 3 5))))
        (when (and year month day (<= 1 year 9999) (<= 1 month 12)
                   (<= 1 day (month-days year month)))
          (make-date-parts year month day))))))

(fn (picker-display string) ((date (or null date-parts)))
  "Format a date value for display in the date picker text field."
  (if date (format nil "~2,'0D/~2,'0D/~4,'0D" (aref date 1) (aref date 2)
                   (aref date 0))

      ;; else
      ""))

(fn (picker-value (or null string)) ((date (or null date-parts)))
  "Parse the picker's editable date text into its canonical date value."
  (when date (format nil "~4,'0D-~2,'0D-~2,'0D" (aref date 0) (aref date 1)
                     (aref date 2))))

(fn (calendar-start (integer 0 6)) ((year integer) (month (integer 1 12)))
  "Find the first displayed day in the six-week calendar grid."
  ;; Gregorian weekday, Sunday = 0, independent of time zones and OS clocks.
  (let* ((previous (1- year))
         (days (+ (* 365 previous) (floor previous 4)
                  (- (floor previous 100)) (floor previous 400))))
    (loop :for m :from 1 :below month :do (incf days (month-days year m)))
    (mod (1+ days) 7)))

(defparameter *month-names*
  #("January" "February" "March" "April" "May" "June" "July" "August"
    "September" "October" "November" "December"))

(fn (local-today date-parts) ()
  "Return today's date in the local timezone as a canonical date string."
  (multiple-value-bind (s m h day month year)
      (decode-universal-time (get-universal-time))
    (declare (ignore s m h))
    (make-date-parts year month day)))

(fn (shift-month (values integer (integer 1 12)))
    ((year integer) (month (integer 1 12)) (delta integer))
  "Shift the displayed calendar month, carrying across year boundaries."
  (multiple-value-bind (year-offset index) (floor (+ month -1 delta) 12)
    (values (+ year year-offset) (1+ index))))

(fn (calendar-item boolean)
    ((id object-id) (text string) &rest (options list))
  "Declare one selectable calendar entry with its date-specific options."
  (%list-item id text (append options (list :font-size 14))))

(fn (calendar-day (values integer integer integer))
    ((year integer) (month (integer 1 12)) (day integer))
  "Resolve a day in MONTH or either adjacent month, including year bounds."
  (let* ((count (month-days year month))
         (offset (cond ((< day 1) -1) ((> day count) 1) (t 0))))
    (multiple-value-bind (y m) (shift-month year month offset)
      (values y m (case offset
                    (-1 (+ day (month-days y m)))
                    (1 (- day count)) (otherwise day))))))

(fn (calendar-arrow-focus (values)) ((id object-id) (state picker-state))
  "Move calendar keyboard focus according to arrow and paging keys."
  (let ((focus (context-focus *context*)))
    (when (and (consp focus) (equal (first focus) id)
               (eq (second focus) :day))
      (let ((day (third focus)))
        (loop :for event :across (events-for focus) :do
              (let ((step (and (eq (event-kind event) :key)
                               (case (event-key event)
                                 (lui.key:left -1)
                                 (lui.key:right 1)
                                 (lui.key:up -7)
                                 (lui.key:down 7)
                                 (otherwise nil)))))
                (when step
                  (multiple-value-bind (y m next)
                      (calendar-day (picker-state-year state)
                                    (picker-state-month state) (+ day step))
                    (when (<= 1 y 9999)
                      (setf day next
                            (picker-state-year state) y
                            (picker-state-month state) m
                            (context-focus *context*) (list id :day
                                                            day))))))))))
  (values))

(fn (calendar-header (values))
    ((id object-id) (state picker-state) (year integer) (month integer)
     (months boolean))
  "Declare month/year navigation and update the picker state when activated."
  (row (:width (%lui.layout:grow))
    (when (calendar-item (list id :month-menu)
                         (format nil "~A ~4,'0D ▼"
                                 (aref *month-names* (1-
                                                      month)) year)
                         :width (%lui.layout:grow) :font-weight :bold)
      (setf (picker-state-months-p state) (not months)))
    (dolist (step '(-1 1))
      (multiple-value-bind (y m) (shift-month year month (* step (if months
                                                                     12
                                                                     ;; else
                                                                     1)))
        (when (calendar-item (list id (if (minusp step) :previous-month
                                          ;; else
                                          :next-month))
                             (if (minusp step) "↑" "↓") :font-size 19
                             :center-text-p t
                             :width (%lui.layout:fixed (if
                                                       (context-text-mode-p
                                                        *context*) 3
                                                           ;; else
                                                           28))
                             :disabled-p (not (<= 1 y 9999))
                             :accessible-name (if months (if (minusp step) "Previous year" "Next year")
                                                  ;; else
                                                  (if (minusp step) "Previous month" "Next month")))
          (setf (picker-state-year state) y (picker-state-month state) m)))))
  (values))

(fn (calendar-month-grid (values))
    ((id object-id) (state picker-state) (month integer))
  "Declare the month chooser and switch back to the day grid after selection."
  (dotimes (r 4)
    (row (:id r :width (%lui.layout:grow))
      (dotimes (c 3)
        (let ((m (+ 1 (* r 3) c)))
          (when (calendar-item (list id :month m) (subseq (aref
                                                           *month-names* (1-
                                                                          m))
                                                          0 3)
                               :width (%lui.layout:percent (/ 1 3))
                               :selected-p (= m month))
            (setf (picker-state-month state) m (picker-state-months-p
                                                state) nil))))))
  (values))

(fn (picker-calendar (values (or null date-parts) boolean))
    ((id object-id) (state picker-state) (selected (or null date-parts)))
  "Return the selected date parts (or NIL for Clear) and an action flag."
  (calendar-arrow-focus id state)
  (let* ((year (picker-state-year state))
         (month (picker-state-month state))
         (months (picker-state-months-p state))
         (width (%lui.layout:percent (/ 1 7)))
         (palette (toolkit-defaults))
         (foreground (getf palette :foreground "#ffffff"))
         (muted (%lui.widgets:muted-ink
                 foreground (getf palette :background "#303040")))
         (ink (getf palette :accent foreground)))

    ;; Header actions can change the year, month, or month-grid mode.
    (calendar-header id state year month months)
    (setf year (picker-state-year state) month (picker-state-month state))

    ;; Draw either month choices or the six-week day grid.
    (if (picker-state-months-p
         state)
        (calendar-month-grid id state month)
        ;; else
        (let ((start (calendar-start year month)))
          (row (:width (%lui.layout:grow))
            (loop :for name :across "SMTWTFS"
                  :for index :from 0
                  :do (row (:id index :width width :align :center)
                        (%label nil (string name) (list :font-size 13)))))
          (dotimes (week 6)
            (row (:id week :width (%lui.layout:grow))
              (dotimes (column 7)
                (multiple-value-bind (y m day)
                    (calendar-day year month
                                  (- (+ 1 (* week 7) column) start))
                  (let ((current (= m month)))
                    (when (calendar-item
                           (if current (list id :day day)
                               ;; else
                               (list id :adjacent y m day))
                           (princ-to-string day) :width width :center-text-p t
                           :disabled-p (not (<= 1 y 9999))
                           :foreground (if current foreground muted)
                           :selected-p
                           (equalp (make-date-parts y m day) selected))
                      (return-from picker-calendar
                        (values (make-date-parts y m day) t))))))))))

    ;; Footer actions clear the value or choose today without a day click.
    (row (:width (%lui.layout:grow))
      (when (calendar-item (list id :clear) "Clear" :foreground ink)
        (return-from picker-calendar (values nil t)))
      (column (:width (%lui.layout:grow)))
      (when (calendar-item (list id :today) "Today" :foreground ink)
        (return-from picker-calendar (values (local-today) t))))
    (values nil nil)))

(fn (calendar-trigger (values))
    ((id object-id) (state picker-state) (parts (or null date-parts))
     (trigger object-id) (terminal boolean))
  "Toggle the calendar from its icon or field and establish its initial date and focus."
  (let* ((input (list id :input))
         (field-click (or (activated-p input) (activated-p (list id
                                                                 :field))))
         (icon-click (calendar-item trigger "▦" :icon :calendar
                                    :accessible-name "Choose date"
                                    :height (%lui.layout:grow) :width
                                    (%lui.layout:fixed (if terminal 3 26)))))
    (cond ((and icon-click (picker-state-open-p state))
           (setf (picker-state-open-p state) nil (context-focus *context*)
                 trigger))
          ((or icon-click field-click)
           (when (or icon-click (not (picker-state-open-p state)))
             (let ((initial (or parts (local-today))))
               (setf (picker-state-open-p state) t (picker-state-months-p
                                                    state) nil
                                                    (picker-state-year state)
                                                    (aref initial 0)
                                                    (picker-state-month
                                                     state) (aref initial 1))
               (when icon-click
                 (setf (context-focus *context*) (list id :day (aref
                                                                initial
                                                                2))))))
           (when field-click (setf (context-focus *context*) input)))))
  (values))

(fn (calendar-popup (values (or null date-parts) boolean))
    ((id object-id) (state picker-state) (parts (or null date-parts)))
  "Declare the date-picker overlay and return a selected date and change flag."
  (let ((trigger (list id :calendar))
        (popup (list id :popup))
        (focus (context-focus *context*))
        (terminal (context-text-mode-p *context*)))

    ;; Resolve the field or icon action before considering dismissal.
    (calendar-trigger id state parts trigger terminal)
    (when (picker-state-open-p state)
      (let ((press (%lui.frame:context-pointer-press *context*))
            (bounds (previous-box popup)))

        ;; Outside clicks, Escape, and focus leaving the picker close the popup.
        (cond ((and press bounds
                    (not (some (lambda (target) (find :press (events-for
                                                              target) :key
                                                              #'event-kind))
                               (list trigger (list id :input) (list id
                                                                    :field))))
                    (not (%lui.frame:contains-p bounds (event-x press)
                                                (event-y press))))
               (setf (picker-state-open-p state) nil))
              ((find lui.key:escape (events-for focus) :key #'event-key)
               (setf (picker-state-open-p state) nil (context-focus
                                                      *context*) trigger))
              ((and bounds focus (not (and (consp focus) (equal (first focus)
                                                                id))))
               (setf (picker-state-open-p state) nil))
              (t
               (let ((*parent* (anchored-popup popup *parent*
                                               (list :width (%lui.layout:fixed
                                                            (if terminal 32
                                                                ;; else
                                                                260))))))

                 ;; A chosen date removes the overlay and returns focus to its trigger.
                 (multiple-value-bind (date action)
                     (picker-calendar id state
                                      (or
                                       parts
                                       (local-today)))
                   (when action
                     (pop (%lui.frame:context-popups *context*))
                     (setf (picker-state-open-p state) nil (context-focus
                                                            *context*)
                           trigger)
                     (return-from calendar-popup (values date t)))))))))
    (values nil nil)))

(fn (%date-picker (or null string))
    ((id object-id) (value (or null string)) &optional ((options list) nil))
  "Type a date as MM/DD/YYYY or pick it from the calendar. Return YYYY-MM-DD
or NIL when cleared. An incomplete or invalid draft preserves the model value."
  (let ((date (parse-picker-date value))
        (state (or (gethash id (context-state *context*))
                   (setf (gethash id (context-state *context*))
                         (make-picker-state))))
        (result value))

    ;; An external model change replaces the editable draft.
    (unless (equal value (picker-state-value state))
      (setf (picker-state-value state) value
            (picker-state-draft state) (if date
                                       (picker-display date)
                                           ;; else
                                           (or value ""))))

    ;; Keep incomplete typed text visible while preserving the model date.
    (column (:id id :width (getf options :width (%lui.layout:fit)))
      (panel (:id (list id :field) :interactive-p t :keyboard-focus-p nil
              :options (append options (list :direction :row :padding 1 :gap 0)))
             (let* ((old (picker-state-draft state))
               (draft (%text-field (list id :input) old
                                       (list :width (%lui.layout:grow)
                                            :accessible-name "Date"
                                            :placeholder "mm/dd/yyyy"))))
               (unless (equal old draft)
                 (let ((parsed (parse-picker-date draft)))
                   (setf (picker-state-draft state) draft)
                   (when (or parsed (zerop (length draft)))
                     (setf date parsed result (picker-value parsed)))
                   (when parsed
                     (setf (picker-state-year state) (aref parsed 0)
                           (picker-state-month state) (aref parsed 1))))))

             ;; Calendar choices replace both the model date and displayed draft.
             (multiple-value-bind (chosen action) (calendar-popup id state
                                                                  date)
               (when action
                 (setf date chosen result (picker-value chosen)
                       (picker-state-draft state) (picker-display chosen))
                 (request-frame)))))

    ;; Publish a committed change and schedule any remaining popup work.
    (unless (equal result value)
      (setf (picker-state-draft state) (picker-display date)
            (picker-state-value state) result)
      (request-frame))
    (when (and (picker-state-open-p state) (plusp (length (activated-ids))))
      (request-frame))
    result))

(define-widget searchable-combobox (id value choices)
    (disabled-p placeholder max-results password-p)
  "Return editable text, a change flag, and ID. :default-value initializes text.
Use :value for application-owned text. CHOICES supplies autocomplete suggestions.")

(define-widget date-picker (id value) ()
  "Return a date, a change flag, and ID. :default-value initializes the date.
Use :value for an application-owned YYYY-MM-DD date or NIL.")

(fn (measure-label (values real real))
    ((text string) &key ((width (or null real)) nil)
     ((font-family symbol) :sans-serif)
     ((font-size (or null real)) nil)
     ((font-weight (or null symbol)) nil))
  "Measure label text with current backend metrics and toolkit geometry.
Call during a frame. WIDTH is available content width; NIL measures intrinsic
size. Font size and weight default to the current toolkit's values. Returns
width and height in logical backend coordinates without declaring a widget."
  (let ((defaults (lui.toolkit:toolkit-defaults)))
    (funcall (context-measure *context*)
             (make-widget :kind :label :style (current-toolkit) :text text
                          :font-family font-family
                          :font-size (or font-size
                                         (getf defaults :font-size 16))
                          :font-weight (or font-weight
                                           (getf defaults :font-weight
                                                 :normal)))
             width)))
