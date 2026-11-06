(defpackage #:lui.gl
  (:use #:cl #:lui.fn #:lui.layout #:lui.draw #:lui.font)
  (:export #:gpu #:attach-gpu #:open-gpu #:close-gpu #:gpu-renderer #:gpu-width
           #:gpu-height #:gpu-logical-width #:gpu-logical-height
           #:begin-gpu-frame #:present-gpu))
(in-package #:lui.gl)

(cffi:define-foreign-library egl
  (:unix (:or "libEGL.so.1" "libEGL.so")))
(cffi:define-foreign-library opengl
  (:darwin (:framework "OpenGL"))
  (:unix (:or "libGL.so.1" "libGL.so")))
(cffi:use-foreign-library opengl)

(defmacro call-gl (name &rest args)
  `(cffi:foreign-funcall ,name ,@args))

(defmacro call-egl (name &rest args)
  ;; Resolve EGL only when using an EGL context, including on early-binding
  ;; FFI implementations. GLX needs libGL but does not require libEGL.
  `(cffi:foreign-funcall-pointer
    (cffi:foreign-symbol-pointer ,name :library 'egl) () ,@args))

(defstruct gpu
  "GL drawing resources and viewport dimensions for a current compatibility context."
  display surface context renderer
  (geometry (make-hash-table :test 'equal) :type hash-table)
  (geometry-builds 0 :type integer)
  (program 0 :type integer)
  (texture 0 :type integer)
  (texture-width 0 :type integer)
  (texture-height 0 :type integer)
  (width 1 :type integer)
  (height 1 :type integer)
  (logical-width 1 :type real)
  (logical-height 1 :type real))

(defparameter *vertex-source*
  "#version 120
void main() { gl_Position = ftransform(); }")

(defparameter *glass-source*
  "#version 120
uniform sampler2D backdrop;
uniform vec2 resolution;
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
        (p+bend+vec2(float(x),float(y))*frost*0.25)
        /resolution).rgb;
  color /= 25.0;
  float luma = dot(color,vec3(0.2126,0.7152,0.0722));
  gl_FragColor = vec4(mix(vec3(luma),color,1.3),1.0);
}")

(fn compile-shader ((kind integer) (source string))
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
          (error "GL shader: ~A" (cffi:foreign-string-to-lisp log)))))
    shader))

(fn make-program ()
  (let ((vertex (compile-shader #x8b31 *vertex-source*))
        (fragment 0)
        (program (call-gl "glCreateProgram" :uint)))
    (unwind-protect
         (progn
           (setf fragment (compile-shader #x8b30 *glass-source*))
           (call-gl "glAttachShader" :uint program :uint vertex :void)
           (call-gl "glAttachShader" :uint program :uint fragment :void)
           (call-gl "glLinkProgram" :uint program :void)
           (cffi:with-foreign-object (status :int)
             (call-gl "glGetProgramiv" :uint program :uint #x8b82
                      :pointer status :void)
             (when (zerop (cffi:mem-ref status :int))
               (call-gl "glDeleteProgram" :uint program :void)
               (error "Cannot link the GL glass shader.")))
           program)
      (call-gl "glDeleteShader" :uint vertex :void)
      (when (plusp fragment)
        (call-gl "glDeleteShader" :uint fragment :void)))))

(fn clear-geometry ((gpu gpu))
  (maphash (lambda (key display-list)
             (declare (ignore key))
             (call-gl "glDeleteLists" :uint display-list :int 1 :void))
           (gpu-geometry gpu))
  (clrhash (gpu-geometry gpu)))

(fn gl-color ((color string) (alpha real))
  (destructuring-bind (red green blue opacity)
      (color-components color alpha)
    (call-gl "glColor4f" :float (float red 1.0)
             :float (float green 1.0) :float (float blue 1.0)
             :float (float opacity 1.0) :void)))

(fn gl-geometry ((gpu gpu) (contours list))
  (let ((display-list (gethash contours (gpu-geometry gpu))))
    (unless display-list
      ;; Keep resize/animation variants bounded; glyphs use font-unit contours.
      (when (>= (hash-table-count (gpu-geometry gpu)) 512)
        (clear-geometry gpu))
      (setf display-list (call-gl "glGenLists" :int 1 :uint))
      (when (zerop display-list) (error "Cannot allocate GL geometry."))
      (call-gl "glNewList" :uint display-list :uint #x1300 :void)
      (unwind-protect
           (progn
             (call-gl "glBegin" :uint 4 :void)
             (unwind-protect
                  (trapezoids
                   contours
                   (lambda (quad)
                     (dolist (index '(0 1 2 0 2 3))
                       (let ((point (nth index quad)))
                         (call-gl "glVertex2f"
                                  :float (float (car point) 1.0)
                                  :float (float (cdr point) 1.0) :void)))))
               (call-gl "glEnd" :void)))
        (call-gl "glEndList" :void))
      (incf (gpu-geometry-builds gpu))
      (setf (gethash contours (gpu-geometry gpu)) display-list))
    (call-gl "glCallList" :uint display-list :void)))

(fn gl-polygons ((gpu gpu) (contours list) (color string) (alpha real))
  (gl-color color alpha)
  (gl-geometry gpu contours))

(fn gl-shape ((gpu gpu) (contours list) (color string) (alpha real))
  ;; Stipples reuse large contour batches in screen coordinates.
  ;; Submit them directly instead of copying thousands of points per frame.
  (when (nthcdr 8 contours)
    (return-from gl-shape (gl-polygons gpu contours color alpha)))
  ;; Cache the shape, not every screen position of a cell or debugger row.
  (let ((origin (first (find-if #'consp contours))))
    (when origin
      (let* ((x (car origin)) (y (cdr origin))
             (local (mapcar (lambda (contour)
                              (mapcar (lambda (point)
                                        (cons (- (car point) x)
                                              (- (cdr point) y)))
                                      contour))
                            contours)))
        (call-gl "glPushMatrix" :void)
        (unwind-protect
             (progn
               (call-gl "glTranslatef" :float (float x 1.0)
                        :float (float y 1.0) :float 0.0 :void)
               (gl-polygons gpu local color alpha))
          (call-gl "glPopMatrix" :void))))))

(fn gl-text ((gpu gpu) (font font) (text string)
            (x real) (y real) (color string))
  (let* ((loader (font-loader font))
         (scale (float (/ (font-size font) (zpb-ttf:units/em loader)) 1.0))
         (advance 0) (previous nil))
    (gl-color color 1)
    (call-gl "glPushMatrix" :void)
    (unwind-protect
         (progn
           (call-gl "glTranslatef" :float (float x 1.0)
                    :float (float y 1.0) :float 0.0 :void)
           (call-gl "glScalef" :float scale :float (- scale) :float 1.0 :void)
           (loop :for char :across text
                 :do (when previous
                       (incf advance (zpb-ttf:kerning-offset
                                      previous char loader))
                       (call-gl "glTranslatef" :float (float advance 1.0)
                                :float 0.0 :float 0.0 :void))
                     (gl-geometry gpu (glyph-polygons font char))
                     (setf advance (zpb-ttf:advance-width
                                    (zpb-ttf:find-glyph char loader))
                           previous char)))
      (call-gl "glPopMatrix" :void))))

(fn pixel-box ((gpu gpu) (box box))
  (let ((sx (/ (gpu-width gpu) (gpu-logical-width gpu)))
        (sy (/ (gpu-height gpu) (gpu-logical-height gpu))))
    (make-box :x (* sx (box-x box)) :y (* sy (box-y box))
              :width (* sx (box-width box))
              :height (* sy (box-height box)))))

(fn gl-clip ((gpu gpu) (box box))
  (let* ((pixels (pixel-box gpu box))
         (left (floor (box-x pixels)))
         (top (floor (box-y pixels)))
         (right (ceiling (+ (box-x pixels) (box-width pixels))))
         (bottom (ceiling (+ (box-y pixels) (box-height pixels)))))
    (call-gl "glScissor" :int left
             :int (max 0 (- (gpu-height gpu) bottom))
             :int (max 0 (- right left))
             :int (max 0 (- bottom top)) :void)))

(fn uniform ((gpu gpu) (name string))
  (call-gl "glGetUniformLocation" :uint (gpu-program gpu)
           :string name :int))

(fn gl-glass ((gpu gpu) (box box) (radius real) (frost real))
  (call-gl "glBindTexture" :uint #x0de1 :uint (gpu-texture gpu) :void)
  (let* ((w (gpu-width gpu)) (h (gpu-height gpu))
         (area (pixel-box gpu box))
         (scale (/ w (gpu-logical-width gpu)))
         ;; Refraction, the outer blur taps, and bilinear interpolation.
         (margin (ceiling (+ 2 (* scale (+ 3 (/ (abs frost) 2))))))
         (x (max 0 (- (floor (box-x area)) margin)))
         (top (max 0 (- (floor (box-y area)) margin)))
         (right (min w (+ (ceiling (+ (box-x area) (box-width area)))
                          margin)))
         (bottom (min h (+ (ceiling (+ (box-y area) (box-height area)))
                           margin)))
         (y (- h bottom)))
    (unless (and (< x right) (< top bottom)) (return-from gl-glass nil))
    (unless (and (= w (gpu-texture-width gpu)) (= h (gpu-texture-height gpu)))
      (call-gl "glTexImage2D" :uint #x0de1 :int 0 :int #x1908
               :int w :int h :int 0 :uint #x1908 :uint #x1401
               :pointer (cffi:null-pointer) :void)
      (setf (gpu-texture-width gpu) w (gpu-texture-height gpu) h))
    (call-gl "glCopyTexSubImage2D" :uint #x0de1 :int 0 :int x :int y
             :int x :int y :int (- right x) :int (- bottom top) :void))
  (call-gl "glUseProgram" :uint (gpu-program gpu) :void)
  (unwind-protect
       (progn
         (call-gl "glUniform1i" :int (uniform gpu "backdrop")
                  :int 0 :void)
         (call-gl "glUniform2f" :int (uniform gpu "resolution")
                  :float (float (gpu-width gpu) 1.0)
                  :float (float (gpu-height gpu) 1.0) :void)
         (let ((scale (/ (gpu-width gpu) (gpu-logical-width gpu))))
           (call-gl "glUniform1f" :int (uniform gpu "pixelScale")
                    :float (float scale 1.0) :void)
           (call-gl "glUniform1f" :int (uniform gpu "frost")
                    :float (float (* frost scale) 1.0) :void))
         (let ((box (pixel-box gpu box)))
           (call-gl "glUniform4f" :int (uniform gpu "bounds")
                  :float (float (box-x box) 1.0)
                  :float (float (- (gpu-height gpu) (box-y box)
                                   (box-height box)) 1.0)
                  :float (float (box-width box) 1.0)
                  :float (float (box-height box) 1.0) :void))
         (gl-polygons gpu (list (rounded-polygon box radius)) "#ffffff" 1))
    (call-gl "glUseProgram" :uint 0 :void)))

(fn egl-check (result (operation string))
  (when (or (null result) (eql result 0)
            (and (cffi:pointerp result) (cffi:null-pointer-p result)))
    (error "~A failed (EGL ~X)." operation
           (call-egl "eglGetError" :int)))
  result)

(fn initialize-gpu ((gpu gpu) (font font))
  (setf (gpu-program gpu) (make-program))
  (cffi:with-foreign-object (texture :uint)
    (call-gl "glGenTextures" :int 1 :pointer texture :void)
    (setf (gpu-texture gpu) (cffi:mem-ref texture :uint)))
  (call-gl "glBindTexture" :uint #x0de1
           :uint (gpu-texture gpu) :void)
  (dolist (parameter '(#x2801 #x2800))
    (call-gl "glTexParameteri" :uint #x0de1
             :uint parameter :int #x2601 :void))
  (dolist (parameter '(#x2802 #x2803))
    (call-gl "glTexParameteri" :uint #x0de1
             :uint parameter :int #x812f :void))
  (setf (gpu-renderer gpu)
        (make-renderer
         :font font
         :polygons (lambda (contours color alpha)
                     (gl-shape gpu contours color alpha))
         :text (lambda (font text x y color)
                 (gl-text gpu font text x y color))
         :clip (lambda (box) (gl-clip gpu box))
         :glass (lambda (box radius frost)
                  (gl-glass gpu box radius frost))))
  gpu)

(fn attach-gpu ((font font) (width integer) (height integer))
  "Attach the shared renderer to a current OpenGL compatibility context."
  (let ((gpu (make-gpu :width width :height height
                       :logical-width width :logical-height height))
        (done nil))
    (unwind-protect
         (prog1 (initialize-gpu gpu font) (setf done t))
      (unless done (close-gpu gpu)))))

(fn open-gpu (native-display native-window font
             (width integer) (height integer))
  "Use a Wayland EGL window, or NIL/NIL for a surfaceless test buffer."
  (cffi:use-foreign-library egl)
  (let* ((display
           (if native-display
               (call-egl "eglGetDisplay" :pointer native-display :pointer)
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
           (cffi:with-foreign-objects ((attributes :int 17)
                                      (config :pointer) (count :int))
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
                        (call-egl "eglCreatePbufferSurface"
                                 :pointer display
                                 :pointer (cffi:mem-ref config :pointer)
                                 :pointer attributes :pointer))
                    "eglCreateSurface")))
           (egl-check
            (call-egl "eglMakeCurrent" :pointer display
                     :pointer (gpu-surface gpu) :pointer (gpu-surface gpu)
                     :pointer (gpu-context gpu) :uint)
            "eglMakeCurrent")
           (initialize-gpu gpu font)
           (setf complete t)
           gpu)
      (unless complete (close-gpu gpu)))))

(fn begin-gpu-frame ((gpu gpu))
  "Clear the back buffer and set the viewport, projection, clipping, and blending."
  (call-gl "glViewport" :int 0 :int 0 :int (gpu-width gpu)
           :int (gpu-height gpu) :void)
  (call-gl "glDisable" :uint #x0c11 :void)
  (call-gl "glClearColor" :float 0.12 :float 0.14
           :float 0.19 :float 1.0 :void)
  (call-gl "glClear" :uint #x4000 :void)
  (call-gl "glEnable" :uint #x0be2 :void)
  ;; Keep the opaque destination alpha while blending translucent RGB overlays.
  (call-gl "glBlendFuncSeparate" :uint #x0302 :uint #x0303
           :uint 1 :uint #x0303 :void)
  (call-gl "glEnable" :uint #x0c11 :void)
  (call-gl "glMatrixMode" :uint #x1701 :void)
  (call-gl "glLoadIdentity" :void)
  (call-gl "glOrtho" :double 0.0d0
           :double (float (gpu-logical-width gpu) 1.0d0)
           :double (float (gpu-logical-height gpu) 1.0d0)
           :double 0.0d0 :double -1.0d0 :double 1.0d0 :void)
  (call-gl "glMatrixMode" :uint #x1700 :void)
  (call-gl "glLoadIdentity" :void))

(fn present-gpu ((gpu gpu))
  "Swap the EGL surface created by OPEN-GPU. GLX presents its own drawable."
  (egl-check
   (call-egl "eglSwapBuffers" :pointer (gpu-display gpu)
            :pointer (gpu-surface gpu) :uint)
   "eglSwapBuffers"))

(fn close-gpu ((gpu gpu))
  "Release cached geometry, shader, and texture; also release an owned EGL context."
  (clear-geometry gpu)
  (when (plusp (gpu-program gpu))
    (call-gl "glDeleteProgram" :uint (gpu-program gpu) :void))
  (when (plusp (gpu-texture gpu))
    (cffi:with-foreign-object (texture :uint)
      (setf (cffi:mem-ref texture :uint) (gpu-texture gpu))
      (call-gl "glDeleteTextures" :int 1 :pointer texture :void)))
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
