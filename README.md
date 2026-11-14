# Demo and Docs
https://visendev.github.io/lui/

# Hello World

```lisp
(lui:run (lambda () (lui:label "hello world")))
```

# FAQ

## What is this? 
  Lui is an immediate mode common lisp ui library. You can run the demo via
  `make demo` (you must have cffi and zpb-ttf `load-system`'able).
  
## Was this developed with AI?
  Yes.
  
## Is the README written by AI?
  No, the readme was entirely human written.
  
## Is this slop?
  Depends on what you mean by that. If you consider anything developed using
  AI to be slop, then yes. However, because I am developing this project
  primary to for me to use (manually coding) at work to build business 
  software, code quality is very important. 
  
  To that end, the codebase has purposefully been kept very small and minimal.
  The core of the ui library is less than 5kloc measured by 
  [CLOC](https://github.com/aldanial/cloc), the rest of the code being about
  another 10kloc for backends, and various widget styling toolkits. I have
  kept the codebase small that way it is easy for me to manually review all 
  of the code. For reference, the 'Core' folder of [McCLIM](https://codeberg.org/mcclim/mcclim/)
  is ~36kloc measured using the same tool.
  
  The layout engine is based on a lisp port of the excellent 
  [CLAY](https://github.com/nicbarker/clay) UI layout library by Nic Barker.
  And the windowing backends are based on my [incomplete (human written)
  common lisp windowing library](https://github.com/visendev/clgfw).
  
## Why did you build this?
  Common Lisp has a painful dearth of UI libraries. I have a lot of things
  I want out of a UI library, and this is my attempt to build my dream 
  UI Library. Namely, the features I wanted:
  - Native Lisp Windowing (no wrappers over glfw or SDL)
  - Must support the web.
  - Must support TUI rendering, so applications built with it can be used on headless systems.
  - Must be able to emulate a wide variety of other UI toolkits (Motif, Garnet, etc...)
  - No mandatory dependencies.
  - Minimal, preferrably below 10kloc (we are a bit above this right now).
  - Immediate Mode
  
## What dependencies does Lui require?
  The core has no external dependencies, native backends require CFFI for
  OS communication and [zpb-ttf](https://github.com/xach/zpb-ttf) for font
  rendering. Shinmera's [font-discovery](https://codeberg.org/shinmera/font-discovery.git)
  is optionally used to find font-files. You can push `:lui-no-font-discovery`
  to disable this. The terminal backend uses [uncursed](https://github.com/plisp/uncursed).
  
## How do I use a custom font?
  Override the value of `lui.font:*font-path*` to the path to the font you 
  want to use.
  
```lisp
  (let ((lui.font:*font-path* "/usr/share/fonts/TTF/DejaVuSans.ttf"))
           (lui:run (lambda () (lui:label "hello world"))))
```
  
## Is this just a wrapper over a C windowing library?
  No, everything interfaces with OS apis directly, allowing you to build
  small self contained lisp executables.
  
## What backends are supported?
  Linux Wayland,
  Linux X11,
  ANSI Terminal (TUI),
  Macos Cocoa,
  Windows Win32,
  PDF (for doing document layouts),
  Web via [JSCL](https://github.com/jscl-project/jscl),
  Web via ECL and EMSCRIPTEN,
  
## What is the "Debugger"?
  Lui has a built in inspector you can use to examine the UI tree in real
  time while your application is running. To test it out, just click
  the "Show Debugger" button on [the docs page](https://visendev.github.io/lui/).
  
## Do you need to write different UI code based on the platform?
  No, write your UI code once, and it can be run natively, in your terminal,
  or on the web.

## What is this `fn` macro all over the source code?
  `fn` is a (human written) macro used to simplify type declarations on 
  functions. I originally wrote it for another project, but I am using it
  here because type annotations make it much easier to understand unfamiliar
  code and review things.
  
## Why are vectors used so much in the source code? Isn't this (LIS)t (P)rocessing??
  More type safety to increase code understandability. Lists can't be given
  element types, vectors can. 
  
## Why aren't you using CLOS?
  JSCL can't compile `setf` on CLOS accessors, so classes are not as ergonomic
  to use, and structs are a lot faster anyways.
  
## What styles does the UI support?
  Lui has the concept of different widget "toolkits", with different
  toolkits each emulating the look and feel of various famous UI libraries
  or OS native functionality. 
  
  Glass
  ![](./assets/glass.png)

  Motif
  ![](./assets/motif.png)

  Garnet (based on [the library from the 80s](https://www.cs.cmu.edu/afs/cs.cmu.edu/project/garnet/www/)
  ![](./assets/garnet.png)

  QT
  ![](./assets/qt.png)

  Macos
  ![](./assets/macos.png)

## What does the TUI version of the UI look like?
  ![](./assets/tui.png)

