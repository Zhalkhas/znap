{
  description = "virtual environments";

  inputs = {
    devshell.url = "github:numtide/devshell";
    flake-parts.url = "github:hercules-ci/flake-parts";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };
  outputs =
    inputs@{
      self,
      flake-parts,
      devshell,
      nixpkgs,
      zig-overlay,
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        devshell.flakeModule
        inputs.flake-parts.flakeModules.easyOverlay
      ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      perSystem =
        { pkgs, system, ... }:
        {
          packages.default = pkgs.stdenv.mkDerivation {
            pname = "znap";
            version = "0.1.0";

            src = pkgs.lib.cleanSource ./.;

            buildInputs = with pkgs; [
              zig-overlay.packages.${system}."0.15.2"
            ];

            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
              zig build
            '';

            installPhase = ''
              mkdir -p $out/bin
              mv ./zig-out/bin/znap $out/bin/znap
            '';
          };
          
          overlayAttrs = {
            inherit (pkgs) znap;
          };

          devshells.default = ({
            env = [
              {
                name = "DEBUG";
                value = "1";
              }
            ];
            packages = with pkgs; [
              zig-overlay.packages.${system}."0.15.2"
              zls
              socat
            ];
          });
        };
    };
}
