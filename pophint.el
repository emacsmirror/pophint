;;; pophint.el --- Provide navigation using pop-up tips, like Firefox's Vimperator Hint Mode

;; Copyright (C) 2013  Hiroaki Otsu

;; Author: Hiroaki Otsu <ootsuhiroaki@gmail.com>
;; Keywords: popup
;; URL: https://github.com/aki2o/emacs-pophint
;; Version: 1.4.0
;; Package-Requires: ((log4e "0.4.0") (yaxception "1.0.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This extension provides navigation like the Vimperator Hint Mode of Firefox.
;; The interface has the following flow.
;;  1. pop-up tip about the matched point for some action which user want.
;;  2. do some action for the user selecting.
;;
;; For detail, see <https://github.com/aki2o/emacs-pophint/blob/master/README.md>
;; For configuration, see Configuration section in <https://github.com/aki2o/emacs-pophint/wiki>
;;
;; Enjoy!!!

;;; Code:

(require 'cl-lib)
(require 'rx)
(require 'mode-local)
(require 'yaxception)
(require 'log4e)
(require 'pos-tip nil t)


(defgroup pophint nil
  "Pop-up the hint tip of candidates for doing something"
  :group 'popup
  :prefix "pophint:")

(defcustom pophint:popup-chars "hjklyuiopnm"
  "Characters for pop-up hint."
  :type 'string
  :group 'pophint)

(defcustom pophint:select-source-chars "123456789"
  "Characters for selecting source."
  :type 'string
  :group 'pophint)

(defcustom pophint:select-source-method 'use-source-char
  "Method to select source.

This value is one of the following symbols.
 - use-source-char
     Push the key bound to each of sources from `pophint:select-source-chars'
     without pushing `pophint:switch-source-char'.
 - use-popup-char
     Push the key bound to each of sources from `pophint:popup-chars'
     after pushing `pophint:switch-source-char'.
 - nil
     Push `pophint:switch-source-char' only."
  :type '(choice (const use-source-char)
                 (const use-popup-char)
                 (const nil))
  :group 'pophint)

(defcustom pophint:switch-source-char "s"
  "Character for switching source used to pop-up."
  :type 'string
  :group 'pophint)

(defcustom pophint:switch-source-reverse-char "S"
  "Character for switching source used to pop-up in reverse."
  :type 'string
  :group 'pophint)

(defcustom pophint:switch-source-delay 0.5
  "Second for delay to switch source used to pop-up.

If nil, it means not delay."
  :type 'number
  :group 'pophint)

(defcustom pophint:switch-source-selectors nil
  "List of dedicated selector for source.

Example:
 \\='((\"Quoted\"   . \"q\")
   (\"Url/Path\" . \"u\"))
"
  :type '(repeat (cons string string))
  :group 'pophint)

(defcustom pophint:switch-direction-char "d"
  "Character for switching direction of pop-up."
  :type 'string
  :group 'pophint)

(defcustom pophint:switch-direction-reverse-char "D"
  "Character for switching direction of pop-up in reverse."
  :type 'string
  :group 'pophint)

(defcustom pophint:switch-window-char "w"
  "Character for switching window of pop-up."
  :type 'string
  :group 'pophint)

(defcustom pophint:popup-max-tips 200
  "Maximum counts of pop-up hint.

If nil, it means limitless."
  :type 'integer
  :group 'pophint)

(defcustom pophint:default-require-length 3
  "Default minimum length of matched text for pop-up."
  :type 'integer
  :group 'pophint)

(defcustom pophint:switch-direction-p t
  "Whether switch direction of pop-up."
  :type 'boolean
  :group 'pophint)

(defcustom pophint:do-allwindow-p nil
  "Whether do pop-up at all windows."
  :type 'boolean
  :group 'pophint)

(defcustom pophint:use-pos-tip nil
  "Whether use pos-tip.el to show prompt."
  :type 'boolean
  :group 'pophint)

(defcustom pophint:inch-forward-length 3
  "Size of chars to make next hint by `'"
  :type 'integer
  :group 'pophint)
(make-obsolete 'pophint-config:inch-length 'pophint:inch-forward-length "1.1.0")

(defface pophint:tip-face
  '((t (:background "khaki1" :foreground "black" :bold t)))
  "Face for the pop-up hint."
  :group 'pophint)

(defface pophint:match-face
  '((t (:background "steel blue" :foreground "white")))
  "Face for matched hint text."
  :group 'pophint)

(defface pophint:pos-tip-face
  '((((class color) (background dark))  (:background "ivory" :foreground "black"))
    (((class color) (background light)) (:background "gray10" :foreground "white"))
    (t                                  (:background "ivory" :foreground "black")))
  "Face for the tip of pos-tip.el"
  :group 'pophint)

(defface pophint:prompt-bind-part-face
  '((t (:inherit font-lock-keyword-face :bold t)))
  "Face for the part of bound key in prompt."
  :group 'pophint)

(defface pophint:prompt-active-part-face
  '((t (:bold t)))
  "Face for the part of active source/direction in prompt."
  :group 'pophint)

(defvar pophint:sources nil
  "Buffer local sources for pop-up hint tip flexibly.")
(make-variable-buffer-local 'pophint:sources)

(defvar pophint:global-sources nil
  "Global sources for pop-up hint tip flexibly")

(defvar pophint:dedicated-sources nil
  "Dedicated sources for pop-up hint tip in particular situation.")

(cl-defstruct pophint:hint window popup overlay (startpt 0) (endpt 0) (value ""))
(cl-defstruct pophint:action name action)


(log4e:deflogger "pophint" "%t [%l] %m" "%H:%M:%S" '((fatal . "fatal")
                                                     (error . "error")
                                                     (warn  . "warn")
                                                     (info  . "info")
                                                     (debug . "debug")
                                                     (trace . "trace")))
(pophint--log-set-level 'trace)


(cl-defstruct pophint--condition
  source sources action action-name direction window allwindow use-pos-tip
  not-highlight not-switch-direction not-switch-window not-switch-source
  tip-face)

(defvar pophint--action-hash (make-hash-table :test 'equal))
(defvar pophint--enable-allwindow-p nil)
(defvar pophint--disable-allwindow-p nil)

(defvar pophint--last-hints nil)
(defvar pophint--last-condition nil)
(defvar pophint--last-context-condition-hash (make-hash-table :test 'equal))

(defvar pophint--current-context nil)
(defvar pophint--current-window nil)
(defvar pophint--current-point nil)

(defvar pophint--resumed-input-method nil)

(defvar pophint--non-alphabet-chars "!\"#$%&'()-=^~\\|@`[{;+:*]},<.>/?_")

(defvar pophint--default-search-regexp
  (let ((min-len pophint:default-require-length))
    (rx-to-string `(and point (or
                               ;; 連続する空白
                               (and (group-n 1 (>= ,min-len blank)))
                               ;; 連続する記号
                               (and (* blank)
                                    (group-n 1 (>= ,min-len (any ,pophint--non-alphabet-chars))))
                               ;; 連続する英数字
                               (and (* (any ,pophint--non-alphabet-chars blank))
                                    (group-n 1 (>= ,min-len (any "a-zA-Z0-9"))))
                               ;; ;; 単語
                               ;; (and (** 1 ,(1- min-len) (not word))
                               ;;      (group-n 1 (>= ,min-len word)))
                               ;; ;; 単語区切りまでの何か
                               ;; (and (group-n 1 (** ,min-len ,min-len not-newline) (*? not-newline))
                               ;;      word-boundary)
                               ;; 改行
                               (and (* (any ,pophint--non-alphabet-chars blank))
                               ;;(and (*? not-newline)
                                    (group-n 1 "\n"))
                               )))))

(defun pophint--default-search ()
  (if (re-search-forward pophint--default-search-regexp nil t)
      `(:startpt ,(match-beginning 1) :endpt ,(match-end 1) :value ,(match-string-no-properties 1))
    (let ((startpt (point))
          (endpt (progn (forward-word) (point))))
      (when (> endpt startpt)
        `(:startpt ,startpt :endpt ,endpt :value ,(buffer-substring-no-properties startpt endpt))))))

(defvar pophint--default-source '((shown . "Default")
                                  (requires . 1)
                                  (method . pophint--default-search)
                                  (highlight . nil)))

(defvar pophint--default-action (lambda (hint)
                                  (let ((wnd (pophint:hint-window hint)))
                                    (push-mark)
                                    (when (and (windowp wnd)
                                               (window-live-p wnd)
                                               (not (eq (selected-window) wnd)))
                                      (select-window wnd))
                                    (goto-char (pophint:hint-startpt hint)))))

(defvar pophint--default-action-name "Go/SrcAct")

(defvar pophint--next-window-source
  '((shown . "Wnd")
    (requires . 0)
    (highlight . nil)
    (tip-face-attr . (:height 2.0))
    (init . (lambda ()
              (setq pophint--current-point (point))))
    (method . (lambda ()
                (cond ((eq pophint--current-window (selected-window))
                       (setq pophint--current-window nil))
                      ((and (window-minibuffer-p (selected-window))
                            (not (minibuffer-window-active-p (selected-window))))
                       (setq pophint--current-window nil))
                      (t
                       (setq pophint--current-window (selected-window))
                       (when (= (buffer-size) 0) (insert " "))
                       (let* ((startpt (min (save-excursion
                                              (goto-char (window-start))
                                              (forward-line 1)
                                              (while (and (< (- (pos-eol) (point)) (window-hscroll))
                                                          (< (point) (point-max)))
                                                (forward-line 1))
                                              (+ (point) (window-hscroll)))
                                            (1- (point-max))))
                              (endpt (max pophint--current-point (1+ startpt))))
                         `(:startpt ,startpt :endpt ,endpt :value ""))))))
    (action . hint)))


;;;;;;;;;;;;;
;; Utility

(cl-defmacro pophint--aif (test then &rest else)
  (declare (indent 2))
  `(let ((it ,test)) (if it ,then ,@else)))

(cl-defmacro pophint--awhen (test &rest body)
  (declare (indent 1))
  `(let ((it ,test)) (when it ,@body)))

(cl-defun pophint--show-message (msg &rest args)
  (apply 'message (concat "[PopHint] " msg) args)
  nil)

(defsubst pophint--current-not-highlight-p (cond)
  (or (pophint--condition-not-highlight cond)
      (pophint--awhen (assq 'highlight (pophint--condition-source cond))
        (not (cdr-safe it)))))

(defsubst pophint--current-not-switch-source-p (cond)
  (or (pophint--condition-not-switch-source cond)
      (< (length (pophint--condition-sources cond)) 2)))

(defsubst pophint--current-action (cond)
  (or (pophint--condition-action cond)
      (assoc-default 'action (pophint--condition-source cond))
      pophint--default-action))

(defvar pophint--stocked-overlays nil)

(defsubst pophint--make-overlay (start end)
  (or (pophint--awhen (pop pophint--stocked-overlays)
        (move-overlay it start end (current-buffer)))
      (make-overlay start end (current-buffer))))

(defsubst pophint--stock-overlay (ov)
  (overlay-put ov 'text nil)
  (overlay-put ov 'window nil)
  (overlay-put ov 'display nil)
  (overlay-put ov 'after-string nil)
  (overlay-put ov 'face nil)
  (overlay-put ov 'priority nil)
  (push ov pophint--stocked-overlays))

(defsubst pophint--delete (hint)
  (when (pophint:hint-p hint)
    (let* ((tip (pophint:hint-popup hint))
           (ov (pophint:hint-overlay hint)))
      (when ov
        ;; (delete-overlay ov)
        (pophint--stock-overlay ov)
        (setf (pophint:hint-overlay hint) nil))
      (when tip
        ;; (delete-overlay tip)
        (pophint--stock-overlay tip)
        (setf (pophint:hint-popup hint) nil))
      nil)))

(defun pophint--deletes (hints)
  (pophint--trace "start delete hints. hints:[%s]" (length hints))
  (dolist (hint hints)
    (pophint--delete hint))
  nil)

(defun pophint--compile-to-function (something)
  (cond ((functionp something)
         something)
        ((and (symbolp something)
              (boundp something))
         (symbol-value something))
        ((listp something)
         something)
        (t
         nil)))

(defsubst pophint--compile-source (source)
  (cond ((symbolp source)
         (symbol-value source))
        ((listp source)
         source)))

(defun pophint--compile-sources (sources)
  (cl-loop for s in sources
        collect (pophint--compile-source s)))

(make-face 'pophint--tip-face-temp)
(defsubst pophint--update-tip-face (face-attr)
  (if (not face-attr)
      'pophint:tip-face
    (copy-face 'pophint:tip-face 'pophint--tip-face-temp)
    (apply 'set-face-attribute 'pophint--tip-face-temp nil face-attr)
    'pophint--tip-face-temp))

(defsubst pophint--make-index-char-string (idx char-list)
  (if (or (not (stringp char-list))
          (string= char-list ""))
      ""
    (let* ((basei (length char-list)))
      (cl-loop with ret = ""
            with n = idx
            for i = (/ n basei)
            for r = (- n (* basei i))
            until (= i 0)
            do (setq n i)
            do (setq ret (concat (substring char-list r (+ r 1)) ret))
            finally return (concat (substring char-list r (+ r 1)) ret)))))

(defsubst pophint--make-unique-char-strings (count char-list &optional not-upcase exclude-strings)
  (cl-loop with reth = (make-hash-table :test 'equal)
        with idx = 0
        with currcount = 0
        while (< currcount count)
        for currstr = (pophint--make-index-char-string idx char-list)
        for currstr = (if not-upcase currstr (upcase currstr))
        do (cl-incf idx)
        do (when (not (member currstr exclude-strings))
             (puthash currstr t reth)
             (cl-incf currcount))
        do (let ((chkvalue (substring currstr 0 (- (length currstr) 1))))
             (when (gethash chkvalue reth)
               (remhash chkvalue reth)
               (cl-decf currcount)))
        finally return (cl-loop for k being the hash-keys in reth collect k)))
      
(defun pophint--set-selector-sources (sources)
  (cl-loop with char-list = (cl-case pophint:select-source-method
                           (use-popup-char  pophint:popup-chars)
                           (use-source-char pophint:select-source-chars)
                           (t               nil))
        with excludes = (cl-loop for src in sources
                              for s = (assoc-default (assoc-default 'shown src) pophint:switch-source-selectors)
                              if s
                              append (cl-loop with idx = (length s)
                                           while (> idx 0)
                                           collect (substring s 0 idx)
                                           do (cl-decf idx)))
        with selectors = (when char-list
                           (pophint--make-unique-char-strings (length sources) char-list t excludes))
        for src in sources
        for selector = (or (assoc-default (assoc-default 'shown src) pophint:switch-source-selectors)
                           (when selectors (pop selectors)))
        do (pophint--awhen (assq 'selector src)
             (setq src (delq it src)))
        if selector
        do (add-to-list 'src `(selector . ,selector) t)
        collect src))

(defun pophint--get-available-sources (window)
  (let* ((sources (with-current-buffer (or (and (windowp window)
                                                (window-live-p window)
                                                (window-buffer window))
                                           (current-buffer))
                    (pophint--compile-sources pophint:sources))))
    (cl-loop for src in (pophint--compile-sources pophint:global-sources)
          do (add-to-list 'sources src t))
    ;; (add-to-list 'sources pophint--default-source t)
    sources))

(cl-defun pophint--set-last-condition (condition &key context)
  (pophint--debug "set last condition of %s\n%s" context condition)
  (setq pophint--last-condition condition)
  (when context
    (puthash context condition pophint--last-context-condition-hash)))

(defun pophint--get-last-condition-with-context (context)
  (gethash context pophint--last-context-condition-hash))

(cl-defmacro pophint--with-no-last-condition (&rest body)
  (declare (indent 0))
  `(let ((pophint--last-condition nil)
         (pophint--last-context-condition-hash (make-hash-table :test 'equal)))
     ,@body))

(defvar pophint--selected-action nil)
(defvar pophint--selected-hint nil)

(defun pophint--do-action (hint action)
  (when (pophint:hint-p hint)
    (let* ((tip (pophint:hint-popup hint))
           (selected (pophint:hint-value hint)))
      (pophint--debug "start action. selected:[%s] action:%s" selected action)
      (pophint--delete hint)
      (cond ((eq action 'value)
             (pophint:hint-value hint))
            ((eq action 'point)
             (pophint:hint-startpt hint))
            ((eq action 'hint)
             hint)
            ((functionp action)
             (setq pophint--selected-action action)
             (setq pophint--selected-hint hint)
             (run-at-time 0 nil (lambda ()
                                  (let ((action pophint--selected-action)
                                        (hint pophint--selected-hint))
                                    (setq pophint--selected-action nil)
                                    (setq pophint--selected-hint nil)
                                    (funcall action hint)))))
            (t
             (error "Unsupported action"))))))

(cl-defmacro pophint--maybe-kind-mode-buffer-p (buf &rest modes)
  (declare (indent 0))
  `(let ((buf-mode (buffer-local-value 'major-mode ,buf)))
     (when (or (memq buf-mode (list ,@modes))
               (memq (get-mode-local-parent buf-mode) (list ,@modes)))
       t)))


;;;;;;;;;;;;;;;;;;;;;
;; For Interactive

(defun pophint--menu-read-key-sequence (prompt use-pos-tip &optional timeout)
  (pophint--trace "start menu read key sequence. prompt[%s] use-pos-tip[%s] timeout[%s]"
                  prompt use-pos-tip timeout)
  ;; Coding by referring to popup-menu-read-key-sequence
  (catch 'timeout
    (let ((timer (and timeout
                      (run-with-timer timeout nil
                                      (lambda ()
                                        (if (zerop (length (this-command-keys)))
                                            (throw 'timeout nil))))))
          (old-global-map (current-global-map))
          (temp-global-map (make-sparse-keymap))
          (overriding-terminal-local-map (make-sparse-keymap)))
      (substitute-key-definition 'keyboard-quit 'keyboard-quit temp-global-map old-global-map)
      (define-key temp-global-map [menu-bar] (lookup-key old-global-map [menu-bar]))
      (define-key temp-global-map [tool-bar] (lookup-key old-global-map [tool-bar]))
      (when (current-local-map)
        (define-key overriding-terminal-local-map [menu-bar] (lookup-key (current-local-map) [menu-bar])))
      (yaxception:$
        (yaxception:try
          (use-global-map temp-global-map)
          (clear-this-command-keys)
          (if (and use-pos-tip
                   window-system
                   (featurep 'pos-tip))
              (progn (pophint--pos-tip-show prompt)
                     (read-key-sequence nil))
            (with-temp-message prompt
              (read-key-sequence nil))))
        (yaxception:finally
          (use-global-map old-global-map)
          (when timer (cancel-timer timer))
          (when (and use-pos-tip
                     (featurep 'pos-tip))
            (pos-tip-hide)))))))

(cl-defun pophint--make-source-selection-prompt (sources &key
                                                       (delimiter "|")
                                                       highlight-source)
  (let ((hsrcnm (or (assoc-default 'shown highlight-source)
                    "")))
    (mapconcat (lambda (src)
                 (let* ((srcnm (or (assoc-default 'shown src) "*None*"))
                        (selector (assoc-default 'selector src)))
                   (concat (if selector
                               (concat (propertize selector 'face 'pophint:prompt-bind-part-face) ":")
                             "")
                           (if (string= hsrcnm srcnm)
                               (propertize srcnm 'face 'pophint:prompt-active-part-face)
                             srcnm))))
               sources
               delimiter)))

(defun pophint--make-prompt (cond hint-count)
  (let* ((source (pophint--condition-source cond))
         (sources (pophint--condition-sources cond))
         (actdesc (pophint--condition-action-name cond))
         (direction (pophint--condition-direction cond))
         (not-switch-direction (pophint--condition-not-switch-direction cond))
         (not-switch-window (pophint--condition-not-switch-window cond))
         (not-switch-source (pophint--current-not-switch-source-p cond))
         (swsrctext (cond ((not not-switch-source)
                           (format "%s%s:SwSrc(%s) "
                                   (propertize pophint:switch-source-char 'face 'pophint:prompt-bind-part-face)
                                   (if pophint:switch-source-reverse-char
                                       (concat "/"
                                               (propertize pophint:switch-source-reverse-char 'face 'pophint:prompt-bind-part-face))
                                     "")
                                   (pophint--make-source-selection-prompt sources
                                                                          :highlight-source source)))
                          ((cl-loop for s in (append (list source) sources)
                                 always (assoc-default 'dedicated s))
                           "")
                          (t
                           (format "Src[%s] " (or (assoc-default 'shown source)
                                                  "*None*")))))
         (swdirtext (cond ((not not-switch-direction)
                           (format "%s%s:SwDrct(%s) "
                                   (propertize pophint:switch-direction-char 'face 'pophint:prompt-bind-part-face)
                                   (if pophint:switch-direction-reverse-char
                                       (concat "/"
                                               (propertize pophint:switch-direction-reverse-char 'face 'pophint:prompt-bind-part-face))
                                     "")
                                   (mapconcat (lambda (d)
                                                (let* ((s (format "%s" d)))
                                                  (if (eq d direction)
                                                      (propertize s 'face 'pophint:prompt-active-part-face)
                                                    s)))
                                              '(around forward backward)
                                              "|")))
                          (t
                           "")))
         (swwndtext (cond ((not not-switch-window)
                           (format "%s:SwWnd "
                                   (propertize pophint:switch-window-char 'face 'pophint:prompt-bind-part-face)))
                          (t
                           ""))))
    (format "Select ch. Hints[%s] Act[%s] %s%s%s" hint-count actdesc swsrctext swdirtext swwndtext)))

(defun pophint--make-prompt-interactively ()
  (let* ((count 1)
         (acttext (cl-loop with ret = ""
                        for k being the hash-keys in pophint--action-hash using (hash-values act)
                        for desc = (pophint:action-name act)
                        do (cl-incf count)
                        do (setq ret (concat ret
                                             (format "%s:%s "
                                                     (propertize k 'face 'pophint:prompt-bind-part-face)
                                                     desc)))
                        finally return ret))
         (defact (propertize "<RET>" 'face 'pophint:prompt-bind-part-face)))
    (format "Select ch. Actions[%s] %s:Default %s" count defact acttext)))


;;;;;;;;;;;;;;;;;
;; Pop-up Hint

(cl-defun pophint--let-user-select (cond &key context)
  (when (not (pophint--condition-source cond))
    (let ((sources (pophint--condition-sources cond)))
      (setf (pophint--condition-source cond)
            (or (and (> (length sources) 0) (nth 0 sources))
                pophint--default-source))))
  (let ((pophint--current-context (or context pophint--current-context this-command))
        (hints (pophint--get-hints cond))
        (tip-face-attr (assoc-default 'tip-face-attr (pophint--condition-source cond))))
    (pophint--set-last-condition cond :context pophint--current-context)
    (pophint--show-hint-tips hints
                             (pophint--current-not-highlight-p cond)
                             (or (pophint--condition-tip-face cond)
                                 (pophint--update-tip-face tip-face-attr)))
    (pophint--event-loop hints cond)))

(defsubst pophint--get-max-tips (source direction)
  (let ((ret (or (assoc-default 'limit source)
                 pophint:popup-max-tips)))
    (when (and (eq direction 'around)
               ret)
      (setq ret (/ ret 2)))
    ret))

(defsubst pophint--get-hint-regexp (source)
  (let ((re (or (assoc-default 'regexp source)
                pophint--default-search-regexp)))
    (cond ((stringp re)   re)
          ((boundp re)    (symbol-value re))
          ((functionp re) (funcall re))
          (t              (eval re)))))

(defsubst pophint--get-search-function (srcmtd direction)
  (cond ((functionp srcmtd)
         srcmtd)
        ((and (listp srcmtd)
              (> (length srcmtd) 0))
         (nth 0 srcmtd))))

(defsubst pophint--valid-location-p (lastpt startpt endpt)
  (when (and startpt endpt
             (> startpt lastpt)
             (> endpt startpt))
    t))

(defsubst pophint--hintable-location-p (direction currpt startpt endpt)
  (when (and (not (ignore-errors (invisible-p startpt)))
             (not (ignore-errors (invisible-p (1- endpt))))
             (cl-case direction
               (around   t)
               (forward  (>= startpt currpt))
               (backward (< endpt currpt))))
    t))

(cl-defun pophint--get-hints (cond)
  (let* ((source (pophint--condition-source cond))
         (direction (pophint--condition-direction cond))
         (window (pophint--condition-window cond))
         (allwindow (pophint--condition-allwindow cond))
         (wndchker (pophint--compile-to-function (assoc-default 'activebufferp source)))
         (init (pophint--compile-to-function (assoc-default 'init source)))
         (requires (or (assoc-default 'requires source)
                       pophint:default-require-length))
         (re (pophint--get-hint-regexp source))
         (srcmtd (pophint--compile-to-function (assoc-default 'method source)))
         (srchfnc (pophint--get-search-function srcmtd direction))
         (maxtips (pophint--get-max-tips source direction))
         forward-hints backward-hints) 
   (dolist (wnd (or (when allwindow (window-list nil t))
                     (and (windowp window) (window-live-p window) (list window))
                     (list (nth 0 (get-buffer-window-list)))))
      (with-selected-window wnd
        (when (or (not (functionp wndchker))
                  (funcall wndchker (window-buffer)))
          (save-restriction
            (yaxception:$
              (yaxception:try (narrow-to-region
                               (if (eq direction 'forward) (point) (window-start))
                               (if (eq direction 'backward) (point) (window-end))))
              (yaxception:catch 'error e
                (pophint--warn "failed narrow region : window:%s startpt:%s endpt:%s" wnd (window-start) (window-end))))
            (save-excursion
              (cl-loop initially (progn
                                (pophint--trace
                                 "start searching hint. require:[%s] max:[%s] buffer:[%s] point:[%s]\nregexp: %s\nfunc: %s"
                                 requires maxtips (current-buffer) (point) re srchfnc)
                                (when (functionp init) (funcall init))
                                (goto-char (point-min)))
                    with currpt = (point)
                    with lastpt = 0
                    with cnt = 0
                    with mtdret
                    while (and (yaxception:$
                                 (yaxception:try
                                   (cond (srchfnc (setq mtdret (funcall srchfnc)))
                                         (t       (re-search-forward re nil t))))
                                 (yaxception:catch 'error e
                                   (pophint--error "failed seek next popup point : %s\n%s"
                                                   (yaxception:get-text e) (yaxception:get-stack-trace-string e))))
                               (or (not maxtips)
                                   (< cnt maxtips)))
                    for startpt = (cond ((pophint:hint-p mtdret) (pophint:hint-startpt mtdret))
                                        (mtdret                  (plist-get mtdret :startpt))
                                        (t                       (or (match-beginning 1) (match-beginning 0))))
                    for endpt = (cond ((pophint:hint-p mtdret) (pophint:hint-endpt mtdret))
                                      (mtdret                  (plist-get mtdret :endpt))
                                      (t                       (or (match-end 1) (match-end 0))))
                    for value = (cond ((pophint:hint-p mtdret) (pophint:hint-value mtdret))
                                      (mtdret                  (plist-get mtdret :value))
                                      ((match-beginning 1)     (match-string-no-properties 1))
                                      (t                       (match-string-no-properties 0)))
                    if (not (pophint--valid-location-p lastpt startpt endpt))
                    return (pophint--warn "found hint location is invalid. text:[%s] lastpt:[%s] startpt:[%s] endpt:[%s]"
                                          value lastpt startpt endpt)
                    if (and (>= (length value) requires)
                            (pophint--hintable-location-p direction currpt startpt endpt))
                    do (let ((hint (cond ((pophint:hint-p mtdret) mtdret)
                                         (t                       (make-pophint:hint :startpt startpt :endpt endpt :value value)))))
                         (pophint--trace "found hint. text:[%s] startpt:[%s] endpt:[%s]" value startpt endpt)
                         (setf (pophint:hint-window hint) (selected-window))
                         (cl-incf cnt)
                         (if (<= endpt currpt)
                             (setq backward-hints (append (list hint) backward-hints))
                           (setq forward-hints (append forward-hints (list hint)))))
                    do (setq lastpt startpt)))))))
    (append forward-hints backward-hints)))

(make-face 'pophint--minibuf-tip-face)
(defun pophint--show-hint-tips (hints not-highlight &optional tip-face)
  (pophint--trace "start show hint tips. count:[%s] not-highlight:[%s] tip-face:[%s]"
                  (length hints) not-highlight tip-face)
  (pophint:delete-last-hints)
  (yaxception:$
    (yaxception:try
      (cl-loop initially (progn
                        (copy-face (or tip-face 'pophint:tip-face) 'pophint--minibuf-tip-face)
                        (set-face-attribute 'pophint--minibuf-tip-face nil :height 1.0))
            with orgwnd = (selected-window)
            with wnd = orgwnd
            with tiptexts = (pophint--make-unique-char-strings (length hints) pophint:popup-chars)
            with minibufp = (window-minibuffer-p wnd)
            for hint in hints
            for tiptext = (or (when tiptexts (pop tiptexts)) "")
            for nextwnd = (pophint:hint-window hint)
            if (string= tiptext "")
            return nil
            if (not (eq wnd nextwnd))
            do (progn (select-window nextwnd t)
                      (setq wnd (selected-window))
                      (setq minibufp (window-minibuffer-p wnd)))
            do (let* ((startpt (pophint:hint-startpt hint))
                      (endpt (pophint:hint-endpt hint))
                      ;; Get a covered part by the pop-up tip
                      (covered-endpt (+ startpt (length tiptext)))
                      (covered-v (buffer-substring-no-properties startpt (min covered-endpt (point-max))))
                      ;; The range, which the pop-up tip covers, is shrinked if it includes linefeed
                      (tip-endpt (+ startpt (or (string-match "\n" covered-v)
                                                (length tiptext))))
                      (tip-len (- tip-endpt startpt))
                      (tip (pophint--make-overlay startpt tip-endpt))
                      (ov (when (not not-highlight)
                            (pophint--make-overlay startpt endpt)))
                      (tip-face (or (when minibufp 'pophint--minibuf-tip-face)
                                    tip-face
                                    'pophint:tip-face)))
                 (put-text-property 0 (length tiptext) 'face tip-face tiptext)
                 (overlay-put tip 'text tiptext)
                 (overlay-put tip 'window (selected-window))
                 (overlay-put tip 'display (substring tiptext 0 tip-len))
                 (overlay-put tip 'after-string (substring tiptext tip-len))
                 (overlay-put tip 'priority 99)
                 (setf (pophint:hint-popup hint) tip)
                 (when ov
                   (overlay-put ov 'window (selected-window))
                   (overlay-put ov 'face 'pophint:match-face)
                   (overlay-put ov 'priority 10)
                   (setf (pophint:hint-overlay hint) ov)))
            finally do (select-window orgwnd t)))
    (yaxception:catch 'error e
      (pophint--deletes hints)
      (pophint--error "failed show hint tips : %s\n%s" (yaxception:get-text e) (yaxception:get-stack-trace-string e))
      (yaxception:throw e))))

(defsubst pophint--get-next-source (source sources &optional reverse)
  (cl-loop with maxidx = (- (length sources) 1)
        with i = (if reverse maxidx 0)
        with endi = (if reverse 0 maxidx)
        while (not (= i endi))
        for currsrc = (nth i sources)
        if (equal source currsrc)
        return (let* ((nidx (if reverse (- i 1) (+ i 1)))
                      (nidx (cond ((< nidx 0)      maxidx)
                                  ((> nidx maxidx) 0)
                                  (t               nidx))))
                 (pophint--trace "got next source index : %s" nidx)
                 (nth nidx sources))
        do (if reverse (cl-decf i) (cl-incf i))
        finally return (let ((nidx (if reverse maxidx 0)))
                         (nth nidx sources))))

(defsubst pophint--get-next-window (window)
  (pophint--with-no-last-condition
    (let ((basic-getter (lambda (w)
                          (with-selected-window (or (and (windowp w) (window-live-p w) w)
                                                    (get-buffer-window))
                            (next-window)))))
      (if (<= (length (window-list)) 2)
          (funcall basic-getter window)
        (or (pophint--awhen (pophint:do :source pophint--next-window-source :allwindow t :use-pos-tip t)
              (pophint:hint-window it))
            (progn
              (pophint--warn "failed get next window by pophint:do")
              (funcall basic-getter window)))))))

(cl-defun pophint--event-loop (hints cond &optional (inputed "") source-selection)
  (yaxception:$
    (yaxception:try
      (if (and (= (length hints) 1)
               (not (string= inputed "")))
          (pop hints)
        (setq pophint--last-hints hints)
        (let* ((source (pophint--condition-source cond))
               (sources (pophint--condition-sources cond))
               (action-name (pophint--condition-action-name cond))
               (window (pophint--condition-window cond))
               (allwindow (pophint--condition-allwindow cond))
               (not-switch-direction (pophint--condition-not-switch-direction cond))
               (not-switch-window (pophint--condition-not-switch-window cond))
               (not-switch-source (pophint--current-not-switch-source-p cond))
               (key (pophint--menu-read-key-sequence (pophint--make-prompt cond (length hints))
                                                     (pophint--condition-use-pos-tip cond)))
               (gbinding (when key (lookup-key (current-global-map) key)))
               (binding (or (when (and key (current-local-map))
                              (lookup-key (current-local-map) key))
                            gbinding)))
          (pophint--trace "got user input. key:[%s] gbinding:[%s] binding:[%s]" key gbinding binding)

          ;; Case by user input
          (cond
           ;; Error
           ((or (null key) (zerop (length key)))
            (pophint--warn "can't get user input")
            (pophint--deletes hints))
           ;; Quit
           ((eq gbinding 'keyboard-quit)
            (pophint--debug "user inputed keyboard-quit")
            (pophint--deletes hints)
            (keyboard-quit)
            nil)
           ;; Restart loop
           ((or (eq gbinding 'backward-delete-char-untabify)
                (eq gbinding 'delete-backward-char))
            (pophint--debug "user inputed delete command")
            (pophint--deletes hints)
            (pophint--let-user-select cond))
           ((or (eq gbinding 'self-insert-command)
                (and (stringp key)
                     (string-match key (mapconcat (lambda (s) (or s ""))
                                                  (list pophint:popup-chars
                                                        pophint:select-source-chars
                                                        pophint:switch-source-char
                                                        pophint:switch-source-reverse-char
                                                        pophint:switch-direction-char
                                                        pophint:switch-direction-reverse-char
                                                        pophint:switch-window-char)
                                                  ""))))
            (cond
             ;; Grep hints
             ((and (string-match key pophint:popup-chars)
                   (not source-selection))
              (pophint--debug "user inputed hint char")
              (let* ((currinputed (concat inputed (upcase key)))
                     (nhints (cl-loop with re = (concat "\\`" currinputed)
                                   for hint in hints
                                   for tip = (pophint:hint-popup hint)
                                   for tiptext = (or (when (overlayp tip) (overlay-get tip 'text))
                                                     "")
                                   if (and (string-match re tiptext)
                                           (overlayp tip))
                                   collect hint
                                   else
                                   do (pophint--delete hint))))
                (pophint--event-loop nhints cond currinputed)))
             ;; Select source
             ((and (or source-selection
                       (and (string-match key pophint:select-source-chars)
                            (eq pophint:select-source-method 'use-source-char)))
                   (not not-switch-source))
              (pophint--debug "user inputed select source char")
              (when (not source-selection) (setq inputed ""))
              (let* ((currinputed (concat inputed key))
                     (nsource (cl-loop for src in sources
                                    if (string= currinputed (or (assoc-default 'selector src) ""))
                                    return src)))
                (if (not nsource)
                    (pophint--event-loop hints cond currinputed t)
                  (pophint--deletes hints)
                  (setf (pophint--condition-source cond) nsource)
                  (pophint--let-user-select cond))))
             ;; Switch source
             ((and (or (string= key pophint:switch-source-char)
                       (string= key pophint:switch-source-reverse-char))
                   (not not-switch-source))
              (pophint--debug "user inputed switch source")
              (if (eq pophint:select-source-method 'use-popup-char)
                  (pophint--event-loop hints cond "" t)
                (cl-loop with reverse = (string= key pophint:switch-source-reverse-char)
                      do (setf (pophint--condition-source cond)
                               (pophint--get-next-source (pophint--condition-source cond) sources reverse))
                      while (and pophint:switch-source-delay
                                 (string= key (pophint--menu-read-key-sequence
                                               (pophint--make-prompt cond (length hints))
                                               (pophint--condition-use-pos-tip cond)
                                               pophint:switch-source-delay))))
                (pophint--deletes hints)
                (pophint--let-user-select cond)))
             ;; Switch direction
             ((and (or (string= key pophint:switch-direction-char)
                       (string= key pophint:switch-direction-reverse-char))
                   (not not-switch-direction))
              (pophint--debug "user inputed switch direction")
              (pophint--deletes hints)
              (let* ((reverse (string= key pophint:switch-direction-reverse-char))
                     (ndirection (cl-case (pophint--condition-direction cond)
                                   (forward  (if reverse 'around 'backward))
                                   (backward (if reverse 'forward 'around))
                                   (around   (if reverse 'backward 'forward))
                                   (t        'around))))
                (setf (pophint--condition-direction cond) ndirection)
                (pophint--let-user-select cond)))
             ;; Switch window
             ((and (string= key pophint:switch-window-char)
                   (not not-switch-window))
              (pophint--debug "user inputed switch window")
              (pophint--deletes hints)
              (let* ((nwindow (pophint--get-next-window window))
                     (nsources (when (not not-switch-source)
                                 (pophint--set-selector-sources (pophint--get-available-sources nwindow)))))
                (setf (pophint--condition-window cond) nwindow)
                ;; (when (and (> (length nsources) 0)
                ;;            (not (member source nsources)))
                ;;   (setf (pophint--condition-source cond) nil))
                (setf (pophint--condition-sources cond) nsources)
                (pophint--let-user-select cond)))
             ;; Warning
             (t
              (pophint--debug "user inputed worthless char")
              (pophint--show-message "Inputed not hint char.")
              (sleep-for 2)
              (pophint--event-loop hints cond inputed source-selection))))
           ;; Pass inputed command
           ((commandp binding)
            (pophint--debug "user inputed command : %s" binding)
            (pophint--deletes hints)
            (call-interactively binding)
            nil)
           ;; Abort
           (t
            (pophint--deletes hints))))))
    (yaxception:catch 'error e
      (pophint--deletes hints)
      (setq pophint--last-hints nil)
      (pophint--error "failed event loop : %s\n%s" (yaxception:get-text e) (yaxception:get-stack-trace-string e))
      (yaxception:throw e))))


;;;;;;;;;;;;;;;;;;;;
;; For pos-tip.el

(defun pophint--pos-tip-show (string)
  (copy-face 'pophint:pos-tip-face 'pos-tip-temp)
  (when (eq (face-attribute 'pos-tip-temp :font) 'unspecified)
    (set-face-font 'pos-tip-temp (frame-parameter nil 'font)))
  (set-face-bold 'pos-tip-temp (face-bold-p 'pophint:pos-tip-face))
  (cl-multiple-value-bind (wnd rightpt bottompt) (pophint--get-pos-tip-location)
    (let* ((max-width (pos-tip-x-display-width))
           (max-height (pos-tip-x-display-height))
           (tipsize (pophint--get-pos-tip-size string))
           (tipsize (cond ((or (> (car tipsize) max-width)
                               (> (cdr tipsize) max-height))
                           (setq string (pos-tip-truncate-string string max-width max-height))
                           (pophint--get-pos-tip-size string))
                          (t
                           tipsize)))
           (tipwidth (car tipsize))
           (tipheight (cdr tipsize))
           (dx (- rightpt tipwidth 10))
           (dy (- bottompt tipheight)))
      (pos-tip-show-no-propertize
       string 'pos-tip-temp 1 wnd 300 tipwidth tipheight nil dx dy))))

(defun pophint--get-pos-tip-size (string)
  "Return (WIDTH . HEIGHT) of the tip of pos-tip.el generated from STRING."
  (let* ((w-h (pos-tip-string-width-height string))
         (width (pos-tip-tooltip-width (car w-h) (frame-char-width)))
         (height (pos-tip-tooltip-height (cdr w-h) (frame-char-height))))
    (cons width height)))

(defun pophint--get-pos-tip-location ()
  "Return (WND RIGHT BOTTOM) as the location to show the tip of pos-tip.el."
  (let ((leftpt 0)
        (toppt 0)
        wnd rightpt bottompt)
    (dolist (w (window-list))
      (let* ((edges (when (not (minibufferp (window-buffer w)))
                      (window-pixel-edges w)))
             (currleftpt (or (nth 0 edges) -1))
             (currtoppt (or (nth 1 edges) -1)))
        (when (and (= currleftpt 0)
                   (= currtoppt 0))
          (setq wnd w))
        (when (or (not rightpt)
                  (> currleftpt leftpt))
          (setq rightpt (nth 2 edges))
          (setq leftpt currleftpt))
        (when (or (not bottompt)
                  (> currtoppt toppt))
          (setq bottompt (nth 3 edges))
          (setq toppt currtoppt))))
    (list wnd rightpt bottompt)))


;;;;;;;;;;;;;;;;;;;
;; User Function

;;;###autoload
(cl-defmacro pophint:defsource (&key name description source)
  "Define the variable and command to pop-up hint-tip by using given source.

NAME is string. It is used for define variable and command as part of the name.
DESCRIPTION is string. It is used for define variable as part of the docstring.
SOURCE is alist. The member is the following.

 - shown
     String to use for message in minibuffer when get user input.
     If nil, its value is NAME.

 - regexp
     String to use for finding next point of pop-up.
     If nil, its value is `pophint--default-search-regexp'.
     If exist group of matches, next point is beginning of group 1,
      else it is beginning of group 0.

 - requires
     Integer of minimum length of matched text as next point.
     If nil, its value is 0.

 - limit
     Integer to replace `pophint:popup-max-tips' with it.

 - action
     Function to be called when finish hint-tip selection.
     If nil, its value is `pophint--default-action'.
     It receive the object of `pophint:hint' selected by user.
     Also it accepts one of the following symbols, and returns
       - value : `pophint:hint-value' of the selected
       - point : `pophint:hint-startpt' of the selected
       - hint  : `pophint:hint' as the selected

 - method
     Function to find next point of pop-up.
     If nil, its value is `re-search-forward', and regexp is used.

 - init
     Function to be called before finding pop-up points
      for each of window/direction.

 - highlight
     Boolean. Default is t.
     If nil, don't highlight matched text when pop-up hint.

 - dedicated
     Symbol or list to mean the situation that SOURCE is dedicated for.
     If non-nil, added to `pophint:dedicated-sources'.

 - activebufferp
     Function to call for checking if SOURCE is activated in the buffer.
     It is required with `dedicated' option.
     It receives a buffer object and
      needs to return non-nil if the buffer is the target of itself.

 - tip-face-attr
     It is plist for customize of `pophint:tip-face' temporarily.

Example:
 (pophint:defsource :name \"sexp-head\"
                    :description \"Head word of sexp.\"
                    :source \\='((shown . \"SexpHead\")
                              (regexp . \"(+\\([^() \t\n]+\\)\")
                              (requires . 1)))
"
  (declare (indent 0))
  (let* ((symnm (downcase (replace-regexp-in-string " +" "-" name)))
         (var-sym (intern (format "pophint:source-%s" symnm)))
         (var-doc (format "Source for pop-up hint-tip of %s.\n\nDescription:\n%s"
                          name (or description "Not documented.")))
         (fnc-sym (intern (format "pophint:do-%s" symnm)))
         (fnc-doc (format "Do pop-up hint-tip using `%s'." var-sym)))
    `(progn
       (defvar ,var-sym nil
         ,var-doc)
       (setq ,var-sym ,source)
       (when (not (assoc-default 'shown ,var-sym))
         (add-to-list ',var-sym '(shown . ,name)))
       (when (assoc-default 'dedicated ,var-sym)
         (add-to-list 'pophint:dedicated-sources ',var-sym t))
       (defun ,fnc-sym ()
         ,fnc-doc
         (interactive)
         (pophint:do :source ',var-sym)))))

;;;###autoload
(cl-defmacro pophint:defaction (&key key name description action)
  "Define the action to be called when finish hint-tip selection.

KEY is string of one character to input on `pophint:do-interactively'.
NAME is string to be part of the command name and shown on user input.
DESCRIPTION is string to be part of the docstring of the command.
ACTION is function. For detail, see action of SOURCE for `pophint:defsource'.

Example:
 (pophint:defaction :key \"y\"
                    :name \"Yank\"
                    :description \"Yank the text of selected hint-tip.\"
                    :action (lambda (hint)
                              (kill-new (pophint:hint-value hint))))
"
  (declare (indent 0))
  (let ((fnc-sym (intern (format "pophint:do-flexibly-%s"
                                 (downcase (replace-regexp-in-string " +" "-" name)))))
        (fnc-doc (format "Do pop-up hint-tip using source in `pophint:sources' and do %s.\n\nDescription:\n%s"
                         name (or description "Not documented."))))
    `(progn
       (let ((key ,key)
             (name ,name)
             (action ,action))
         (if (or (not (stringp key))
                 (string= key "")
                 (not (= (length key) 1)))
             (pophint--show-message "Failed pophint:defaction : key is not one character.")
           (puthash key
                    (make-pophint:action :name name :action action)
                    pophint--action-hash)
           (defun ,fnc-sym ()
             ,fnc-doc
             (interactive)
             (let ((act (gethash ,key pophint--action-hash)))
               (pophint:do-flexibly :action (pophint:action-action act)
                                    :action-name (pophint:action-name act)))))))))

;;;###autoload
(cl-defmacro pophint:defsituation (situation)
  "Define the command to pop-up hint-tip in SITUATION.

SITUATION is symbol. It is used for finding the sources that is dedicated
for SITUATION from `pophint:dedicated-sources'.

Example:
 (pophint:defsituation e2wm)
"
  (declare (indent 0))
  (let* ((symnm (downcase (replace-regexp-in-string " +" "-" (symbol-name situation))))
         (fnc-sym (intern (format "pophint:do-situationally-%s" symnm)))
         (fnc-doc (format "Do `pophint:do-situationally' for '%s'." symnm)))
    `(progn
       (defun ,fnc-sym ()
         ,fnc-doc
         (interactive)
         (pophint:do-situationally ',situation)))))

;;;###autoload
(cl-defmacro pophint:set-allwindow-command (func)
  "Define advice to FUNC for doing pop-up at all windows.

FUNC is symbol not quoted.

e.g. (pophint:set-allwindow-command pophint:do-flexibly)"
  `(defadvice ,func (around pophint-allwindow activate)
     (let ((pophint--enable-allwindow-p t))
       ad-do-it)))

;;;###autoload
(cl-defmacro pophint:set-not-allwindow-command (func)
  "Define advice to FUNC for doing pop-up at one window.

FUNC is symbol not quoted.

e.g. (pophint:set-not-allwindow-command pophint:do-flexibly)"
  `(defadvice ,func (around pophint-not-allwindow activate)
     (let ((pophint--disable-allwindow-p t))
       ad-do-it)))

;;;###autoload
(cl-defmacro pophint:defcommand-determinate (&key source-name
                                                action-name
                                                other-windows-p
                                                all-windows-p
                                                ignore-already-defined)
  "Define a determinate command using SOURCE-NAME, ACTION-NAME."
  (declare (indent 0))
  (let* ((wnd-typenm (cond (all-windows-p   "all-windows")
                           (other-windows-p "other-windows")
                           (t               "current-window")))
         (source-sym-name (downcase (replace-regexp-in-string " +" "-" source-name)))
         (action-sym-name (downcase (replace-regexp-in-string " +" "-" action-name)))
         (fnc-sym (intern (format "pophint:%s-%s-on-%s"
                                  action-sym-name source-sym-name wnd-typenm)))
         (fnc-doc (format "Do pop-up hint-tip using `pophint:source-%s' to %s in %s"
                          source-sym-name action-name wnd-typenm))
         (opt-source-parts (when other-windows-p
                             '((activebufferp . (lambda (b)
                                                  (not (eql b (current-buffer))))))))
         (source (symbol-value (intern (format "pophint:source-%s" source-sym-name)))))
    `(progn
       (when (or (not ,ignore-already-defined)
                 (not (commandp ',fnc-sym)))
         (defun ,fnc-sym ()
           ,fnc-doc
           (interactive)
           (let ((action-func (cl-loop for act being the hash-values in pophint--action-hash
                                    if (string= ,action-name (pophint:action-name act))
                                    return (pophint:action-action act))))
             (pophint:do :source '(,@opt-source-parts ,@source)
                         :action action-func
                         :action-name ,action-name
                         :not-switch-window t
                         :allwindow ,all-windows-p)))))))

;;;###autoload
(cl-defun pophint:defcommand-exhaustively (&key feature)
  "Do `pophint:defcommand-determinate' for all sources/actions/windows."
  (cl-loop for var-sym in (apropos-internal "\\`pophint:source-")
        for varnm = (replace-regexp-in-string "\\`pophint:source-" "" (symbol-name var-sym))
        for commands = (cl-loop for act being the hash-values in pophint--action-hash
                             for actnm = (pophint:action-name act)
                             collect (eval `(pophint:defcommand-determinate :source-name ,varnm
                                                                            :action-name ,actnm
                                                                            :ignore-already-defined t))
                             collect (eval `(pophint:defcommand-determinate :source-name ,varnm
                                                                            :action-name ,actnm
                                                                            :ignore-already-defined t
                                                                            :other-windows-p t))
                             collect (eval `(pophint:defcommand-determinate :source-name ,varnm
                                                                            :action-name ,actnm
                                                                            :ignore-already-defined t
                                                                            :all-windows-p t)))
        if feature
        do (cl-loop for cmd in commands
                 if cmd
                 do (autoload cmd feature))))

;;;###autoload
(defun pophint:get-current-direction ()
  "Get current direction of searching next point for pop-up hint-tip."
  (when (pophint--condition-p pophint--last-condition)
    (pophint--condition-direction pophint--last-condition)))

;;;###autoload
(cl-defun pophint:inch-forward (&key (length pophint:inch-forward-length))
  (let* ((currpt (point))
         (pt1 (save-excursion
                (cl-loop for pt = (progn (forward-word 1) (point))
                         until (or (>= (- pt currpt) length)
                                   (= pt (point-max))))
                (point)))
         (pt2 (save-excursion
                (cl-loop for re in '("\\w+" "\\s-+" "\\W+" "\\w+")
                         for pt = (progn (re-search-forward (concat "\\=" re) nil t)
                                         (point))
                         if (>= (- pt currpt) length)
                         return pt
                         finally return pt1))))
    (goto-char (if (> pt1 pt2) pt2 pt1))))
(define-obsolete-function-alias 'pophint-config:inch-forward 'pophint:inch-forward "1.1.0")

;;;###autoload
(cl-defun pophint:make-hint-with-inch-forward (&key limit (length pophint:inch-forward-length))
  (let ((currpt (point))
        (nextpt (progn (pophint:inch-forward) (point))))
    (when (and (or (not limit)
                   (<= currpt limit))
               (>= (- nextpt currpt) length))
      `(:startpt ,currpt :endpt ,nextpt :value ,(buffer-substring-no-properties currpt nextpt)))))
(define-obsolete-function-alias 'pophint-config:make-hint-with-inch-forward 'pophint:make-hint-with-inch-forward "1.1.0")


;;;;;;;;;;;;;;;;;;
;; User Command

;;;###autoload
(cl-defun pophint:do (&key source
                         sources
                         action
                         action-name
                         direction
                         not-highlight
                         window
                         not-switch-window
                         allwindow
                         (use-pos-tip 'global)
                         tip-face-attr
                         context)
  "Do pop-up hint-tip using given source on target to direction.

SOURCE is alist or symbol of alist. About its value, see `pophint:defsource'.
 If nil, its value is the first of SOURCES or `pophint--default-source'.
 If non-nil, `pophint--default-source' isn't used for SOURCES.

SOURCES is list of SOURCE.
 If this length more than 1, enable switching SOURCE when pop-up hint.

ACTION is function or symbol.
 About this, see action of SOURCE for `pophint:defsource'. If nil, it's used.

ACTION-NAME is string.
 About this, see name of `pophint:defaction'.

DIRECTION is symbol to be strategy of finding the pop-up points.
 - forward  : moving forward until `pophint:popup-max-tips'.
 - backward : moving backward until `pophint:popup-max-tips'.
 - around   : moving both until half of `pophint:popup-max-tips'.
 If nil, enable switching DIRECTION when pop-up hint.

NOT-HIGHLIGHT is t or nil.
 If non-nil, don't highlight matched text when pop-up hint.

WINDOW is window to find next point of pop-up in the window.
 If nil, its value is `selected-window'.

NOT-SWITCH-WINDOW is t or nil.
 If non-nil, disable switching window when select shown hint.

ALLWINDOW is t or nil.
 If non-nil, pop-up at all windows in frame.

USE-POS-TIP is t or nil.
 If omitted, inherit `pophint:use-pos-tip'.

TIP-FACE-ATTR is plist for customize of `pophint:tip-face' temporarily."
  (interactive)
  (let ((pophint--resumed-input-method current-input-method))
    
    (ignore-errors (deactivate-input-method))
    
    (yaxception:$
      (yaxception:try
        (pophint--debug
         "start do.\ndirection:%s\nnot-highlight:%s\nwindow:%s\nnot-switch-window:%s\nallwindow:%s\naction-name:%s\naction:%s\nsource:%s\nsources:%s"
         direction not-highlight window not-switch-window allwindow action-name action source sources)
        (let* (;; (current-input-method nil)
               (case-fold-search nil)
               (allwindow-p (and (or allwindow
                                     pophint--enable-allwindow-p
                                     pophint:do-allwindow-p)
                                 (not pophint--disable-allwindow-p)
                                 (not window)))
               (c (make-pophint--condition :source (pophint--compile-source source)
                                           :sources (pophint--set-selector-sources (pophint--compile-sources sources))
                                           :action action
                                           :action-name (or action-name pophint--default-action-name)
                                           :direction (or direction
                                                          (when (not pophint:switch-direction-p) 'around)
                                                          (pophint:get-current-direction)
                                                          'around)
                                           :window window
                                           :allwindow allwindow-p
                                           :use-pos-tip (if (eq use-pos-tip 'global) pophint:use-pos-tip use-pos-tip)
                                           :not-highlight not-highlight
                                           :not-switch-direction (or (when direction t)
                                                                     (not pophint:switch-direction-p))
                                           :not-switch-window (or not-switch-window (one-window-p) allwindow-p)
                                           :not-switch-source (and source (not sources))
                                           :tip-face (when tip-face-attr
                                                       (pophint--update-tip-face tip-face-attr))))
               (hint (pophint--let-user-select c :context context)))
          (pophint--do-action hint (pophint--current-action c))))
      (yaxception:catch 'error e
        (pophint--show-message "Failed pophint:do : %s" (yaxception:get-text e))
        (pophint--fatal "failed do : %s\n%s" (yaxception:get-text e) (yaxception:get-stack-trace-string e))
        (pophint--log-open-log-if-debug))
      (yaxception:finally
        (pophint--awhen pophint--resumed-input-method
          (activate-input-method it))))))

;;;###autoload
(cl-defun pophint:do-flexibly (&key action action-name window)
  "Do pop-up hint-tip using source in `pophint:sources'.

For detail, see `pophint:do'."
  (interactive)
  (pophint--debug "start do flexibly. window:[%s] action-name:[%s]\naction:%s" window action-name action)
  (let* ((pophint--current-context (format "pophint:do-flexibly-%s"
                                           (downcase (replace-regexp-in-string " +" "-" (or action-name "")))))
         (lastc (pophint--get-last-condition-with-context pophint--current-context))
         (window (or window
                     (when (pophint--condition-p lastc)
                       (pophint--condition-window lastc))))
         (sources (pophint--get-available-sources window))
         (lastsrc (when (pophint--condition-p lastc)
                    (pophint--condition-source lastc)))
         (compsrc (pophint--aif (assq 'selector lastsrc)
                      (delq it (copy-sequence lastsrc))
                    lastsrc))
         (source (when (and compsrc
                            (member compsrc sources))
                   lastsrc)))
    (pophint:do :source source
                :sources sources
                :action action
                :action-name action-name
                :window window)))

;;;###autoload
(defun pophint:do-interactively ()
  "Do pop-up hint-tip asking about what to do after select hint-tip."
  (interactive)
  (yaxception:$
    (yaxception:try
      (let* ((key (pophint--menu-read-key-sequence (pophint--make-prompt-interactively)
                                                   pophint:use-pos-tip))
             (gbinding (lookup-key (current-global-map) key))
             (binding (or (when (current-local-map)
                            (lookup-key (current-local-map) key))
                          gbinding)))
        (pophint--trace "got user input. key:[%s] gbinding:[%s] binding:[%s]" key gbinding binding)
        (cond ((or (null key) (zerop (length key)))
               (pophint--warn "can't get user input"))
              ((eq gbinding 'keyboard-quit)
               (pophint--debug "user inputed keyboard-quit")
               (pophint--show-message "Quit do-interactively."))
              ((eq gbinding 'newline)
               (pophint--debug "user inputed newline")
               (pophint:do-flexibly))
              ((eq gbinding 'self-insert-command)
               (let* ((action (gethash key pophint--action-hash)))
                 (cond ((pophint:action-p action)
                        (pophint:do-flexibly :action (pophint:action-action action)
                                             :action-name (pophint:action-name action)))
                       (t
                        (pophint--show-message "Inputed not start key of action.")
                        (sleep-for 2)
                        (pophint:do-interactively)))))
              ((commandp binding)
               (pophint--debug "user inputed command : %s" binding)
               (call-interactively binding)
               (pophint:do-interactively)))))
    (yaxception:catch 'error e
      (pophint--show-message "Failed pophint:do-interactively : %s" (yaxception:get-text e))
      (pophint--fatal "failed do-interactively : %s\n%s" (yaxception:get-text e) (yaxception:get-stack-trace-string e))
      (pophint--log-open-log-if-debug))))

;;;###autoload
(defun pophint:do-situationally (situation)
  "Do pop-up hint-tip for SITUATION.

SITUATION is symbol to be defined on `pophint:defsituation'."
  (interactive
   (list (intern
          (completing-read "Select situation: "
                           (cl-loop with ret = nil
                                 for src in (pophint--compile-sources pophint:dedicated-sources)
                                 for dedicated = (assoc-default 'dedicated src)
                                 if dedicated
                                 do (cond ((symbolp dedicated) (cl-pushnew dedicated ret))
                                          ((listp dedicated)   (cl-loop for e in dedicated do (cl-pushnew e ret))))
                                 finally return ret)
                           nil t nil '()))))
  (yaxception:$
    (yaxception:try
      (pophint--trace "start do situationally. situation[%s]" situation)
      (let* ((current-input-method nil)
             (sources (cl-loop for src in (pophint--compile-sources pophint:dedicated-sources)
                            for dedicated = (assoc-default 'dedicated src)
                            if (or (and dedicated
                                        (symbolp dedicated)
                                        (eq dedicated situation))
                                   (and dedicated
                                        (listp dedicated)
                                        (memq situation dedicated)))
                            collect src))
             (not-highlight (cl-loop for src in sources
                                  always (and (assq 'highlight src)
                                              (not (assoc-default 'highlight src)))))
             (actionh (make-hash-table :test 'equal))
             (cond (make-pophint--condition :sources sources
                                            :action-name (upcase (symbol-name situation))
                                            :direction 'around
                                            :use-pos-tip pophint:use-pos-tip
                                            :not-highlight not-highlight
                                            :not-switch-direction t
                                            :not-switch-window t
                                            :not-switch-source t))
             (hints (cl-loop for wnd in (window-list nil nil)
                          do (setf (pophint--condition-window cond) wnd)
                          append (with-selected-window wnd
                                   (cl-loop with buff = (window-buffer)
                                         for src in sources
                                         for chker = (assoc-default 'activebufferp src)
                                         if (and (functionp chker)
                                                 (funcall chker buff))
                                         return (progn
                                                  (puthash (buffer-name buff) (assoc-default 'action src) actionh)
                                                  (setf (pophint--condition-source cond) src)
                                                  (pophint--get-hints cond))))))
             (hint (progn (pophint--show-hint-tips hints not-highlight)
                          (pophint--event-loop hints cond)))
             (action (or (when hint
                           (gethash (buffer-name (window-buffer (pophint:hint-window hint))) actionh))
                         pophint--default-action)))
        (pophint--do-action hint action)))
    (yaxception:catch 'error e
      (pophint--show-message "Failed pophint:do situationally : %s" (yaxception:get-text e))
      (pophint--fatal "failed do situationally : %s\n%s"
                      (yaxception:get-text e) (yaxception:get-stack-trace-string e))
      (pophint--log-open-log-if-debug))))

;;;###autoload
(defun pophint:redo ()
  "Redo last pop-up hint-tip using any sources."
  (interactive)
  (yaxception:$
    (yaxception:try
      (if (not (pophint--condition-p pophint--last-condition))
          (pophint--show-message "Failed pophint:redo : Maybe pophint:do done not yet")
        (let ((hint (pophint--let-user-select pophint--last-condition)))
          (pophint--do-action hint (pophint--current-action pophint--last-condition)))))
    (yaxception:catch 'error e
      (pophint--show-message "Failed pophint:redo : %s" (yaxception:get-text e))
      (pophint--fatal "failed redo : %s\n%s" (yaxception:get-text e) (yaxception:get-stack-trace-string e))
      (pophint--log-open-log-if-debug))))

;;;###autoload
(defun pophint:toggle-use-pos-tip ()
  "Toggle the status of `pophint:use-pos-tip'."
  (interactive)
  (setq pophint:use-pos-tip (not pophint:use-pos-tip)))

;;;###autoload
(defun pophint:delete-last-hints ()
  "Delete last hint-tip."
  (interactive)
  (when pophint--last-hints
    (pophint--deletes pophint--last-hints)
    (setq pophint--last-hints nil)))


(defadvice keyboard-quit (before pophint:delete-last-hints activate)
  (ignore-errors (pophint:delete-last-hints)))


(provide 'pophint)
;;; pophint.el ends here
