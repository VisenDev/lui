(defpackage #:%lui.gl
  (:use #:cl #:%lui.fn #:%lui.layout #:lui.draw #:lui.font)
  (:export #:gpu #:attach-gpu #:open-gpu #:close-gpu #:gpu-renderer
           #:gpu-width
           #:gpu-height #:gpu-logical-width #:gpu-logical-height
           #:begin-gpu-frame #:present-gpu))
(in-package #:%lui.gl)

(cffi:define-foreign-library egl
    (:unix (:or "libEGL.so.1" "libEGL.so")))
(cffi:define-foreign-library opengl
    (:darwin (:framework "OpenGL"))
  (:unix (:or "libGL.so.1" "libGL.so")))
(cffi:use-foreign-library opengl)

(defmacro call-gl (name &rest args)
  "Call a named OpenGL entry point through CFFI with explicit foreign argument types."
  `(cffi:foreign-funcall ,name ,@args))

(defmacro call-egl (name &rest args)
  "Call a named EGL entry point through CFFI with explicit foreign argument types."
  ;; Resolve EGL only when using an EGL context, including on early-binding
  ;; FFI implementations. GLX needs libGL but does not require libEGL.
  `(cffi:foreign-funcall-pointer
    (cffi:foreign-symbol-pointer ,name :library 'egl) () ,@args))

(defstruct gl-ink
  "An immutable drawing command and its conservative physical scissor bounds."
  (bounds (make-box) :type box)
  (key nil :type list))

(defstruct gl-backdrop
  "A regional background texture and the drawing commands that produced it."
  (texture 0 :type integer)
  (sources (make-array 0 :element-type 'gl-ink) :type (vector gl-ink))
  (revision 0 :type integer))

(defstruct gpu
  "GL drawing resources and viewport dimensions for a current compatibility context."
  display surface context renderer
  (geometry (make-hash-table :test 'equalp) :type hash-table)
  (geometry-builds 0 :type integer)
  (program 0 :type integer)
  (clip (make-box) :type box)
  (ink (make-array 0 :element-type 'gl-ink :adjustable t :fill-pointer 0)
       :type (vector gl-ink))
  (backdrops (make-hash-table :test 'equal) :type hash-table)
  (backdrop-bytes 0 :type integer)
  (backdrop-revision 0 :type integer)
  (backdrop-size nil :type list)
  (width 1 :type integer)
  (height 1 :type integer)
  (logical-width 1 :type real)
  (logical-height 1 :type real))

(defparameter *vertex-source*
  "#version 120
void main() { gl_Position = ftransform(); }")

(defparameter *backdrop-fragment-source*
  "#version 120
uniform sampler2D backdrop;
uniform vec2 resolution;
uniform vec2 origin;
uniform vec4 bounds;
uniform float frost;
uniform float pixelScale;
void main() {
  vec2 p = gl_FragCoord.xy;
  vec2 lo = bounds.xy;
  vec2 hi = bounds.xy + bounds.zw;
  vec2 center = (lo + hi) * 0.5;
  float edge = min(min(p.x-lo.x, hi.x-p.x),
                   min(p.y-lo.y, hi.y-p.y));
  vec2 bend = normalize(p-center+vec2(0.001))
              * (3.0*pixelScale)
              * (1.0-smoothstep(0.0,12.0*pixelScale,edge));
  vec3 color = vec3(0.0);
  for (int x=-2; x<=2; ++x)
    for (int y=-2; y<=2; ++y)
      color += texture2D(backdrop,
        (p-origin+bend+vec2(float(x),float(y))*frost*0.25)
        /resolution).rgb;
  color /= 25.0;
  float luma = dot(color,vec3(0.2126,0.7152,0.0722));
  gl_FragColor = vec4(mix(vec3(luma),color,1.3),1.0);
}")

(fn (compile-shader integer) ((kind integer) (source string))
  "Compile SOURCE as KIND and signal BACKEND-ERROR with the shader log on failure."
  (let ((shader (call-gl "glCreateShader" :uint kind :uint)))
    (cffi:with-foreign-string (text source)
      (cffi:with-foreign-object (strings :pointer)
        (setf (cffi:mem-ref strings :pointer) text)
        (call-gl "glShaderSource" :uint shader :int 1
                 :pointer strings :pointer (cffi:null-pointer) :void)))
    (call-gl "glCompileShader" :uint shader :void)
    (cffi:with-foreign-object (status :int)
      (call-gl "glGetShaderiv" :uint shader :uint #x8b81
               :pointer status :void)
      (when (zerop (cffi:mem-ref status :int))
        (cffi:with-foreign-object (log :char 4096)
          (call-gl "glGetShaderInfoLog" :uint shader :int 4096
                   :pointer (cffi:null-pointer) :pointer log :void)
          (call-gl "glDeleteShader" :uint shader :void)
          (error '%lui.conditions:backend-error
                 :backend :gl
                 :operation :compile-shader
                 :format-control "GL shader: ~A"
                 :format-arguments (list (cffi:foreign-string-to-lisp
                                          log))))))
    shader))

(fn (make-program integer) ()
  "Link the backdrop shader program and signal BACKEND-ERROR on link failure."
  (let ((vertex (compile-shader #x8b31 *vertex-source*))
        (fragment 0)
        (program (call-gl "glCreateProgram" :uint)))
    (unwind-protect
         (progn
           (setf fragment (compile-shader #x8b30 *backdrop-fragment-source*))
           (call-gl "glAttachShader" :uint program :uint vertex :void)
           (call-gl "glAttachShader" :uint program :uint fragment :void)
           (call-gl "glLinkProgram" :uint program :void)
           (cffi:with-foreign-object (status :int)
             (call-gl "glGetProgramiv" :uint program :uint #x8b82
                      :pointer status :void)
             (when (zerop (cffi:mem-ref status :int))
               (call-gl "glDeleteProgram" :uint program :void)
               (error '%lui.conditions:backend-error
                      :backend :gl
                      :operation :make-program
                      :format-control "Cannot link the GL backdrop shader.")))
           program)
      (call-gl "glDeleteShader" :uint vertex :void)
      (when (plusp fragment)
        (call-gl "glDeleteShader" :uint fragment :void)))))

(fn (clear-geometry hash-table) ((gpu gpu))
  "Delete cached OpenGL display lists and clear GPU's contour cache."
  (maphash (lambda (key display-list)
             (declare (ignore key))
             (call-gl "glDeleteLists" :uint display-list :int 1 :void))
           (gpu-geometry gpu))
  (clrhash (gpu-geometry gpu)))

(fn (gl-color (values)) ((color string) (alpha real))
  "Set the current OpenGL color from a hexadecimal color and alpha."
  (let ((rgba (color-components color alpha)))
    (call-gl "glColor4f" :float (aref rgba 0) :float (aref rgba 1)
             :float (aref rgba 2) :float (aref rgba 3) :void))
  (values))

(fn (gl-geometry (values)) ((gpu gpu) (contours contours))
  "Draw filled contours, caching reusable geometry in GPU's display lists."
  (let ((display-list (gethash contours (gpu-geometry gpu))))
    (unless display-list
      ;; Keep resize/animation variants bounded; glyphs use font-unit contours.
      (when (>= (hash-table-count (gpu-geometry gpu)) 512)
        (clear-geometry gpu))
      (setf display-list (call-gl "glGenLists" :int 1 :uint))
      (when (zerop display-list) (error '%lui.conditions:backend-error
                                        :backend :gl
                                        :operation :gl-geometry
                                        :format-control "Cannot allocate GL geometry."))
      (call-gl "glNewList" :uint display-list :uint #x1300 :void)
      (unwind-protect
           (progn
             (call-gl "glBegin" :uint 4 :void)
             (unwind-protect
                  (%trapezoids
                   contours
                   (lambda (quad)
                     (dolist (index '(0 1 2 0 2 3))
                       (let ((point (aref quad index)))
                         (call-gl "glVertex2f"
                                  :float (float (car point) 1.0f0)
                                  :float (float (cdr point) 1.0f0) :void)))))
               (call-gl "glEnd" :void)))
        (call-gl "glEndList" :void))
      (incf (gpu-geometry-builds gpu))
      (setf (gethash contours (gpu-geometry gpu)) display-list))
    (call-gl "glCallList" :uint display-list :void))
  (values))

(fn (gl-polygons (values))
    ((gpu gpu) (contours contours) (color string) (alpha real))
  "Set fill color and draw contour geometry through GPU."
  (gl-color color alpha)
  (gl-geometry gpu contours)
  (values))

(fn (record-ink (values)) ((gpu gpu) (key list))
  "Record immutable drawing data so cached backgrounds detect content changes."
  (let ((clip (gpu-clip gpu)))
    (vector-push-extend
     (make-gl-ink :bounds clip
                  :key (list (box-x clip) (box-y clip)
                             (box-width clip) (box-height clip) key))
     (gpu-ink gpu)))
  (values))

(fn (gl-shape (values))
    ((gpu gpu) (contours contours) (color string) (alpha real))
  "Paint a rounded surface or outline using cached contour geometry."
  (record-ink gpu
              (list :shape
                    (map 'list (lambda (contour)
                                 (map 'list #'copy-list contour))
                         contours)
                    (copy-seq color) alpha))
  ;; Stipples reuse large contour batches in screen coordinates.
  ;; Submit them directly instead of copying thousands of points per frame.
  (when (> (length contours) 8)
    (return-from gl-shape (gl-polygons gpu contours color alpha)))
  ;; Cache the shape, not every screen position of a cell or debugger row.
  (let ((origin (let ((contour (find-if (lambda (points) (plusp (length
                                                                 points)))
                                        contours)))
                  (when contour (aref contour 0)))))
    (when origin
      (let* ((x (car origin))
             (y (cdr origin))
             (local (map 'contours (lambda (contour)
                                     (map 'contour (lambda (point)
                                                     (cons (- (car point) x)
                                                           (- (cdr point) y)))
                                          contour))
                         contours)))
        (call-gl "glPushMatrix" :void)
        (unwind-protect
             (progn
               (call-gl "glTranslatef" :float (float x 1.0f0)
                        :float (float y 1.0f0) :float 0.0f0 :void)
               (gl-polygons gpu local color alpha))
          (call-gl "glPopMatrix" :void)))))
  (values))

(fn (gl-text (values)) ((gpu gpu) (font font) (text string)
                        (x real) (y real) (color string))
  "Paint font glyph outlines at the requested baseline and color."
  (record-ink gpu (list :text (%font-loader font) (font-size font)
                        (copy-seq text) x y (copy-seq color)))
  (let* ((loader (%font-loader font))
         (scale (float (/ (font-size font) (zpb-ttf:units/em loader)) 1.0f0))
         (advance 0)
         (previous nil))
    (gl-color color 1)
    (call-gl "glPushMatrix" :void)
    (unwind-protect
         (progn
           (call-gl "glTranslatef" :float (float x 1.0f0)
                    :float (float y 1.0f0) :float 0.0f0 :void)
           (call-gl "glScalef" :float scale :float (- scale) :float 1.0f0
                    :void)
           (loop :for char :across text
                 :do (when previous
                       (incf advance (zpb-ttf:kerning-offset
                                      previous char loader))
                       (call-gl "glTranslatef" :float (float advance 1.0f0)
                                :float 0.0f0 :float 0.0f0 :void))
                 (gl-geometry gpu (glyph-polygons font char))
                 (setf advance (zpb-ttf:advance-width
                                (zpb-ttf:find-glyph char loader))
                       previous char)))
      (call-gl "glPopMatrix" :void)))
  (values))

(fn (pixel-box box) ((gpu gpu) (box box))
  "Scale logical BOX coordinates to framebuffer pixels."
  (let ((sx (/ (gpu-width gpu) (gpu-logical-width gpu)))
        (sy (/ (gpu-height gpu) (gpu-logical-height gpu))))
    (make-box :x (* sx (box-x box)) :y (* sy (box-y box))
              :width (* sx (box-width box))
              :height (* sy (box-height box)))))

(fn (gl-clip (values)) ((gpu gpu) (box box))
  "Set OpenGL scissoring from a logical clip rectangle."
  (let* ((pixels (pixel-box gpu box))
         (left (floor (box-x pixels)))
         (top (floor (box-y pixels)))
         (right (ceiling (box-right pixels)))
         (bottom (ceiling (box-bottom pixels))))
    (setf (gpu-clip gpu)
          (make-box :x left
                    :y (min top (- (gpu-height gpu)
                                   (max 0 (- bottom top))))
                    :width (max 0 (- right left))
                    :height (max 0 (- bottom top))))
    (call-gl "glScissor" :int left
             :int (max 0 (- (gpu-height gpu) bottom))
             :int (max 0 (- right left))
             :int (max 0 (- bottom top)) :void))
  (values))

(fn (uniform integer) ((gpu gpu) (name string))
  "Look up a named uniform location in GPU's backdrop shader program."
  (call-gl "glGetUniformLocation" :uint (gpu-program gpu)
           :string name :int))

(fn (backdrop-area box) ((gpu gpu) (box box) (frost real))
  "Bound the visible background and all refraction, blur, and bilinear samples."
  (let* ((w (gpu-width gpu))
         (h (gpu-height gpu))
         (area (intersect-boxes (pixel-box gpu box) (gpu-clip gpu)))
         (scale (/ w (gpu-logical-width gpu)))
         ;; Refraction, the outer blur taps, and bilinear interpolation.
         (margin (ceiling (+ 2 (* scale (+ 3 (/ (abs frost) 2))))))
         (x (max 0 (- (floor (box-x area)) margin)))
         (top (max 0 (- (floor (box-y area)) margin)))
         (right (min w (+ (ceiling (box-right area))
                          margin)))
         (bottom (min h (+ (ceiling (box-bottom area)) margin))))
    (make-box :x x :y top :width (max 0 (- right x))
              :height (max 0 (- bottom top)))))

(fn (clear-backdrops (values)) ((gpu gpu))
  "Delete cached regional textures and their retained drawing dependencies."
  (cffi:with-foreign-object (texture :uint)
    (maphash (lambda (key entry)
               (declare (ignore key))
               (setf (cffi:mem-ref texture :uint) (gl-backdrop-texture entry))
               (call-gl "glDeleteTextures" :int 1 :pointer texture :void))
             (gpu-backdrops gpu)))
  (clrhash (gpu-backdrops gpu))
  (setf (gpu-backdrop-bytes gpu) 0)
  (values))

(fn (allocate-backdrop gl-backdrop) ((gpu gpu) (area box) (key list))
  "Allocate a regional texture, bounding retained storage to 32 MiB or one region."
  (let ((bytes (* 4 (box-width area) (box-height area)))
        (entry (make-gl-backdrop)))
    (when (or (>= (hash-table-count (gpu-backdrops gpu)) 128)
              (> (+ (gpu-backdrop-bytes gpu) bytes) (* 32 1024 1024)))
      (clear-backdrops gpu))
    (cffi:with-foreign-object (texture :uint)
      (call-gl "glGenTextures" :int 1 :pointer texture :void)
      (setf (gl-backdrop-texture entry) (cffi:mem-ref texture :uint)))
    (setf (gethash key (gpu-backdrops gpu)) entry)
    (incf (gpu-backdrop-bytes gpu) bytes)
    (call-gl "glBindTexture" :uint #x0de1
             :uint (gl-backdrop-texture entry) :void)
    (dolist (parameter '(#x2801 #x2800))
      (call-gl "glTexParameteri" :uint #x0de1
               :uint parameter :int #x2601 :void))
    (dolist (parameter '(#x2802 #x2803))
      (call-gl "glTexParameteri" :uint #x0de1
               :uint parameter :int #x812f :void))
    (call-gl "glTexImage2D" :uint #x0de1 :int 0 :int #x8058
             :int (box-width area) :int (box-height area)
             :int 0 :uint #x1908 :uint #x1401
             :pointer (cffi:null-pointer) :void)
    entry))

(fn (backdrop-sources (vector gl-ink)) ((gpu gpu) (area box))
  "Select earlier commands whose scissor can affect this background's samples."
  (remove-if-not
   (lambda (ink)
     (let ((box (gl-ink-bounds ink)))
       (and (< (box-x box) (box-right area))
            (< (box-x area) (box-right box))
            (< (box-y box) (box-bottom area))
            (< (box-y area) (box-bottom box)))))
   (gpu-ink gpu)))

(fn (cached-backdrop gl-backdrop) ((gpu gpu) (area box))
  "Copy a background only when its preceding drawing commands changed."
  (let* ((key (list (box-x area) (box-y area)
                    (box-width area) (box-height area)))
         (entry (or (gethash key (gpu-backdrops gpu))
                    (allocate-backdrop gpu area key)))
         (sources (backdrop-sources gpu area))
         (previous (gl-backdrop-sources entry)))
    (call-gl "glBindTexture" :uint #x0de1
             :uint (gl-backdrop-texture entry) :void)
    ;; EQUAL is intentional: EQUALP would miss case-only text/color changes.
    (unless (and (plusp (gl-backdrop-revision entry))
                 (= (length sources) (length previous))
                 (every (lambda (a b) (equal (gl-ink-key a) (gl-ink-key b)))
                        sources previous))
      (call-gl "glCopyTexSubImage2D" :uint #x0de1 :int 0 :int 0 :int 0
               :int (box-x area) :int (- (gpu-height gpu) (box-bottom area))
               :int (box-width area) :int (box-height area) :void)
      (setf (gl-backdrop-sources entry) sources
            (gl-backdrop-revision entry) (incf (gpu-backdrop-revision gpu))))
    entry))

(fn (gl-backdrop-effect (values))
    ((gpu gpu) (box box) (radius real) (frost real))
  "Sample and blur the existing framebuffer behind a rounded translucent surface."
  (let ((area (backdrop-area gpu box frost)))
    (unless (and (plusp (box-width area)) (plusp (box-height area)))
      (return-from gl-backdrop-effect (values)))
    (let ((entry (cached-backdrop gpu area)))
      (record-ink gpu (list :backdrop (gl-backdrop-revision entry)
                            (box-x box) (box-y box) (box-width box)
                            (box-height box) radius frost)))

    ;; Configure the blur shader in physical pixels, then paint its contour.
    (call-gl "glUseProgram" :uint (gpu-program gpu) :void)
    (unwind-protect
         (progn
           (call-gl "glUniform1i" :int (uniform gpu "backdrop")
                    :int 0 :void)
           (call-gl "glUniform2f" :int (uniform gpu "resolution")
                    :float (float (box-width area) 1.0f0)
                    :float (float (box-height area) 1.0f0) :void)
           (call-gl "glUniform2f" :int (uniform gpu "origin")
                    :float (float (box-x area) 1.0f0)
                    :float (float (- (gpu-height gpu) (box-bottom area))
                                  1.0f0) :void)
           (let ((scale (/ (gpu-width gpu) (gpu-logical-width gpu))))
             (call-gl "glUniform1f" :int (uniform gpu "pixelScale")
                      :float (float scale 1.0f0) :void)
             (call-gl "glUniform1f" :int (uniform gpu "frost")
                      :float (float (* frost scale) 1.0f0) :void))
           (let ((box (pixel-box gpu box)))
             (call-gl "glUniform4f" :int (uniform gpu "bounds")
                      :float (float (box-x box) 1.0f0)
                      :float (float (- (gpu-height gpu) (box-y box)
                                       (box-height box)) 1.0f0)
                      :float (float (box-width box) 1.0f0)
                      :float (float (box-height box) 1.0f0) :void))
           (gl-polygons gpu
                        (make-array 1 :element-type 'contour
                                      :initial-element
                                      (rounded-polygon box radius))
                        "#ffffff" 1))
      (call-gl "glUseProgram" :uint 0 :void)))
  (values))

(fn (egl-check t) (result (operation string))
  "Return a successful EGL result or signal BACKEND-ERROR with the EGL status."
  (when (or (null result) (eql result 0)
            (and (cffi:pointerp result) (cffi:null-pointer-p result)))
    (error '%lui.conditions:backend-error
           :backend :gl
           :operation :egl-check
           :format-control "~A failed (EGL ~X)."
           :format-arguments (list operation (call-egl "eglGetError" :int))))
  result)

(fn (initialize-gpu gpu) ((gpu gpu) (font font))
  "Initialize GPU's shared drawing state and renderer callbacks using FONT."
  (setf (gpu-program gpu) (make-program))
  (setf (gpu-renderer gpu)
        (%make-renderer
         :font font
         :polygons (lambda (contours color alpha)
                     (gl-shape gpu contours color alpha))
         :text (lambda (font text x y color)
                 (gl-text gpu font text x y color))
         :clip (lambda (box) (gl-clip gpu box))
         :backdrop-effect (lambda (box radius frost)
                  (gl-backdrop-effect gpu box radius frost))))
  gpu)

(fn (attach-gpu gpu) ((font font) (width integer) (height integer))
  "Attach the shared renderer to a current OpenGL compatibility context."
  (let ((gpu (make-gpu :width width :height height
                       :logical-width width :logical-height height))
        (done nil))
    (unwind-protect
         (prog1 (initialize-gpu gpu font) (setf done t))
      (unless done (close-gpu gpu)))))

(fn (choose-egl-config (values))
    (display native-window attributes config count)
  "Choose a multisampled EGL configuration, falling back when unavailable."
  (loop :for value :in
        (list #x3024 8 #x3023 8 #x3022 8 #x3021 8
              #x3033 (if native-window 4 1) #x3040 8
              #x3032 1 #x3031 4 #x3038)
        :for i :from 0
        :do (setf (cffi:mem-aref attributes :int i) value))
  (egl-check
   (call-egl "eglChooseConfig" :pointer display
             :pointer attributes :pointer config
             :int 1 :pointer count :uint)
   "eglChooseConfig")
  (when (zerop (cffi:mem-ref count :int))
    ;; Multisampling is optional; retain the same rendering API.
    (setf (cffi:mem-aref attributes :int 12) #x3038)
    (egl-check
     (call-egl "eglChooseConfig" :pointer display
               :pointer attributes :pointer config
               :int 1 :pointer count :uint)
     "eglChooseConfig without multisampling"))
  (assert (plusp (cffi:mem-ref count :int)))
  (values))

(fn (create-egl-surface (values))
    ((gpu gpu) display native-window (width integer) (height integer))
  "Choose an EGL configuration and attach its context and surface to GPU."
  (cffi:with-foreign-objects ((attributes :int 17)
                              (config :pointer) (count :int))
    (choose-egl-config display native-window attributes
                       config count)
    (setf (gpu-context gpu)
          (egl-check
           (call-egl "eglCreateContext" :pointer display
                     :pointer (cffi:mem-ref config :pointer)
                     :pointer (cffi:null-pointer)
                     :pointer (cffi:null-pointer) :pointer)
           "eglCreateContext"))
    (setf (cffi:mem-aref attributes :int 0) #x3057
          (cffi:mem-aref attributes :int 1) width
          (cffi:mem-aref attributes :int 2) #x3056
          (cffi:mem-aref attributes :int 3) height
          (cffi:mem-aref attributes :int 4) #x3038)
    (setf (gpu-surface gpu)
          (egl-check
           (if native-window
               (call-egl "eglCreateWindowSurface"
                         :pointer display
                         :pointer (cffi:mem-ref config :pointer)
                         :pointer native-window
                         :pointer (cffi:null-pointer) :pointer)

               ;; else
               (call-egl "eglCreatePbufferSurface"
                         :pointer display
                         :pointer (cffi:mem-ref config :pointer)
                         :pointer attributes :pointer))
           "eglCreateSurface")))
  (values))

(fn (open-gpu gpu) (native-display native-window font
                    (width integer) (height integer))
  "Use a Wayland EGL window, or NIL/NIL for a surfaceless test buffer."
  (cffi:use-foreign-library egl)
  (let* ((display
          (if native-display
              (call-egl "eglGetDisplay" :pointer native-display :pointer)
              ;; else
              (call-egl "eglGetPlatformDisplay" :uint #x31dd
                        :pointer (cffi:null-pointer)
                        :pointer (cffi:null-pointer) :pointer)))
         (gpu (make-gpu :display display :width width :height height
                        :logical-width width :logical-height height))
         (complete nil))
    (unwind-protect
         (progn
           (egl-check display "eglGetDisplay")
           (egl-check
            (call-egl "eglInitialize" :pointer display
                      :pointer (cffi:null-pointer)
                      :pointer (cffi:null-pointer) :uint)
            "eglInitialize")
           (egl-check (call-egl "eglBindAPI" :uint #x30a2 :uint)
                      "eglBindAPI")
           (create-egl-surface gpu display native-window width height)
           (egl-check
            (call-egl "eglMakeCurrent" :pointer display
                      :pointer (gpu-surface gpu) :pointer (gpu-surface gpu)
                      :pointer (gpu-context gpu) :uint)
            "eglMakeCurrent")
           (initialize-gpu gpu font)
           (setf complete t)
           gpu)
      (unless complete (close-gpu gpu)))))

(fn (begin-gpu-frame (values)) ((gpu gpu))
  "Clear the back buffer and set the viewport, projection, clipping, and blending."
  (let ((size (list (gpu-width gpu) (gpu-height gpu)
                    (gpu-logical-width gpu) (gpu-logical-height gpu))))
    (unless (equal size (gpu-backdrop-size gpu))
      (clear-backdrops gpu)
      (setf (gpu-backdrop-size gpu) size)))
  (setf (fill-pointer (gpu-ink gpu)) 0)
  (call-gl "glViewport" :int 0 :int 0 :int (gpu-width gpu)
           :int (gpu-height gpu) :void)
  (call-gl "glDisable" :uint #x0c11 :void)
  (call-gl "glClearColor" :float 0.12f0 :float 0.14f0
           :float 0.19f0 :float 1.0f0 :void)
  (call-gl "glClear" :uint #x4000 :void)
  ;; Glyphs and rounded borders are polygons; use available sample coverage.
  (call-gl "glEnable" :uint #x809d :void)
  (call-gl "glEnable" :uint #x0be2 :void)
  ;; Keep the opaque destination alpha while blending translucent RGB overlays.
  (call-gl "glBlendFuncSeparate" :uint #x0302 :uint #x0303
           :uint 1 :uint #x0303 :void)
  (call-gl "glEnable" :uint #x0c11 :void)
  (gl-clip gpu (make-box :width (gpu-logical-width gpu)
                         :height (gpu-logical-height gpu)))
  (call-gl "glMatrixMode" :uint #x1701 :void)
  (call-gl "glLoadIdentity" :void)
  (call-gl "glOrtho" :double 0.0d0
           :double (float (gpu-logical-width gpu) 1.0d0)
           :double (float (gpu-logical-height gpu) 1.0d0)
           :double 0.0d0 :double -1.0d0 :double 1.0d0 :void)
  (call-gl "glMatrixMode" :uint #x1700 :void)
  (call-gl "glLoadIdentity" :void)
  (values))

(fn (present-gpu integer) ((gpu gpu))
  "Swap the EGL surface created by OPEN-GPU. GLX presents its own drawable."
  (egl-check
   (call-egl "eglSwapBuffers" :pointer (gpu-display gpu)
             :pointer (gpu-surface gpu) :uint)
   "eglSwapBuffers"))

(fn (close-gpu (or null integer)) ((gpu gpu))
  "Release cached geometry, shader, and texture; also release an owned EGL context."
  (clear-geometry gpu)
  (clear-backdrops gpu)
  (when (plusp (gpu-program gpu))
    (call-gl "glDeleteProgram" :uint (gpu-program gpu) :void))
  (when (gpu-display gpu)
    (call-egl "eglMakeCurrent" :pointer (gpu-display gpu)
              :pointer (cffi:null-pointer) :pointer (cffi:null-pointer)
              :pointer (cffi:null-pointer) :uint)
    (when (gpu-surface gpu)
      (call-egl "eglDestroySurface" :pointer (gpu-display gpu)
                :pointer (gpu-surface gpu) :uint))
    (when (gpu-context gpu)
      (call-egl "eglDestroyContext" :pointer (gpu-display gpu)
                :pointer (gpu-context gpu) :uint))
    (call-egl "eglTerminate" :pointer (gpu-display gpu) :uint)))
