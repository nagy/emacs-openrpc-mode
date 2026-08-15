# AGENTS.md

Guidance for AI agents working in this repository. Read before changing code.

## Project

`openrpc-mode` is an Emacs Lisp package for discovering and browsing
[OpenRPC](https://www.open-rpc.org/) methods exposed by JSON-RPC 2.0 endpoints
over stdio. The user supplies a shell command (e.g. `my-cli --stdio`); the
package launches it as a subprocess, sends an `rpc.discover` request through
the built-in `jsonrpc` library, and renders the discovered methods in a
`tabulated-list-mode` buffer.

Targets GNU Emacs >= 30.1. License is AGPL-3.0-or-later in every file. The
package is small: three Elisp files, two transports (Content-Length envelope
and raw newline-delimited JSON), and two persistence integrations (Emacs
bookmarks and Org `openrpc:` links).

## Repository layout

|File                   |Role                                                                                 |
|-----------------------|-------------------------------------------------------------------------------------|
|`openrpc-mode.el`      |Main mode: discover, tabulated list, method detail, bookmarks, shutdown, events log  |
|`jsonrpc-noenvelope.el`|Raw newline-delimited-JSON transport (EIEIO subclass of `jsonrpc-process-connection`)|
|`ol-openrpc.el`        |Org `openrpc:` link type (follow / complete / store)                                 |
|`test-server.sh`       |Manual fixture: Content-Length envelope transport, single-shot                       |
|`test-server-raw.sh`   |Manual fixture: raw newline-JSON transport, looping, `--ready` mode                  |
|`default.nix`          |`melpaBuild` packaging; warnings promoted to errors                                  |
|`shell.nix`            |Dev shell; builds `jsonrpc-noenvelope` as a separate package                         |
|`README.org`           |User documentation (minimal)                                                         |

## Build and verify

Run from the repository root. Byte-compilation must stay warning-free:
`default.nix` sets `turnCompilationWarningToError = true`.

```sh
# Byte-compile (fast, verified)
emacs -Q --batch -L . -f batch-byte-compile \
  openrpc-mode.el ol-openrpc.el jsonrpc-noenvelope.el

# checkdoc (warnings are printed to the message buffer)
emacs -Q --batch -L . --eval '(checkdoc-file "openrpc-mode.el")'

# Build the MELPA-style package
nix-build default.nix

# Dev shell (or `nix develop` when the nix-command feature is enabled)
nix-shell shell.nix
```

There is **no automated test suite yet**. Do not invoke a test runner that does
not exist. Manual smoke tests use the fixture servers:

- Envelope transport: `M-x openrpc-mode-discover` -> `./test-server.sh`
- Raw transport: `C-u M-x openrpc-mode-discover` -> `./test-server-raw.sh`

`test-server-raw.sh --ready` additionally emits a `ready` notification before
answering `rpc.discover`.

## Code conventions

- Emacs Lisp with `lexical-binding: t` in every file (first line).
- Every `.el` file keeps the AGPL-3.0-or-later header with real author and
  copyright. Do not change the license.
- Docstrings are checkdoc-clean: first line is a complete sentence, all
  arguments are mentioned (`ARGS`, `PATH`, ...).
- `;;;###autoload` goes only on public entry points. Never on internal
  `-`-prefixed functions. There is currently one stray autoload on
  `openrpc-mode--find-buffer` — do not replicate that pattern.
- `defcustom` options use `:group 'openrpc-mode`; risky values (e.g. the
  transport toggle) declare a `:safe` predicate.
- Reuse existing patterns: EIEIO subclassing via `cl-defmethod`, derived
  `tabulated-list-mode` mode, async `jsonrpc-async-request` with distinct
  success/error/timeout handlers.

## Critical constraints

- **Two transports.** Default is the Content-Length envelope transport
  (`jsonrpc-process-connection`). Raw newline-delimited JSON uses
  `jsonrpc-noenvelope`, selected by prefix argument or the
  `openrpc-mode-use-envelope` defcustom. Never assume one transport.
- **`jsonrpc-noenvelope` is a separate package**, declared in
  `Package-Requires`, not vendored into `openrpc-mode.el`. However,
  `default.nix` currently bundles it by accident (`fileSpecs` default of
  `*.el`). Treat it as standalone: its changes ship independently.
- **Known lifecycle bug: multi-connection clobbering.** Multiple connections
  currently clobber one shared results buffer and can leak or duplicate
  subprocesses. This is a known, analyzed defect, not a design to preserve.
  Each connection should get its own results buffer with correct reuse and
  shutdown semantics.
- **Shell execution.** Commands are run via `sh -c` (`make-process`), not an
  argv array. `openrpc-link-follow` and the bookmark handler execute commands
  from non-interactive contexts without confirmation. If you touch
  link/bookmark paths, keep that security model in mind.
- **Warnings are errors** in the nix build. Any new byte-compile or checkdoc
  warning fails packaging.

## License

AGPL-3.0-or-later (`LICENSE` is the AGPLv3 text). Keep all file headers,
`default.nix` (`lib.licenses.agpl3Plus`), and `README.org` consistent.
