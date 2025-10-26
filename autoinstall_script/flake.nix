{
  description = "IvorySQL development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Core compiler and build tools
          gcc
          gnumake
          bison
          flex
          pkg-config
          # Dependencies required for building IvorySQL
          readline.dev
          zlib.dev
          openssl.dev
          libxml2.dev
          libxslt
          icu.dev
          libuuid
          gettext
          tcl
          # Python development environment
          python3
          python3Packages.setuptools
          # For running the regression test suite
          perl
          perlPackages.IPCRun
          # Additional utilities
          which
          curl
        ];
      };
    };
}