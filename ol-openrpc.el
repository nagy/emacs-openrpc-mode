;;; ol-openrpc.el --- Org mode link to OpenRPC endpoints  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Free Software Foundation, Inc.

;; Author: <your-name>
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (openrpc-mode "0.1.0") (org "9.0"))
;; Keywords: outlines, hypermedia

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This library registers an Org mode link type for OpenRPC
;; endpoints.  Links are written as:
;;
;;     [[openrpc:/path/to/some-binary --flag]]
;;
;; Following such a link calls `openrpc-mode-discover' with the
;; path, launching the connection and displaying the discovered
;; methods in an `openrpc-mode' buffer.
;;
;; Use `C-c C-l' (org-insert-link) to insert one interactively,
;; or `C-c l` (org-store-link) from an `openrpc-mode' buffer to
;; store a link back to that endpoint.
;;
;;; Code:

(require 'ol)   ; org-link-set-parameters, org-store-link-props
(require 'openrpc-mode)

;;;###autoload
(defun openrpc-link-follow (path &optional _)
  "Open an OpenRPC connection to PATH and show the methods buffer.
PATH is a shell command string passed to `openrpc-mode-discover'."
  (openrpc-mode-discover path))

;;;###autoload
(defun openrpc-link-complete (&optional _)
  "Create an openrpc: link, prompting for the command."
  (concat "openrpc:"
          (read-shell-command "OpenRPC command: ")))

;;;###autoload
(defun openrpc-link-store ()
  "Store a link to the current `openrpc-mode' buffer."
  (when (derived-mode-p 'openrpc-mode)
    (let ((cmd openrpc-mode--command))
      (when cmd
        (org-link-store-props
         :type "openrpc"
         :link (concat "openrpc:" cmd)
         :description (format "OpenRPC `%s'" cmd))
        t))))

;;;###autoload
(org-link-set-parameters "openrpc"
  :follow #'openrpc-link-follow
  :complete #'openrpc-link-complete
  :store #'openrpc-link-store)

(provide 'ol-openrpc)

;;; ol-openrpc.el ends here
