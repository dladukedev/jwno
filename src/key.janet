(use jw32/_winuser)
(use jw32/_util)

(use ./input)

(import ./const)
(import ./log)


# Forward declaration
(var define-keymap nil)
(var keymap? nil)


(defn ascii [ascii-str]
  (in ascii-str 0))


(defn key [key &opt modifiers]
  (default modifiers [])

  (def normalized-key
    (cond
      (number? key)
      key

      (or (keyword? key) (symbol? key))
      (eval (symbol "VK_" (string/ascii-upper (string/replace-all "-" "_" key))))

      (or (string? key)
          (buffer? key))
      (ascii (string/ascii-upper key))

      true
      (error (string/format "unknown key: %n" key))))

  {:key normalized-key
   :modifiers [;(sort (distinct modifiers))]})


(defmacro- async-key-state-down? [vkey-code]
  ~(< (,GetAsyncKeyState ,vkey-code) 0))


(def MODIFIER-KEYS
  {VK_LSHIFT :lshift
   VK_RSHIFT :rshift
   VK_LCONTROL :lctrl
   VK_RCONTROL :rctrl
   VK_LMENU :lalt
   VK_RMENU :ralt
   VK_LWIN :lwin
   VK_RWIN :rwin})


(defn- set-key-def [keymap key-struct command-or-keymap &opt doc]
  (cond
    (nil? command-or-keymap)
    # Remove a key binding
    (put keymap key-struct nil)

    (keymap? command-or-keymap)
    # It's a sub-keymap
    (let [sub-keymap command-or-keymap]
      # We're now using :current-keymap as a stack to track the real parent
      #(put sub-keymap :parent keymap)
      (put sub-keymap :doc doc)
      (put keymap key-struct sub-keymap))

    true
    # It's a normal command
    (let [command command-or-keymap]
      (put keymap key-struct @{:cmd command :doc doc}))))


(def key-name-to-code
  {"lwin" VK_LWIN
   "rwin" VK_RWIN
   "lalt" VK_LMENU
   "ralt" VK_RMENU
   "lctrl" VK_LCONTROL
   "rctrl" VK_RCONTROL
   "lshift" VK_LSHIFT
   "rshift" VK_RSHIFT

   "backspace" VK_BACK
   "tab" VK_TAB
   "enter" VK_RETURN
   "pause" VK_PAUSE
   "capslock" VK_CAPITAL
   "esc"   VK_ESCAPE
   "space" VK_SPACE
   "pageup" VK_PRIOR
   "pagedown" VK_NEXT
   "end" VK_END
   "home" VK_HOME
   "left" VK_LEFT
   "up" VK_UP
   "right" VK_RIGHT
   "down" VK_DOWN
   "insert" VK_INSERT
   "delete" VK_DELETE
   "app" VK_APPS
   "scrolllock" VK_SCROLL

   "numpad0" VK_NUMPAD0
   "numpad1" VK_NUMPAD1
   "numpad2" VK_NUMPAD2
   "numpad3" VK_NUMPAD3
   "numpad4" VK_NUMPAD4
   "numpad5" VK_NUMPAD5
   "numpad6" VK_NUMPAD6
   "numpad7" VK_NUMPAD7
   "numpad8" VK_NUMPAD8
   "numpad9" VK_NUMPAD9
   "numpad*" VK_MULTIPLY
   "numpad+" VK_ADD
   "numpad-" VK_SUBTRACT
   "numpad." VK_DECIMAL
   "numpad/" VK_DIVIDE

   "a" (ascii "A")
   "b" (ascii "B")
   "c" (ascii "C")
   "d" (ascii "D")
   "e" (ascii "E")
   "f" (ascii "F")
   "g" (ascii "G")
   "h" (ascii "H")
   "i" (ascii "I")
   "j" (ascii "J")
   "k" (ascii "K")
   "l" (ascii "L")
   "m" (ascii "M")
   "n" (ascii "N")
   "o" (ascii "O")
   "p" (ascii "P")
   "q" (ascii "Q")
   "r" (ascii "R")
   "s" (ascii "S")
   "t" (ascii "T")
   "u" (ascii "U")
   "v" (ascii "V")
   "w" (ascii "W")
   "x" (ascii "X")
   "y" (ascii "Y")
   "z" (ascii "Z")
   "0" (ascii "0")
   "1" (ascii "1")
   "2" (ascii "2")
   "3" (ascii "3")
   "4" (ascii "4")
   "5" (ascii "5")
   "6" (ascii "6")
   "7" (ascii "7")
   "8" (ascii "8")
   "9" (ascii "9")

   "f1" VK_F1
   "f2" VK_F2
   "f3" VK_F3
   "f4" VK_F4
   "f5" VK_F5
   "f6" VK_F6
   "f7" VK_F7
   "f8" VK_F8
   "f9" VK_F9
   "f10" VK_F10
   "f11" VK_F11
   "f12" VK_F12
   "f13" VK_F13
   "f14" VK_F14
   "f15" VK_F15
   "f16" VK_F16
   "f17" VK_F17
   "f18" VK_F18
   "f19" VK_F19
   "f20" VK_F20
   "f21" VK_F21
   "f22" VK_F22
   "f23" VK_F23
   "f24" VK_F24

   "," VK_OEM_COMMA
   "." VK_OEM_PERIOD
   "=" VK_OEM_PLUS
   "-" VK_OEM_MINUS
   ";" VK_OEM_1
   "/" VK_OEM_2
   "`" VK_OEM_3
   "[" VK_OEM_4
   "\\" VK_OEM_5
   "]" VK_OEM_6
   "'" VK_OEM_7
  })


(def key-code-to-name
  (let [table-map @{}]
    (eachp [name code] key-name-to-code
      (put table-map code name))
    table-map))


# Only matches lower case key names. Do string/ascii-lower before
# matching against this PEG.
(def key-spec-peg
  (peg/compile
   ~{:win "win"
     :alt "alt"
     :ctrl "ctrl"
     :shift "shift"
     :mod (choice :win :alt :ctrl :shift)
     :mod-with-sides (sequence (set "lr") :mod)
     :mod-capture (replace (capture (choice :mod :mod-with-sides))
                           ,(fn [mod-str] (keyword mod-str)))
     :mod-prefix (sequence :mod-capture :s* (choice "+" "-") :s*)

     :trigger-key  (some :S)
     :trigger-capture (replace (capture :trigger-key)
                               ,(fn [trig-str]
                                  (if-let [code (in key-name-to-code trig-str)]
                                    code
                                    (error (string/format "unknown key name: %n" trig-str)))))

     :combo-capture (group (sequence (group (any :mod-prefix)) :trigger-capture))
     :main (sequence (any (sequence :combo-capture :s+)) :combo-capture :s* -1)
    }))


(defn keymap-parse-key [self key-spec]
  (cond
    (or (string? key-spec)
        (buffer? key-spec))
    (if-let [matched (peg/match key-spec-peg (string/ascii-lower key-spec))]
      (map |(let [[mods key-code] $]
              (key key-code mods))
           matched)
      (error (string/format "failed to parse key spec: %n" key-spec)))

    true
    (error (string/format "unknown key spec: %n" key-spec))))


(defn keymap-define-key [self key-seq command-or-keymap &opt doc]
  (if-not (indexed? key-seq)
    (if (or (string? key-seq)
            (buffer? key-seq))
      (break (keymap-define-key self (keymap-parse-key self key-seq) command-or-keymap doc))
      # A single key spec
      (break (keymap-define-key self [key-seq] command-or-keymap doc))))

  (def cur-key (in key-seq 0))
  (def rest-keys (slice key-seq 1))
  (def cur-def (get self cur-key))

  (if (<= (length rest-keys) 0)
    (set-key-def self cur-key command-or-keymap doc)
    (let [sub-keymap (if (keymap? cur-def)
                       cur-def
                       (define-keymap))]
      (set-key-def self
                   cur-key
                   (keymap-define-key
                     sub-keymap
                     rest-keys
                     command-or-keymap
                     doc))
      self)))


(defn keymap-get-key-binding [self key-struct]
  (in self key-struct))


(defn- pad-string-right [str pad-to]
  (def str-len (length str))
  (def pad-char (in " " 0))
  (if (< str-len pad-to)
    (string str (buffer/new-filled (- pad-to str-len) pad-char))
    str))


(defn- clip-string-right [str clip-to]
  (def str-len (length str))
  (if (> str-len clip-to)
    (let [clip-sign "..."
          clip-sign-len (length clip-sign)]
      (string (string/slice str 0 (- clip-to clip-sign-len)) clip-sign))
    str))


(defn- format-key-struct [key &opt pad-to]
  (default pad-to 0) # No padding by default

  (def trigger (in key :key))
  (def mods (in key :modifiers))
  (if-let [trigger-name (in key-code-to-name trigger)]
    (let [key-str (string/join [;mods (string/ascii-upper trigger-name)] " + ")]
      (pad-string-right key-str pad-to))
    (errorf "unknown key code: %n" trigger)))


(defn- format-key-command [cmd-info &opt clip-to]
  (default clip-to const/KEYMAP-COMMAND-DESC-MAX-LENGTH)

  (def cmd-desc
    (if (keymap? cmd-info)
      # A sub-keymap
      (if-let [km-doc (in cmd-info :doc)]
        km-doc
        "...")
      # An actual command
      (if-let [key-doc (in cmd-info :doc)]
        key-doc
        (string/format "%n" (in cmd-info :cmd)))))
  (clip-string-right cmd-desc clip-to))


(defn keymap-format [self]
  (var max-key-str-len 0)
  (def km-arr @[])
  (eachk k (table/proto-flatten self)
    (when (and (struct? k) (has-key? k :key))
      (def key-str (format-key-struct k 0))
      (def key-str-len (length key-str))
      (if (> key-str-len max-key-str-len)
        (set max-key-str-len key-str-len))
      (array/push km-arr [key-str (in self k)])))

  (sort km-arr |(< (first $0) (first $1)))

  (def cmd-desc @[])
  (each [ks c] km-arr
    (array/push cmd-desc
                (string/format "%s\t\t%s"
                               (pad-string-right ks max-key-str-len)
                               (format-key-command c))))
  (string/join cmd-desc "\n"))


(defn prepare-for-marshalling [x &opt fn-reverse-lookup seen]
  (default fn-reverse-lookup @{})
  (default seen @{})

  (cond
    (or (function? x)
        (cfunction? x))
    (unless (has-key? fn-reverse-lookup x)
      (put fn-reverse-lookup x (gensym)))

    (and (indexed? x)
         (not (has-key? seen x)))
    (do
      (put seen x true)
      (each xx x
        (prepare-for-marshalling xx fn-reverse-lookup seen)))

    (and (or (struct? x)
             (table? x))
         (not (has-key? seen x)))
    (eachp [k v] x
      (prepare-for-marshalling k fn-reverse-lookup seen)
      (prepare-for-marshalling v fn-reverse-lookup seen)))

  fn-reverse-lookup)


(defn keymap-prepare-for-marshalling [self &opt fn-reverse-lookup]
  (prepare-for-marshalling self))


(def- keymap-proto
  @{:define-key keymap-define-key
    :parse-key keymap-parse-key
    :get-key-binding keymap-get-key-binding
    :format keymap-format
    :prepare-for-marshalling keymap-prepare-for-marshalling})


(varfn define-keymap [&opt proto]
  (default proto keymap-proto)
  (table/setproto (table/new 0) proto))


(varfn keymap? [x]
  (and (table? x)
       (not (has-key? x :cmd))))


(defn key-manager-new-keymap [self &opt proto]
  (define-keymap proto))


(defn key-manager-set-keymap [self keymap]
  (def fn-reverse-lookup (:prepare-for-marshalling keymap))
  (def fn-lookup (invert fn-reverse-lookup))

  (put self :keymap-fn-reverse-lookup fn-reverse-lookup)
  (put self :keymap-fn-lookup fn-lookup)

  (def sym-lookup @{})
  (each k (keys fn-lookup)
    (put sym-lookup k k))

  (put keymap :bottom-of-stack true)
  (def keymap-ptr (alloc-and-marshal keymap fn-reverse-lookup))
  (def buf-ptr (alloc-and-marshal [keymap-ptr sym-lookup]))
  (:set-keymap (in self :ui-manager) buf-ptr))


(defn key-manager-get-key-code [self key-name]
  (if-let [kc (in key-name-to-code key-name)]
    kc
    (error (string/format "unknown key: %n" key-name))))


(defn key-manager-set-key-mode [self new-mode]
  (:set-key-mode (in self :ui-manager) new-mode))


(defn key-manager-unmarshal-keymap [self buf-ptr]
  (def fn-lookup (in self :keymap-fn-lookup))
  (unmarshal-and-free buf-ptr fn-lookup))


(def- key-manager-proto
  @{:new-keymap key-manager-new-keymap
    :set-keymap key-manager-set-keymap
    :set-key-mode key-manager-set-key-mode
    :get-key-code key-manager-get-key-code
    :unmarshal-keymap key-manager-unmarshal-keymap})


(defn key-manager [ui-man hook-man]
  (def key-man-obj
    (table/setproto
     @{:ui-manager ui-man
       :hook-manager hook-man}
     key-manager-proto))

  (:add-hook hook-man :keymap-switched
     (fn [keymap]
       (:show-tooltip ui-man :keymap (:format keymap))))
  (:add-hook hook-man :keymap-reset
     (fn [_keymap]
       (:hide-tooltip ui-man :keymap)))

  (:add-hook hook-man :keymap-pushed
     (fn [keymap]
       (:show-tooltip ui-man :keymap (:format keymap))))
  (:add-hook hook-man :keymap-popped
     (fn [keymap]
       (if (in keymap :bottom-of-stack)
         (:hide-tooltip ui-man :keymap)
         (:show-tooltip ui-man :keymap (:format keymap)))))

  key-man-obj)


(defn keyboard-hook-handler-set-keymap [self buf-ptr]
  (def [keymap-ptr sym-lookup] (unmarshal-and-free buf-ptr))
  (def keymap (unmarshal-and-free keymap-ptr sym-lookup))

  (def to-set
    (if (nil? keymap)
      (define-keymap)
      keymap))

  (put self :keymap-sym-lookup sym-lookup)
  (put self :current-keymap @[to-set])
  (put self :keymap-stack @[]))


(defn keyboard-hook-handler-push-keymap [self keymap]
  (def new-keymap 
    (if (nil? keymap)
      (define-keymap)
      keymap))
  # XXX: Always reset the current keymap at the same time,
  # Or a sub-keymap may still be active when we pop the stack.
  (array/push (in self :keymap-stack)
              (first (in self :current-keymap)))
  (put self :current-keymap @[new-keymap]))


(defn keyboard-hook-handler-pop-keymap [self]
  (def old-keymap (first (in self :current-keymap)))
  (def new-keymap
    (if-let [stack-top (array/pop (in self :keymap-stack))]
      stack-top
      (define-keymap)))
  (put self :current-keymap @[new-keymap])
  old-keymap)


(defn keyboard-hook-handler-translate-key [self hook-struct]
  (def extra-info (in hook-struct :dwExtraInfo))
  (when (test-kei-flag KEI-FLAG-REMAPPED extra-info)
    # Already remapped
    (break nil))

  (when-let [binding (:get-key-binding (last (in self :current-keymap))
                                       (key (hook-struct :vkCode)))]
    (def {:cmd cmd} binding)
    (match cmd
      [:map-to new-key]
      new-key
      
      _
      nil)))


(defn keyboard-hook-handler-get-modifier-states [self hook-struct]
  (def current-kc (in hook-struct :vkCode))
  (def states @{})
  (each kc (keys MODIFIER-KEYS)
    (when (and (not= kc current-kc) # Special case when only modifiers are pressed
               (async-key-state-down? kc))
      (put states (in MODIFIER-KEYS kc) true)))
  states)


(defn keyboard-hook-handler-find-binding [self hook-struct mod-keys]
  (def mod-combinations-to-check @[mod-keys])
  (each [mod lmod rmod] [[:shift :lshift :rshift]
                         [:ctrl :lctrl :rctrl]
                         [:alt :lalt :ralt]
                         [:win :lwin :rwin]]
    (each state (slice mod-combinations-to-check)
      (when (or (in state lmod)
                (in state rmod))
        (def comb (table/clone state))
        (put comb lmod nil)
        (put comb rmod nil)
        (put comb mod true)
        (array/push mod-combinations-to-check comb))))

  (log/debug "mod-combinations-to-check = %n" mod-combinations-to-check)

  (var binding nil)
  (each comb mod-combinations-to-check
    (def key-struct (key (hook-struct :vkCode) (keys comb)))
    (log/debug "Finding binding for key: %n" key-struct)
    (if-let [found (:get-key-binding (last (in self :current-keymap)) key-struct)]
      (match found
        [:map-to _]
        # handled in translate-key
        nil

        _
        (do
          (set binding found)
          (break)))))
  binding)


(defn keyboard-hook-handler-reset-keymap [self]
  (log/debug "Resetting keymap")
  (def cur-keymap (last (in self :current-keymap)))
  (def root-keymap (first (in self :current-keymap)))
  (put self :current-keymap @[root-keymap])
  (not= root-keymap cur-keymap))


(defn keyboard-hook-handler-marshal-keymap [self data]
  (def sym-lookup (in self :keymap-sym-lookup))
  (alloc-and-marshal data sym-lookup))


(defn keyboard-hook-handler-handle-binding [self hook-struct binding]
  (def key-up (hook-struct :flags.up))

  (when (keymap? binding)
    # It's a sub-keymap, activate it only on key-up
    (if key-up
      (do
        (array/push (in self :current-keymap) binding)
        (break [:key/switch-keymap (:marshal-keymap self binding)]))
      (break nil)))

  (def {:cmd cmd} binding)

  (match cmd
    [:push-keymap keymap]
    (when key-up
      (keyboard-hook-handler-push-keymap self keymap)
      [:key/push-keymap (:marshal-keymap self (last (in self :current-keymap)))])

    :pop-keymap
    (when key-up
      (keyboard-hook-handler-pop-keymap self)
      [:key/pop-keymap (:marshal-keymap self (last (in self :current-keymap)))])

    _
    # It's a normal command, only fire on key-down, and
    # try to reset to root keymap when key-up
    (if key-up
      (when (keyboard-hook-handler-reset-keymap self)
        [:key/reset-keymap (:marshal-keymap self (last (in self :current-keymap)))])
      [:key/command (:marshal-keymap self binding)])))


(defn keyboard-hook-handler-handle-unbound [self hook-struct]
  (def key-up (hook-struct :flags.up))
  # Reset the keymap on key-up, even for key combos we don't recognize.
  # We don't want modifier keys to reset the keymap, since this
  # will prevent the next key combo from having different modifiers.
  (when (and key-up
             (not (in MODIFIER-KEYS (in hook-struct :vkCode))))
    (when (keyboard-hook-handler-reset-keymap self)
      [:key/reset-keymap (:marshal-keymap self (last (in self :current-keymap)))])))


(defn keyboard-hook-handler-set-key-mode [self new-mode]
  (unless (find |(= $ new-mode) [:command :raw])
    (errorf "unknown key mode: %n" new-mode))
  (log/debug "Pending key mode: %n" new-mode)
  (put (in self :key-mode) :pending new-mode))


(defn keyboard-hook-handler-check-key-mode [self hook-struct]
  (def key-up (hook-struct :flags.up))
  (def key-mode (in self :key-mode))
  (def pending-mode (in key-mode :pending))
  (def current-mode (in key-mode :current))

  (when (and (not key-up)
             (not (nil? pending-mode)))
    (log/debug "Update key mode: %n -> %n" current-mode pending-mode)
    (put key-mode :pending nil)
    (put key-mode :current pending-mode))

  (def ret (in key-mode :current))
  (log/debug "Actual key mode: %n" ret)
  ret)


(defn keyboard-hook-handler-handle-raw-key [self hook-struct mod-states]
  (def key-up (hook-struct :flags.up))
  (def key-code (hook-struct :vkCode))
  # All modifier keys needs to go through, or the low-level modifier
  # states tracked by the OS (i.e. the values returned by GetAsyncKeyState)
  # would be wrong.
  (def pass-through? (in MODIFIER-KEYS key-code))
  (if key-up
    [pass-through? nil]
    (let [key-struct (key key-code (keys mod-states))]
      [pass-through? [:key/raw key-struct]])))


(def- keyboard-hook-handler-proto
  @{:set-keymap keyboard-hook-handler-set-keymap
    :push-keymap keyboard-hook-handler-push-keymap
    :pop-keymap keyboard-hook-handler-pop-keymap
    :translate-key keyboard-hook-handler-translate-key
    :find-binding keyboard-hook-handler-find-binding
    :get-modifier-states keyboard-hook-handler-get-modifier-states
    :reset-keymap keyboard-hook-handler-reset-keymap
    :marshal-keymap keyboard-hook-handler-marshal-keymap
    :handle-binding keyboard-hook-handler-handle-binding
    :handle-unbound keyboard-hook-handler-handle-unbound
    :set-key-mode keyboard-hook-handler-set-key-mode
    :check-key-mode keyboard-hook-handler-check-key-mode
    :handle-raw-key keyboard-hook-handler-handle-raw-key})


(defn keyboard-hook-handler [keymap]
  (table/setproto
   @{:keymap-stack @[]
     # if a sub-keymap is defined in a prototype, and we simply follow
     # the child -> parent link in keymaps, the current keymap will be
     # reset to the prototype instead of the real parent, after we
     # triggered that sub-keymap. This array is used as another stack
     # to record how we reached the current keymap, so that we can get
     # back to its real parent.
     :current-keymap @[keymap]
     :key-mode @{
       # When switching key modes, pending key-up events should pass
       # through in the previous mode, so we don't actually change the
       # mode before the first key-down event is seen. We need two flags
       # to track this mode-switching process.          
       :pending nil      # The next mode to switch to
       :current :command # The current mode
      }}
   keyboard-hook-handler-proto))
