# Linux's package manifest -- the counterpart to manifests/macos/Brewfile on macOS.
#
# The split is the same one documented in manifests/macos/Brewfile and
# packages/common/.config/mise/config.toml, and it does not change per OS: mise owns
# every tool it has a backend for, pinned to an exact version, so both
# machines run the same nvim/rg/gh/tmux/python. What is left over -- the
# things mise has no backend for at all -- has to come from somewhere, and
# on Linux that somewhere is Nix rather than Homebrew.
#
# Why not Homebrew here too: this repository's macOS Homebrew is deliberately
# installed to ~/.homebrew, a non-default prefix, which upstream documents as
# giving up bottles for most formulae ("the default prefix ... is required for
# most bottles to be used"). That trade is worth making on the locked-down
# macOS account, where there is no alternative. On Linux there is one, and it
# is strictly better: flake.lock pins an exact nixpkgs revision, so this file
# plus that lock reproduce byte-identical packages, and rolling back is an
# edit to the lock plus a rebuild -- the same property the mise pins give,
# which Homebrew cannot offer in either prefix.
#
# What belongs here, and only this:
#   1. tools with NO mise backend -- checked with `mise registry <tool>`
#   2. the bootstrap dependencies themselves (stow, mise)
#
# Note that mise IS declared here, unlike on macOS. On macOS mise's own
# version is the one thing nothing pins (documented in the README as an
# accepted gap, since Homebrew cannot pin it). Here flake.lock pins it like
# everything else, so that gap simply does not exist on Linux.
#
# Do NOT add a CLI tool here by reflex: run `mise registry <tool>` first, and
# if it resolves, pin it in packages/common/.config/mise/config.toml instead. Adding it in
# both places would have two managers racing for the same name on PATH.
#
# Lives under manifests/, not in a stow package, per the rule that decides
# which tree anything in this repository belongs in: manifests/<platform>/ is
# applied FROM the repository, packages/<pkg>/ is deployed INTO $HOME. This
# file is read in place by bootstrap.sh and reapply.sh, so it is a manifest.
# It briefly lived inside the stow package and showed up as a stray ~/nix/
# directory next to ~/.nix-profile; manifests/macos/Brewfile had the same
# problem in the other direction, appearing as a pointless ~/Brewfile.
#
# Applied by:
#   ./bootstrap.sh   -- "build the pinned Nix environment" step
#   ./reapply.sh     -- every run, before stow
#
# Both realise this flake to ~/.local/state/dotfiles/nix-env (a symlink into
# the store that doubles as a GC root) and packages/linux/.zprofile.d/45-nix.zsh puts its
# bin/ on PATH. Removing a package is therefore a real prune with no extra
# flag: delete the line, rebuild, and it is gone from PATH, because the
# environment is rebuilt as a whole rather than mutated in place. That is the
# one thing manifests/macos/Brewfile needs `./reapply.sh --prune` for.
#
# To bump the pinned revisions:
#   nix flake update --flake ./nix   # then commit the flake.lock change
{
  description = "Packages for the dev account that mise has no backend for";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # mise, and ONLY mise, comes from unstable. Not a preference for newer
    # software -- everything here is pinned by flake.lock either way, and for
    # stow/git/tree/zsh the stable channel is the better default. mise is
    # different in kind: it ships its tool *registry* (the name -> backend
    # mapping for `herdr`, `codex`, `claude-code` and the rest) inside the
    # binary, so an mise that is a few months old cannot resolve a tool added
    # to the registry since. That is not a cosmetic lag -- it is a hard
    # `mise ERROR <tool> not found in mise tool registry`, which halts
    # bootstrap outright. Stable 26.05 carries mise 2026.5.12, which does not
    # know `herdr`; unstable carries 2026.8.6, which does. Since
    # packages/common/.config/mise/config.toml is shared with macOS, where Homebrew tracks
    # mise's tip, a stale mise here would mean the two machines could not run
    # the same manifest at all.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      # Both are declared so the same lock works on an Apple-silicon Linux VM
      # and on an x86_64 box. Darwin is deliberately absent: on macOS this
      # whole file is inert and manifests/macos/Brewfile is the manifest instead.
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forEachSystem = fn:
        nixpkgs.lib.genAttrs systems
          (system: fn nixpkgs.legacyPackages.${system} nixpkgs-unstable.legacyPackages.${system});
    in
    {
      packages = forEachSystem (pkgs: unstable: {
        # A single derivation whose bin/ is the whole PATH contribution, rather
        # than N separate `nix profile install` entries. That is what makes the
        # manifest declarative: the built environment is exactly this list, so
        # a removed line disappears on the next rebuild instead of lingering
        # until someone remembers to uninstall it.
        default = pkgs.buildEnv {
          name = "dotfiles-dev-env";
          paths = with pkgs; [
            # ---- Bootstrap dependencies ----
            stow # links this package into $HOME
            unstable.mise # installs everything in packages/common/.config/mise/config.toml

            # ---- No mise backend (checked against `mise registry`) ----
            git
            tree
            zsh # the login shell these dotfiles configure
          ];
          # zsh site-functions, man pages and the like, not just bin/.
          extraOutputsToInstall = [ "man" "share" ];
        };
      });
    };
}
