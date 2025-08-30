{
  description = "High-performance, multiplayer code editor from the creators of Atom and Tree-sitter";
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
    flake-compat.url = "github:edolstra/flake-compat";
    claude-code.url = "github:sadjow/claude-code-nix";
  };
  outputs =
    {
      nixpkgs,
      rust-overlay,
      crane,
      claude-code,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      overlays = [
        rust-overlay.overlays.default
        claude-code.overlays.default
      ]; # Apply both overlays
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system overlays;
              config.allowUnfree = true;
            }
          )
        );
      mkZed =
        pkgs:
        let
          rustBin = rust-overlay.lib.mkRustBin { } pkgs;
        in
        pkgs.callPackage ./nix/build.nix {
          crane = crane.mkLib pkgs;
          rustToolchain = rustBin.fromRustupToolchainFile ./rust-toolchain.toml;
        };
    in
    rec {
      packages = forAllSystems (pkgs: rec {
        default = mkZed pkgs;
        debug = default.override { profile = "dev"; };
        zed-editor = default;
        claude-code = pkgs.claude-code; # Add claude-code package
      });
      devShells = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/shell.nix {
          zed-editor = packages.${pkgs.hostPlatform.system}.default;
        };
      });
      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
      overlays.default = final: _: { zed-editor = mkZed final; };
    };
  nixConfig = {
    extra-substituters = [
      "https://zed.cachix.org"
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };
}
