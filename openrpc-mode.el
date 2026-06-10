;;; openrpc-mode.el --- Discover and browse OpenRPC methods  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Free Software Foundation, Inc.

;; Author: <your-name>
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (jsonrpc "1.0") (jsonrpc-noenvelope "0.1.0"))
;; Keywords: tools, comm, languages
;; URL: https://github.com/yourname/openrpc-mode

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides an interface for discovering and browsing
;; OpenRPC methods exposed by JSON-RPC endpoints over stdio.
;;
;; The main entry point is `openrpc-mode-discover', which prompts the
;; user for a command string (e.g., "my-cli --stdio"), launches that
;; command as an asynchronous subprocess, and communicates with it
;; using the `jsonrpc' library.
;;
;; By default the standard `jsonrpc-process-connection' class is used,
;; which expects the HTTP Content-Length envelope format.  If the
;; endpoint speaks raw newline-delimited JSON (without Content-Length
;; headers), set `openrpc-mode-use-envelope' to nil or call
;; `openrpc-mode-discover' with a prefix argument.  In that case the
;; `jsonrpc-noenvelope' subclass is used instead.
;;
;; After connecting, an `rpc.discover' request is sent.  The resulting
;; OpenRPC document is parsed and displayed in a `tabulated-list-mode'
;; derived buffer named `*openrpc-methods*', listing all discovered
;; methods with their names, summaries, parameter counts, and result
;; type descriptions.
;;
;;; Code:

;; NOTE: When compiling in batch mode for Nix/guix, you may need
;; to add these directories to the load-path:
;;   -L …/site-lisp/elpa/jsonrpc-1.0.28
;;   -L …/site-lisp/elpa/anaphora-1.0.6
(require 'jsonrpc)
(require 'jsonrpc-noenvelope)
(require 'tabulated-list)
(eval-when-compile (require 'cl-lib))

;;; Customization

(defgroup openrpc-mode nil
  "Discover and browse OpenRPC methods."
  :prefix "openrpc-mode-"
  :group 'tools)

(defcustom openrpc-mode-buffer-name "*openrpc-methods*"
  "Name of the buffer used to display discovered methods."
  :type 'string
  :group 'openrpc-mode)

(defcustom openrpc-mode-events-buffer-size 1000
  "Maximum size of the JSONRPC events buffer (in lines).
Set to nil for unlimited, 0 to disable."
  :type '(choice (const :tag "Unlimited" nil)
                 (integer :tag "Lines"))
  :group 'openrpc-mode)

(defcustom openrpc-mode-use-envelope t
  "Whether to use the HTTP Content-Length envelope for JSONRPC.
Non-nil (the default) uses `jsonrpc-process-connection', which
transmits messages with Content-Length headers.

When nil, uses `jsonrpc-noenvelope' instead, which sends and
receives raw newline-delimited JSON objects.  Set this to nil
for endpoints that speak plain JSON lines over stdio without
the HTTP-style envelope."
  :type 'boolean
  :group 'openrpc-mode
  :safe #'booleanp)

;;; Internal variables

(defvar-local openrpc-mode--connection nil
  "The `jsonrpc-process-connection' object for the current session.")

(defvar-local openrpc-mode--methods nil
  "List of discovered methods, each a plist from the OpenRPC document.")

(defvar openrpc-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'openrpc-mode-revert)
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "RET") #'openrpc-mode-show-method-detail)
    (define-key map (kbd "E") #'openrpc-mode-show-events)
    map)
  "Keymap for `openrpc-mode' buffers.")

;;; The tabulated-list mode

(defun openrpc-mode--make-entry (method)
  "Create a `tabulated-list-entry' from METHOD, a plist.
METHOD should be an OpenRPC method object with at least a `:name'
property."
  (let* ((name     (or (plist-get method :name) "?"))
         (summary  (or (plist-get method :summary)
                       (plist-get method :description)
                       ""))
         (params   (plist-get method :params))
         (n-params (if params (length params) 0))
         (result   (plist-get method :result))
         (result-name
          (cond ((plist-get result :name))
                ((plist-get result :schema)
                 (let ((ref (plist-get (plist-get result :schema) :$ref)))
                   (if ref (file-name-nondirectory ref) "object")))
                (t ""))))
    (list name
          (vector (propertize name 'face 'font-lock-function-name-face)
                  (propertize summary 'face 'font-lock-doc-face)
                  (format "%d" n-params)
                  result-name))))

(defun openrpc-mode--refresh ()
  "Refresh the current `openrpc-mode' buffer with `openrpc-mode--methods'."
  (setq tabulated-list-entries
        (mapcar #'openrpc-mode--make-entry openrpc-mode--methods))
  (tabulated-list-print t))

(define-derived-mode openrpc-mode tabulated-list-mode "OpenRPC Methods"
  "Major mode for browsing discovered OpenRPC methods.

\\{openrpc-mode-map}"
  (setq tabulated-list-format
        [("Method" 40 t)
         ("Summary" 60 nil)
         ("Params" 8 t)
         ("Result Type" 30 t)])
  (setq tabulated-list-sort-key (cons "Method" nil))
  (add-hook 'tabulated-list-revert-hook #'openrpc-mode-revert nil t)
  (tabulated-list-init-header))

;;; Connection management

(defun openrpc-mode--make-process-for-connection (command connection-name)
  "Create a subprocess from COMMAND, using CONNECTION-NAME as
the Emacs process name.  Stderr is captured to a separate buffer
named `*CONNECTION-NAME stderr*'.  The jsonrpc library's
`initialize-instance :after' method detects that this buffer
already exists and adds its forwarding hook, so stderr lines
end up in the events buffer."
  (make-process
   :name connection-name
   :command (split-string-and-unquote command)
   :connection-type 'pipe
   :stderr (get-buffer-create (format "*%s stderr*" connection-name))
   :noquery t))

(defun openrpc-mode--on-shutdown (conn)
  "Called when JSONRPC connection CONN is shut down.
Keeps the results buffer intact for browsing."
  (when-let* ((buffer (get-buffer openrpc-mode-buffer-name)))
    (with-current-buffer buffer
      ;; Keep `openrpc-mode--connection' and `openrpc-mode--methods'
      ;; around so the user can still browse the last results.
      (message "OpenRPC connection to %s has closed."
               (jsonrpc-name conn)))))

(defun openrpc-mode--connection-name (command)
  "Derive a short connection name from COMMAND."
  (let* ((parts (split-string-and-unquote command))
         (base (file-name-nondirectory (car parts))))
    (format "openrpc-%s" base)))

;;; Main entry point

;;;###autoload
(defun openrpc-mode-discover (command)
  "Connect to COMMAND via stdio and discover its OpenRPC methods.

COMMAND is a shell command string that launches a JSON-RPC
endpoint over stdio.

When called with a prefix argument \[universal-argument], the
transport is toggled from the `openrpc-mode-use-envelope'
setting."
  (interactive "sOpenRPC command: ")
  (when (string-blank-p command)
    (user-error "Command must not be empty"))
  (let* ((name (openrpc-mode--connection-name command))
         (effective-envelope
          (if current-prefix-arg
              (not openrpc-mode-use-envelope)
            openrpc-mode-use-envelope))
         (class (if effective-envelope
                    'jsonrpc-process-connection
                  'jsonrpc-noenvelope))
         (events-config `(:size ,openrpc-mode-events-buffer-size
                          :format full))
         (proc (openrpc-mode--make-process-for-connection command name))
         (conn (make-instance
                class
                :name name
                :process proc
                :on-shutdown #'openrpc-mode--on-shutdown
                :events-buffer-config events-config))
         (buffer (get-buffer-create openrpc-mode-buffer-name)))
    ;; Prepare the results buffer
    (with-current-buffer buffer
      (openrpc-mode)
      (setq openrpc-mode--connection conn
            openrpc-mode--methods nil)
      (openrpc-mode--refresh))
    ;; Issue the rpc.discover request
    (jsonrpc-async-request
     conn
     :rpc.discover
     :jsonrpc-omit ;; no params needed
     :success-fn
     (lambda (result)
       (openrpc-mode--on-discover-success result conn))
     :error-fn
     (lambda (err)
       (openrpc-mode--on-discover-error err conn))
     :timeout-fn
     (lambda ()
       (openrpc-mode--on-discover-timeout conn)))
    ;; Show the (still empty) results buffer
    (display-buffer buffer)
    (message
     (concat "Discovering OpenRPC methods via `%s'..."
             " (transport: %s)")
     command
     (if (eq class 'jsonrpc-noenvelope)
         "newline-delimited JSON"
       "Content-Length envelope"))))

(defun openrpc-mode--on-discover-success (result conn)
  "Handle successful `rpc.discover' response.
RESULT is the JSONRPC result (the OpenRPC document).
CONN is the `jsonrpc-process-connection'."
  (let* ((methods (plist-get result :methods))
         (count   (length methods))
         (buffer  (get-buffer openrpc-mode-buffer-name)))
    (if (not (sequencep methods))
        (progn
          (jsonrpc-shutdown conn)
          (message "rpc.discover returned unexpected result: no methods array"))
      ;; json-parse-buffer returns arrays as vectors; normalize to list
      (when buffer
        (with-current-buffer buffer
          (setq openrpc-mode--methods (append methods nil))
          (openrpc-mode--refresh)))
      (message "Discovered %d OpenRPC method(s) from `%s'."
               count (jsonrpc-name conn)))))

(defun openrpc-mode--on-discover-error (err conn)
  "Handle error from `rpc.discover' request.
ERR is the JSONRPC error object (a plist).
CONN is the `jsonrpc-process-connection'."
  (let ((status (openrpc-mode--process-status-string conn)))
    (jsonrpc-shutdown conn)
    (message "rpc.discover failed: %s (process: %s)"
             (or (plist-get err :message) "unknown error") status)))

(defun openrpc-mode--process-status-string (conn)
  "Return a human-readable status string for CONN's process."
  (if (jsonrpc-running-p conn)
      "still running"
    (let* ((proc (ignore-errors (jsonrpc--process conn)))
           (status (and proc (process-status proc)))
           (exit-code (and proc (process-exit-status proc))))
      (format "%s (exit code %s)" status exit-code))))

(defun openrpc-mode--on-discover-timeout (conn)
  "Handle timeout of `rpc.discover' request.
CONN is the `jsonrpc-process-connection'."
  (let ((status (openrpc-mode--process-status-string conn)))
    (jsonrpc-shutdown conn)
    (message "rpc.discover timed out after %d seconds (process: %s)."
             jsonrpc-default-request-timeout status)))

;;; Interactive commands for the mode

(defun openrpc-mode-revert (&optional _ignore-auto _noconfirm)
  "Re-issue the `rpc.discover' request and refresh the buffer.
If the previous connection died, starts a fresh one using the
last command."
  (interactive)
  (let ((conn openrpc-mode--connection))
    (cond
     ((not conn)
      (user-error "No OpenRPC connection; use `M-x openrpc-mode-discover' first"))
     ((not (jsonrpc-running-p conn))
      (user-error "Connection is dead; use `M-x openrpc-mode-discover' to start a new one"))
     (t
      (setq openrpc-mode--methods nil)
      (openrpc-mode--refresh)
      (jsonrpc-async-request
       conn
       :rpc.discover
       :jsonrpc-omit
       :success-fn
       (lambda (result)
         (openrpc-mode--on-discover-success result conn))
       :error-fn
       (lambda (err)
         (openrpc-mode--on-discover-error err conn))
       :timeout-fn
       (lambda ()
         (openrpc-mode--on-discover-timeout conn)))
      (message "Re-discovering OpenRPC methods...")))))

(defun openrpc-mode-show-method-detail ()
  "Show details of the method at point in a help buffer."
  (interactive)
  (let* ((id   (tabulated-list-get-id))
         (methods openrpc-mode--methods)
         (method (and id (cl-find id methods
                                  :key (lambda (m) (plist-get m :name))
                                  :test #'string=
                                  :start (if (listp methods) 0)))))
    (unless method
      (user-error "No method at point"))
    (pop-to-buffer (get-buffer-create "*openrpc-method-detail*"))
    (erase-buffer)
    (insert (format "Method: %s\n\n" (plist-get method :name)))
    (when-let* ((summary (plist-get method :summary)))
      (insert (format "Summary: %s\n" summary)))
    (when-let* ((description (plist-get method :description)))
      (insert (format "\nDescription:\n%s\n" description)))
    (when-let* ((params (plist-get method :params)))
      (insert "\nParameters:\n")
      ;; json-parse-buffer returns arrays as vectors; normalize to list
      (dolist (p (append params nil))
        (insert (format "  - %s : %s\n"
                        (or (plist-get p :name) "?")
                        (or (plist-get p :description) "")))))
    (when-let* ((result (plist-get method :result)))
      (insert (format "\nResult: %s\n"
                      (or (plist-get result :name)
                          (plist-get result :description)
                          ""))))
    (special-mode)
    (goto-char (point-min))))

;;; Diagnostics

(defun openrpc-mode-show-events ()
  "Display the JSONRPC events buffer for the current connection.
Useful for debugging what was sent to and received from the
endpoint."
  (interactive)
  (let* ((conn (and (derived-mode-p 'openrpc-mode)
                    openrpc-mode--connection))
         (buf (and conn (ignore-errors (jsonrpc-events-buffer conn)))))
    (if buf
        (display-buffer buf)
      (user-error "No events buffer available"))))

(defun openrpc-mode-test-connection ()
  "Send a simple ping to test the connection.
Interactively prompts for a method to call."
  (interactive)
  (let ((conn (and (derived-mode-p 'openrpc-mode)
                   openrpc-mode--connection)))
    (unless conn
      (user-error "Not in an openrpc-mode buffer"))
    (unless (jsonrpc-running-p conn)
      (user-error "Connection is not running"))
    (let ((method (read-from-minibuffer "Method to call: " "rpc.discover")))
      (jsonrpc-async-request
       conn
       (intern method)
       :jsonrpc-omit
       :success-fn
       (lambda (result)
         (message "Response: %S" result))
       :error-fn
       (lambda (err)
         (message "Error: %S" err))
       :timeout-fn
       (lambda ()
         (message "Request timed out")))
      (message "Sent request for `%s'..." method))))

;;; Cleanup

(defun openrpc-mode-shutdown ()
  "Shutdown the current OpenRPC connection and cleanup buffers."
  (interactive)
  (when (and openrpc-mode--connection
             (jsonrpc-running-p openrpc-mode--connection))
    (jsonrpc-shutdown openrpc-mode--connection t))
  (when-let* ((buf (get-buffer openrpc-mode-buffer-name)))
    (with-current-buffer buf
      (setq openrpc-mode--connection nil
            openrpc-mode--methods nil))
    (kill-buffer buf))
  (message "OpenRPC connection shut down."))

(provide 'openrpc-mode)

;;; openrpc-mode.el ends here
