# AGENTS.md

Guidance for AI agents working in this repository. Read before changing code.

## Project

`openrpc-mode` is an Emacs Lisp package for discovering and browsing
[OpenRPC](https://www.open-rpc.org/) methods exposed by JSON-RPC 2.0 endpoints
over stdio. The user supplies a shell command (e.g. `my-cli --stdio`); the
package launches it as a subprocess, sends an `rpc.discover` request through
the built-in `jsonrpc` library, and renders the discovered methods in a
`tabulated-list-mode` buffer.

Targets GNU Emacs >= 31.1 (Emacs 31 bundles jsonrpc 1.0.29, which honours
`:jsonrpc-omit`; 30.2 bundles 1.0.25, which rejects it). License is
AGPL-3.0-or-later in every file. The package is small: four Elisp files, three
transports (Content-Length envelope, plus the raw newline-delimited JSON ones
`jsonrpc-noenvelope` and `jsonrpc-linepipe`), and two persistence integrations
(Emacs bookmarks and Org `openrpc:` links).

## Repository layout

|File                   |Role                                                                                 |
|-----------------------|-------------------------------------------------------------------------------------|
|`openrpc-mode.el`      |Main mode: discover, tabulated list, method detail, bookmarks, shutdown, events log  |
|`jsonrpc-noenvelope.el`|Raw newline-JSON transport that re-parses messages itself (subclass of `jsonrpc-process-connection`)|
|`jsonrpc-linepipe.el`  |Raw newline-JSON transport that re-frames lines and reuses the stock `jsonrpc--process-filter`|
|`ol-openrpc.el`        |Org `openrpc:` link type (follow / complete / store)                                 |
|`test-server.sh`       |Manual fixture: Content-Length envelope transport, single-shot                       |
|`test-server-raw.sh`   |Manual fixture: raw newline-JSON transport, looping, `--ready` mode                  |
|`flake.nix`            |flake-parts packaging: `openrpc-mode` + both `jsonrpc-*` transport packages, devShell, treefmt|
|`flake.lock`           |Pinned flake inputs (nixpkgs, flake-parts, treefmt-nix)                               |
|`README.org`           |User documentation (minimal)                                                         |

## Build and verify

Run from the repository root. Byte-compilation must stay warning-free: the
flake sets `turnCompilationWarningToError = true` on both packages.

```sh
# Byte-compile (fast, verified)
emacs -Q --batch -L . -f batch-byte-compile \
  openrpc-mode.el ol-openrpc.el jsonrpc-noenvelope.el jsonrpc-linepipe.el

# checkdoc (warnings are printed to the message buffer)
emacs -Q --batch -L . --eval '(checkdoc-file "openrpc-mode.el")'

# Build both packages (default = openrpc-mode)
nix build

# Flake checks (formatting) and formatter
nix flake check
nix fmt

# Dev shell comes from `flake.nix` (`nix-shell` and `default.nix`/`shell.nix`
# are gone): `nix develop`

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

- **Three transports, two classes.** Default is the Content-Length envelope
  transport (`jsonrpc-process-connection`). Raw newline-delimited JSON is
  served by either `jsonrpc-noenvelope` (hand-rolled parser) or
  `jsonrpc-linepipe` (re-frames lines, reuses `jsonrpc--process-filter`), still
  selected by prefix argument or the `openrpc-mode-use-envelope` defcustom.
  Prefer `jsonrpc-linepipe`: it is ~30 lines and inherits upstream buffering,
  queueing, dispatch and the bug#60088 reentrancy guard.
- **`jsonrpc-noenvelope` and `jsonrpc-linepipe` are separate packages**,
  declared in `Package-Requires`. The flake builds each as its own derivation
  with a single-file `fileSpecs` (no accidental `*.el` bundling). Treat them as
  standalone: their changes ship independently.
- **Emacs 31.1 floor.** `:jsonrpc-omit` (used for `rpc.discover`) requires
  jsonrpc >= 1.0.29, which Emacs 31 bundles. Do not lower `Package-Requires`
  or point the flake at `pkgs.emacs`/`emacs30`.
- **Flake sources are git-tracked files only.** `lib.cleanSource ./.` sees just
  what git knows, so an untracked `*.el` is invisible to `nix build` (it fails
  with `Missing library "jsonrpc-noenvelope.el" matching package name`). Always
  `git add` new source files before building.
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
`flake.nix` (`lib.licenses.agpl3Plus`), and `README.org` consistent.
