{
  description = "Mangaki flake";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs = { type = "github"; owner = "NixOS"; repo = "nixpkgs"; ref = "nixos-20.03"; };

  # Unstable tools.
  inputs.poetry2nix = { type = "github"; owner = "nix-community"; repo = "poetry2nix"; };

  # Upstream source tree(s).
  inputs.mangaki-src = { type = "github"; owner = "mangaki"; repo = "mangaki"; flake = false; };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      # Generate a user-friendly version numer.
      versions =
        let
          generateVersion = builtins.substring 0 8;
        in
        nixpkgs.lib.genAttrs
          [ "mangaki" ]
          (n: generateVersion inputs."${n}-src".lastModifiedDate);

      # System types to support.
      supportedSystems = [ "x86_64-linux" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });

    in
    {

      # A Nixpkgs overlay.
      overlay = final: prev:
        with final;
        {

          # Tools

          inherit (inputs.poetry2nix.packages.${system})
            poetry poetry2nix;

          # Packages

          mangaki = callPackage ./pkgs/mangaki { } {
            src = inputs.mangaki-src;
          };

          mangaki-env = callPackage ./pkgs/mangaki/env.nix { } {
            src = inputs.mangaki-src;
          };

        };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system})
            mangaki;
        });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.mangaki);

      # A NixOS module, if applicable (e.g. if the package provides a system service).
      nixosModules.mangaki = import ./modules/mangaki.nix;

      # NixOS system configuration, if applicable
      nixosConfigurations.mangaki = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux"; # Hardcoded
        modules = [
          # VM-specific configuration
          ({ modulesPath, pkgs, ... }: {
            imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
            virtualisation.qemu.options = [ "-m 2G" "-vga virtio" ];
            environment.systemPackages = with pkgs; [ st unzip ripgrep chromium ];

            networking.hostName = "qemu_virtual";
            networking.networkmanager.enable = true;

            services.xserver.enable = true;
            services.xserver.layout = "us";
            services.xserver.windowManager.i3.enable = true;
            services.xserver.displayManager.lightdm.enable = true;

            users.mutableUsers = false;
            users.users.user = {
              password = "user"; # yes, very secure, I know
              createHome = true;
              isNormalUser = true;
              extraGroups = [ "wheel" ];
            };
          })

          # Flake specific support
          ({ ... }: {
            imports = [
              self.nixosModules.mangaki
            ];

            nixpkgs.overlays = [ self.overlay ];
          })

          # Mangaki configuration
          ({ ... }: {
            security.sudo.enable = true;
            services.mangaki.enable = true;
          })
        ];
      };

      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems (system: self.packages.${system} // {
        # Additional tests, if applicable.
        test =
          with nixpkgsFor.${system};
          stdenv.mkDerivation {
            name = "hello-test-${version}";

            buildInputs = [ hello ];

            unpackPhase = "true";

            buildPhase = ''
              echo 'running some integration tests'
              [[ $(hello) = 'Hello, world!' ]]
            '';

            installPhase = "mkdir -p $out";
          };

        # A VM test of the NixOS module.
        vmTest =
          with import (nixpkgs + "/nixos/lib/testing-python.nix")
            {
              inherit system;
            };

          makeTest {
            nodes = {
              client = { ... }: {
                imports = [ self.nixosModules.hello ];
              };
            };

            testScript =
              ''
                start_all()
                client.wait_for_unit("multi-user.target")
                client.succeed("hello")
              '';
          };
      });

    };
}
