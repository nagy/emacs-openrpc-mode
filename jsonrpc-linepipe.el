;;; jsonrpc-linepipe.el --- Newline-framed JSONRPC for jsonrpc.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Daniel Nagy

;; Author: Daniel Nagy
;; Package-Requires: ((emacs "31.1") (jsonrpc "1.0.25"))
;; Keywords: comm, processes

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public
;; License along with this program.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `jsonrpc-linepipe' is a subclass of `jsonrpc-process-connection' for
;; endpoints that speak raw JSON-RPC 2.0 over stdio as newline-delimited
;; JSON objects, without the HTTP-style Content-Length envelope.
;;
;; This class keeps the stock `jsonrpc--process-filter' and only re-frames
;; data on the way in: each complete line is re-wrapped as a synthetic
;; Content-Length envelope and handed to the upstream filter.  Framing
;; aside, everything -- buffering, byte accounting, the message queue,
;; deferred dispatch via timers, the bug#60088 reentrancy guard, and
;; events-buffer plumbing -- is inherited unchanged from jsonrpc.el.
;;
;; Only `jsonrpc-connection-send' needs a real override, to emit a bare
;; JSON line instead of an envelope.
;;
;;; Code:

(require 'jsonrpc)
(require 'cl-lib)

;;;###autoload
(defclass jsonrpc-linepipe (jsonrpc-process-connection)
  ()
  :documentation
  "JSONRPC connection over stdio using newline-delimited JSON.
Unlike `jsonrpc-process-connection', this class does not use
Content-Length headers on the wire.  Each JSON-RPC message is sent
as a single line of JSON, and received lines are converted back
into envelopes so that the stock `jsonrpc--process-filter' can do
the parsing, queueing and dispatching.")

(defun jsonrpc-linepipe--filter (proc string)
  "Re-frame newline-delimited JSON in STRING as envelopes for PROC.
STRING may be split anywhere, so incomplete trailing data is kept
in PROC's `linepipe-acc' process property until its newline arrives."
  (let* ((acc (concat (or (process-get proc 'linepipe-acc) "") string))
         (lines (split-string acc "\n")))
    (process-put proc 'linepipe-acc (car (last lines)))
    (dolist (line (butlast lines))
      (let ((line (string-trim line)))
        (unless (string-empty-p line)
          (jsonrpc--process-filter
           proc (format "Content-Length: %d\r\n\r\n%s"
                        (string-bytes line) line)))))))

(cl-defmethod initialize-instance :after ((conn jsonrpc-linepipe) _slots)
  "Install the re-framing process filter on CONN.
This runs after the parent `jsonrpc-process-connection' has
already created the process, stderr buffer and sentinel."
  (let ((proc (jsonrpc--process conn)))
    (process-put proc 'linepipe-acc "")
    (set-process-filter proc #'jsonrpc-linepipe--filter)))

(cl-defmethod jsonrpc-connection-send ((connection jsonrpc-linepipe)
                                       &rest args
                                       &key
                                       id
                                       method
                                       _params
                                       (_result nil result-supplied-p)
                                       error
                                       _partial)
  "Send a JSONRPC message, described by ARGS, to CONNECTION.
The message is written as a single newline-delimited JSON line, in
the format that `jsonrpc-convert-to-endpoint' produces."
  (when method
    ;; Sanitize method into a string, as the parent method does.
    (setq args
          (plist-put args :method
                     (cond ((keywordp method) (substring (symbol-name method) 1))
                           ((symbolp method) (symbol-name method))
                           ((stringp method) method)
                           (t (error "[jsonrpc] invalid method %s" method))))))
  (let* ((kind (cond ((or result-supplied-p error) 'reply)
                     (id 'request)
                     (method 'notification)))
         (converted (jsonrpc-convert-to-endpoint connection args kind))
         (json (jsonrpc--json-encode converted)))
    (process-send-string (jsonrpc--process connection) (concat json "\n"))
    (jsonrpc--event
     connection
     'client
     :json json
     :kind  kind
     :message args
     :foreign-message converted)))

(provide 'jsonrpc-linepipe)
;;; jsonrpc-linepipe.el ends here
