(defpackage #:lui.key
  (:use)
  (:export #:key #:key->char #:char->key
           #:quote #:comma #:minus #:period #:slash #:zero #:one #:two
           #:three #:four #:five #:six #:seven #:eight #:nine #:semicolon
           #:equal #:a #:b #:c #:d #:e #:f #:g #:h #:i #:j #:k #:l #:m #:n
           #:o #:p #:q #:r #:s #:t #:u #:v #:w #:x #:y #:z #:left-bracket
           #:backslash #:right-bracket #:backtick #:space #:escape #:enter
           #:tab #:backspace #:insert #:delete #:right #:left #:down #:up
           #:page-up #:page-down #:home #:end #:caps-lock #:scroll-lock
           #:num-lock #:print-screen #:pause #:f1 #:f2 #:f3 #:f4 #:f5 #:f6
           #:f7 #:f8 #:f9 #:f10 #:f11 #:f12 #:left-shift #:right-shift
           #:left-control #:right-control #:left-alt #:right-alt
           #:left-super #:right-super #:left-meta #:right-meta #:left-hyper
           #:right-hyper #:kb-menu #:keypad-0 #:keypad-1 #:keypad-2
           #:keypad-3 #:keypad-4 #:keypad-5 #:keypad-6 #:keypad-7 #:keypad-8
           #:keypad-9 #:keypad-decimal #:keypad-divide #:keypad-multiply
           #:keypad-subtract #:keypad-add #:keypad-enter #:keypad-equal
           #:shift-left #:shift-right #:shift-home #:shift-end #:word-left
           #:word-right #:shift-word-left #:shift-word-right #:select-all
           #:copy #:paste #:kill-end #:kill-start #:kill-word
           #:kill-word-forward #:yank #:transpose #:backward))
(in-package #:lui.key)

;; Keyboard names follow CLGFW; each constant evaluates to its own symbol.
(cl:defconstant quote 'lui.key:quote
  "The QUOTE key.")
(cl:defconstant comma 'lui.key:comma
  "The COMMA key.")
(cl:defconstant minus 'lui.key:minus
  "The MINUS key.")
(cl:defconstant period 'lui.key:period
  "The PERIOD key.")
(cl:defconstant slash 'lui.key:slash
  "The SLASH key.")
(cl:defconstant zero 'lui.key:zero
  "The ZERO key.")
(cl:defconstant one 'lui.key:one
  "The ONE key.")
(cl:defconstant two 'lui.key:two
  "The TWO key.")
(cl:defconstant three 'lui.key:three
  "The THREE key.")
(cl:defconstant four 'lui.key:four
  "The FOUR key.")
(cl:defconstant five 'lui.key:five
  "The FIVE key.")
(cl:defconstant six 'lui.key:six
  "The SIX key.")
(cl:defconstant seven 'lui.key:seven
  "The SEVEN key.")
(cl:defconstant eight 'lui.key:eight
  "The EIGHT key.")
(cl:defconstant nine 'lui.key:nine
  "The NINE key.")
(cl:defconstant semicolon 'lui.key:semicolon
  "The SEMICOLON key.")
(cl:defconstant equal 'lui.key:equal
  "The EQUAL key.")
(cl:defconstant a 'lui.key:a
  "The A key.")
(cl:defconstant b 'lui.key:b
  "The B key.")
(cl:defconstant c 'lui.key:c
  "The C key.")
(cl:defconstant d 'lui.key:d
  "The D key.")
(cl:defconstant e 'lui.key:e
  "The E key.")
(cl:defconstant f 'lui.key:f
  "The F key.")
(cl:defconstant g 'lui.key:g
  "The G key.")
(cl:defconstant h 'lui.key:h
  "The H key.")
(cl:defconstant i 'lui.key:i
  "The I key.")
(cl:defconstant j 'lui.key:j
  "The J key.")
(cl:defconstant k 'lui.key:k
  "The K key.")
(cl:defconstant l 'lui.key:l
  "The L key.")
(cl:defconstant m 'lui.key:m
  "The M key.")
(cl:defconstant n 'lui.key:n
  "The N key.")
(cl:defconstant o 'lui.key:o
  "The O key.")
(cl:defconstant p 'lui.key:p
  "The P key.")
(cl:defconstant q 'lui.key:q
  "The Q key.")
(cl:defconstant r 'lui.key:r
  "The R key.")
(cl:defconstant s 'lui.key:s
  "The S key.")
(cl:defconstant t 'lui.key:t
  "The T key.")
(cl:defconstant u 'lui.key:u
  "The U key.")
(cl:defconstant v 'lui.key:v
  "The V key.")
(cl:defconstant w 'lui.key:w
  "The W key.")
(cl:defconstant x 'lui.key:x
  "The X key.")
(cl:defconstant y 'lui.key:y
  "The Y key.")
(cl:defconstant z 'lui.key:z
  "The Z key.")
(cl:defconstant left-bracket 'lui.key:left-bracket
  "The LEFT-BRACKET key.")
(cl:defconstant backslash 'lui.key:backslash
  "The BACKSLASH key.")
(cl:defconstant right-bracket 'lui.key:right-bracket
  "The RIGHT-BRACKET key.")
(cl:defconstant backtick 'lui.key:backtick
  "The BACKTICK key.")
(cl:defconstant space 'lui.key:space
  "The SPACE key.")
(cl:defconstant escape 'lui.key:escape
  "The ESCAPE key.")
(cl:defconstant enter 'lui.key:enter
  "The ENTER key.")
(cl:defconstant tab 'lui.key:tab
  "The TAB key.")
(cl:defconstant backspace 'lui.key:backspace
  "The BACKSPACE key.")
(cl:defconstant insert 'lui.key:insert
  "The INSERT key.")
(cl:defconstant delete 'lui.key:delete
  "The DELETE key.")
(cl:defconstant right 'lui.key:right
  "The RIGHT key.")
(cl:defconstant left 'lui.key:left
  "The LEFT key.")
(cl:defconstant down 'lui.key:down
  "The DOWN key.")
(cl:defconstant up 'lui.key:up
  "The UP key.")
(cl:defconstant page-up 'lui.key:page-up
  "The PAGE-UP key.")
(cl:defconstant page-down 'lui.key:page-down
  "The PAGE-DOWN key.")
(cl:defconstant home 'lui.key:home
  "The HOME key.")
(cl:defconstant end 'lui.key:end
  "The END key.")
(cl:defconstant caps-lock 'lui.key:caps-lock
  "The CAPS-LOCK key.")
(cl:defconstant scroll-lock 'lui.key:scroll-lock
  "The SCROLL-LOCK key.")
(cl:defconstant num-lock 'lui.key:num-lock
  "The NUM-LOCK key.")
(cl:defconstant print-screen 'lui.key:print-screen
  "The PRINT-SCREEN key.")
(cl:defconstant pause 'lui.key:pause
  "The PAUSE key.")
(cl:defconstant f1 'lui.key:f1
  "The F1 key.")
(cl:defconstant f2 'lui.key:f2
  "The F2 key.")
(cl:defconstant f3 'lui.key:f3
  "The F3 key.")
(cl:defconstant f4 'lui.key:f4
  "The F4 key.")
(cl:defconstant f5 'lui.key:f5
  "The F5 key.")
(cl:defconstant f6 'lui.key:f6
  "The F6 key.")
(cl:defconstant f7 'lui.key:f7
  "The F7 key.")
(cl:defconstant f8 'lui.key:f8
  "The F8 key.")
(cl:defconstant f9 'lui.key:f9
  "The F9 key.")
(cl:defconstant f10 'lui.key:f10
  "The F10 key.")
(cl:defconstant f11 'lui.key:f11
  "The F11 key.")
(cl:defconstant f12 'lui.key:f12
  "The F12 key.")
(cl:defconstant left-shift 'lui.key:left-shift
  "The LEFT-SHIFT key.")
(cl:defconstant right-shift 'lui.key:right-shift
  "The RIGHT-SHIFT key.")
(cl:defconstant left-control 'lui.key:left-control
  "The LEFT-CONTROL key.")
(cl:defconstant right-control 'lui.key:right-control
  "The RIGHT-CONTROL key.")
(cl:defconstant left-alt 'lui.key:left-alt
  "The LEFT-ALT key.")
(cl:defconstant right-alt 'lui.key:right-alt
  "The RIGHT-ALT key.")
(cl:defconstant left-super 'lui.key:left-super
  "The LEFT-SUPER key.")
(cl:defconstant right-super 'lui.key:right-super
  "The RIGHT-SUPER key.")
(cl:defconstant left-meta 'lui.key:left-meta
  "The LEFT-META key.")
(cl:defconstant right-meta 'lui.key:right-meta
  "The RIGHT-META key.")
(cl:defconstant left-hyper 'lui.key:left-hyper
  "The LEFT-HYPER key.")
(cl:defconstant right-hyper 'lui.key:right-hyper
  "The RIGHT-HYPER key.")
(cl:defconstant kb-menu 'lui.key:kb-menu
  "The KB-MENU key.")
(cl:defconstant keypad-0 'lui.key:keypad-0
  "The KEYPAD-0 key.")
(cl:defconstant keypad-1 'lui.key:keypad-1
  "The KEYPAD-1 key.")
(cl:defconstant keypad-2 'lui.key:keypad-2
  "The KEYPAD-2 key.")
(cl:defconstant keypad-3 'lui.key:keypad-3
  "The KEYPAD-3 key.")
(cl:defconstant keypad-4 'lui.key:keypad-4
  "The KEYPAD-4 key.")
(cl:defconstant keypad-5 'lui.key:keypad-5
  "The KEYPAD-5 key.")
(cl:defconstant keypad-6 'lui.key:keypad-6
  "The KEYPAD-6 key.")
(cl:defconstant keypad-7 'lui.key:keypad-7
  "The KEYPAD-7 key.")
(cl:defconstant keypad-8 'lui.key:keypad-8
  "The KEYPAD-8 key.")
(cl:defconstant keypad-9 'lui.key:keypad-9
  "The KEYPAD-9 key.")
(cl:defconstant keypad-decimal 'lui.key:keypad-decimal
  "The KEYPAD-DECIMAL key.")
(cl:defconstant keypad-divide 'lui.key:keypad-divide
  "The KEYPAD-DIVIDE key.")
(cl:defconstant keypad-multiply 'lui.key:keypad-multiply
  "The KEYPAD-MULTIPLY key.")
(cl:defconstant keypad-subtract 'lui.key:keypad-subtract
  "The KEYPAD-SUBTRACT key.")
(cl:defconstant keypad-add 'lui.key:keypad-add
  "The KEYPAD-ADD key.")
(cl:defconstant keypad-enter 'lui.key:keypad-enter
  "The KEYPAD-ENTER key.")
(cl:defconstant keypad-equal 'lui.key:keypad-equal
  "The KEYPAD-EQUAL key.")
(cl:defconstant shift-left 'lui.key:shift-left
  "The SHIFT-LEFT key command.")
(cl:defconstant shift-right 'lui.key:shift-right
  "The SHIFT-RIGHT key command.")
(cl:defconstant shift-home 'lui.key:shift-home
  "The SHIFT-HOME key command.")
(cl:defconstant shift-end 'lui.key:shift-end
  "The SHIFT-END key command.")
(cl:defconstant word-left 'lui.key:word-left
  "The WORD-LEFT key command.")
(cl:defconstant word-right 'lui.key:word-right
  "The WORD-RIGHT key command.")
(cl:defconstant shift-word-left 'lui.key:shift-word-left
  "The SHIFT-WORD-LEFT key command.")
(cl:defconstant shift-word-right 'lui.key:shift-word-right
  "The SHIFT-WORD-RIGHT key command.")
(cl:defconstant select-all 'lui.key:select-all
  "The SELECT-ALL key command.")
(cl:defconstant copy 'lui.key:copy
  "The COPY key command.")
(cl:defconstant kill-end 'lui.key:kill-end
  "The KILL-END key command.")
(cl:defconstant kill-start 'lui.key:kill-start
  "The KILL-START key command.")
(cl:defconstant kill-word 'lui.key:kill-word
  "The KILL-WORD key command.")
(cl:defconstant kill-word-forward 'lui.key:kill-word-forward
  "The KILL-WORD-FORWARD key command.")
(cl:defconstant yank 'lui.key:yank
  "The YANK key command.")
(cl:defconstant transpose 'lui.key:transpose
  "The TRANSPOSE key command.")

(cl:defconstant backward 'lui.key:backward
  "Reverse keyboard focus traversal.")

(cl:defconstant paste 'lui.key:paste
  "Paste text from the system clipboard.")

(cl:deftype key ()
  "A keyboard key or semantic editor command, independent of the backend."
  '(cl:member
    lui.key:quote lui.key:comma lui.key:minus lui.key:period lui.key:slash
    lui.key:zero lui.key:one lui.key:two lui.key:three lui.key:four
    lui.key:five lui.key:six lui.key:seven lui.key:eight lui.key:nine
    lui.key:semicolon lui.key:equal lui.key:a lui.key:b lui.key:c lui.key:d
    lui.key:e lui.key:f lui.key:g lui.key:h lui.key:i lui.key:j lui.key:k
    lui.key:l lui.key:m lui.key:n lui.key:o lui.key:p lui.key:q lui.key:r
    lui.key:s lui.key:t lui.key:u lui.key:v lui.key:w lui.key:x lui.key:y
    lui.key:z lui.key:left-bracket lui.key:backslash lui.key:right-bracket
    lui.key:backtick lui.key:space lui.key:escape lui.key:enter lui.key:tab
    lui.key:backspace lui.key:insert lui.key:delete lui.key:right
    lui.key:left lui.key:down lui.key:up lui.key:page-up lui.key:page-down
    lui.key:home lui.key:end lui.key:caps-lock lui.key:scroll-lock
    lui.key:num-lock lui.key:print-screen lui.key:pause lui.key:f1 lui.key:f2
    lui.key:f3 lui.key:f4 lui.key:f5 lui.key:f6 lui.key:f7 lui.key:f8
    lui.key:f9 lui.key:f10 lui.key:f11 lui.key:f12 lui.key:left-shift
    lui.key:right-shift lui.key:left-control lui.key:right-control
    lui.key:left-alt lui.key:right-alt lui.key:left-super lui.key:right-super
    lui.key:left-meta lui.key:right-meta lui.key:left-hyper
    lui.key:right-hyper lui.key:kb-menu lui.key:keypad-0 lui.key:keypad-1
    lui.key:keypad-2 lui.key:keypad-3 lui.key:keypad-4 lui.key:keypad-5
    lui.key:keypad-6 lui.key:keypad-7 lui.key:keypad-8 lui.key:keypad-9
    lui.key:keypad-decimal lui.key:keypad-divide lui.key:keypad-multiply
    lui.key:keypad-subtract lui.key:keypad-add lui.key:keypad-enter
    lui.key:keypad-equal lui.key:shift-left lui.key:shift-right
    lui.key:shift-home lui.key:shift-end lui.key:word-left lui.key:word-right
    lui.key:shift-word-left lui.key:shift-word-right lui.key:select-all
    lui.key:copy lui.key:paste lui.key:kill-end lui.key:kill-start
    lui.key:kill-word lui.key:kill-word-forward lui.key:yank lui.key:transpose lui.key:backward))

;; US-layout character tables; text input itself remains Unicode.
(cl:declaim (cl:type cl:simple-string *characters* *shifted-characters*)
            (cl:type (cl:vector key) *character-keys*))
(cl:defparameter *characters*
  "abcdefghijklmnopqrstuvwxyz0123456789',-./;=[\\]` ")
(cl:defparameter *shifted-characters*
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ)!@#$%^&*(\"<_>?:+{|}~ ")
(cl:defparameter *character-keys*
  (cl:make-array 48 :element-type 'key :initial-contents
    '(lui.key:a lui.key:b lui.key:c lui.key:d lui.key:e lui.key:f lui.key:g
      lui.key:h lui.key:i lui.key:j lui.key:k lui.key:l lui.key:m
      lui.key:n lui.key:o lui.key:p lui.key:q lui.key:r lui.key:s
      lui.key:t lui.key:u lui.key:v lui.key:w lui.key:x lui.key:y
      lui.key:z lui.key:zero lui.key:one lui.key:two lui.key:three
      lui.key:four lui.key:five lui.key:six lui.key:seven lui.key:eight
      lui.key:nine lui.key:quote lui.key:comma lui.key:minus
      lui.key:period lui.key:slash lui.key:semicolon lui.key:equal
      lui.key:left-bracket lui.key:backslash lui.key:right-bracket
      lui.key:backtick lui.key:space)))

(%lui.fn:fn (key->char (cl:or cl:null cl:character))
    ((key key))
  "Return the unshifted US-layout character for KEY, or NIL."
  (cl:let ((index (cl:position key *character-keys*)))
    (cl:cond (index (cl:char *characters* index))
             ((cl:eq key lui.key:escape) (cl:code-char 27)))))

(%lui.fn:fn (char->key
             (cl:values (cl:or cl:null key) cl:&optional key key key))
    ((char cl:character))
  "Return a US-layout key and modifier, or NIL for an unmapped character.
Ambiguous control characters also return an alternate key/modifier pair."
  (cl:let ((plain (cl:position char *characters*))
           (shifted (cl:position char *shifted-characters*)))
    (cl:cond
      (plain (cl:values (cl:aref *character-keys* plain)))
      (shifted
       (cl:values (cl:aref *character-keys* shifted) lui.key:left-shift))
      (cl:t
       (cl:case (cl:char-code char)
         ((10 13) (cl:values lui.key:enter))
         (9 (cl:values lui.key:tab))
         (8 (cl:values lui.key:backspace))
         (27 (cl:values lui.key:escape))
         (0 (cl:values lui.key:two lui.key:left-control))
         (28 (cl:values lui.key:backslash lui.key:left-control
                        lui.key:four lui.key:left-control))
         (29 (cl:values lui.key:right-bracket lui.key:left-control
                        lui.key:five lui.key:left-control))
         (30 (cl:values lui.key:six lui.key:left-control))
         (31 (cl:values lui.key:minus lui.key:left-control
                        lui.key:seven lui.key:left-control))
         (cl:otherwise cl:nil))))))
