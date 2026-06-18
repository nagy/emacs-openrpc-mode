{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  emacs ? pkgs.emacs,
  emacsPackages ? emacs.pkgs,
  melpaBuild ? emacsPackages.melpaBuild,
}:

melpaBuild {
  pname = "openrpc-mode";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  turnCompilationWarningToError = true;

  meta = {
    description = "Major mode for discovering and browsing OpenRPC methods";
    longDescription = ''
      A major mode for discovering and browsing OpenRPC methods
      exposed by JSON-RPC endpoints over stdio.

      The user enters a command string (e.g. "my-cli --stdio") to
      launch a subprocess.  The package communicates with that
      process over stdio using the jsonrpc library's
      jsonrpc-process-connection class, sends an rpc.discover
      request, and displays the discovered methods in a
      tabulated-list-mode derived buffer.
    '';
    license = lib.licenses.agpl3Plus;
    homepage = "https://github.com/yourname/openrpc-mode";
    maintainers = with lib.maintainers; [ nagy ];
    platforms = lib.platforms.unix;
  };
}
