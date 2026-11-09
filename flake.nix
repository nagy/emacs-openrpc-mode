{
  description = "Discover and browse OpenRPC methods over JSON-RPC stdio (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    # Date of the last commit as YYYY-MM-DD, folded into the version
    # string below.  Flake source info gives it as e.g. "20260922133522",
    # so slice out the year, month and day and glue them with hyphens.
    let
      lastModifiedDate = inputs.self.sourceInfo.lastModifiedDate;
      commitDate = "${builtins.substring 0 4 lastModifiedDate}-${
        builtins.substring 4 2 lastModifiedDate
      }-${builtins.substring 6 2 lastModifiedDate}";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Emacs packages are pure Elisp: no ELF binaries, so evaluate on both
      # Linux architectures. nixpkgs carries Emacs and its package set for
      # both.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          # Emacs the package depends on, with the package set that goes
          # with it, so jsonrpc is built against the same Emacs as the
          # package itself.  Emacs 31 is the floor: its bundled jsonrpc
          # honours `:jsonrpc-omit', which 30.2's bundled 1.0.25 rejects.
          emacsPackages = pkgs.emacsPackagesFor pkgs.emacs31;
          inherit (emacsPackages) melpaBuild;

          # Same Elisp sources feed melpaBuild and trivialBuild; keep the
          # source filter in one place so both see identical files.
          src = lib.cleanSource ./.;

          # Version string follows the nixpkgs convention for unreleased
          # sources: <upstream-version>-unstable-<date of last source commit>.
          # Derived from the flake's source info above, so it never goes
          # stale.
          version = "0.1.0-unstable-${commitDate}";

          # jsonrpc transports live in this repo but ship as separate
          # packages (see AGENTS.md). Build them on their own so
          # openrpc-mode can list them under packageRequires as real
          # derivations.  Both are standalone alternatives: pick one class
          # per endpoint, not both at once.
          jsonrpcTransportMeta = description: longDescription: {
            inherit description longDescription;
            license = lib.licenses.agpl3Plus;
            homepage = "https://github.com/nagy/emacs-openrpc-mode";
            maintainers = with lib.maintainers; [ nagy ];
            platforms = lib.platforms.linux;
          };

          jsonrpc-noenvelope = melpaBuild {
            pname = "jsonrpc-noenvelope";
            inherit version src;
            fileSpecs = [ "jsonrpc-noenvelope.el" ];
            packageRequires = [ emacsPackages.jsonrpc ];
            turnCompilationWarningToError = true;
            meta = jsonrpcTransportMeta "JSON-RPC over stdio without the HTTP Content-Length envelope" ''
              A subclass of `jsonrpc-process-connection' for endpoints that
              speak JSON-RPC 2.0 as newline-delimited JSON objects instead
              of the HTTP-style Content-Length framing used by the stock
              jsonrpc library.
            '';
          };

          jsonrpc-linepipe = melpaBuild {
            pname = "jsonrpc-linepipe";
            inherit version src;
            fileSpecs = [ "jsonrpc-linepipe.el" ];
            packageRequires = [ emacsPackages.jsonrpc ];
            turnCompilationWarningToError = true;
            meta = jsonrpcTransportMeta "Newline-framed JSON-RPC reusing the stock jsonrpc process filter" ''
              A subclass of `jsonrpc-process-connection' for endpoints that
              speak JSON-RPC 2.0 as newline-delimited JSON objects.  Unlike
              `jsonrpc-noenvelope', it keeps the stock
              `jsonrpc--process-filter' and re-frames each incoming line as
              a synthetic Content-Length envelope, so buffering, dispatch
              and events logging stay upstream.
            '';
          };

          openrpc-mode = melpaBuild {
            pname = "openrpc-mode";
            inherit version src;

            # jsonrpc comes from nixpkgs; jsonrpc-noenvelope is the local
            # derivation built above, so `require' resolves after install.
            packageRequires = [
              emacsPackages.jsonrpc
              jsonrpc-noenvelope
            ];

            # Byte-compilation warnings fail the build. Keep it on: it is
            # the cheapest lint the package will ever get, and the old
            # default.nix already promoted warnings to errors.
            turnCompilationWarningToError = true;

            meta = {
              description = "Discover and browse OpenRPC methods";
              longDescription = ''
                A major mode for discovering and browsing OpenRPC methods
                exposed by JSON-RPC endpoints over stdio.

                The user enters a command string (e.g. "my-cli --stdio") to
                launch a subprocess. The package communicates with that
                process over stdio using the jsonrpc library's
                jsonrpc-process-connection class, sends an rpc.discover
                request, and displays the discovered methods in a
                tabulated-list-mode derived buffer.

                Endpoints that speak raw newline-delimited JSON instead of
                the Content-Length envelope are supported through the
                bundled jsonrpc-noenvelope class.
              '';
              license = lib.licenses.agpl3Plus;
              homepage = "https://github.com/nagy/emacs-openrpc-mode";
              maintainers = with lib.maintainers; [ nagy ];
              platforms = lib.platforms.linux;
            };
          };

          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            # Emacs Lisp is indentation-sensitive, so no formatter is
            # enabled for *.el: reformatting would churn diffs without a
            # canonical upstream style to match.
          };
        in
        {
          packages = {
            openrpc-mode = openrpc-mode;
            jsonrpc-noenvelope = jsonrpc-noenvelope;
            jsonrpc-linepipe = jsonrpc-linepipe;
            default = openrpc-mode;
          };

          devShells.default = pkgs.mkShell {
            # A real Emacs plus the deps the package requires, so that
            # `emacs -Q -L . -l openrpc-mode.el' works interactively. The
            # local jsonrpc-noenvelope is on the load path too, otherwise
            # `require' fails when hacking on openrpc-mode.el.
            packages = [
              pkgs.emacs31
              emacsPackages.jsonrpc
              jsonrpc-noenvelope
              jsonrpc-linepipe
            ];
          };

          formatter = treefmtEval.config.build.wrapper;
          checks.formatting = treefmtEval.config.build.check inputs.self;
        };
    };
}
