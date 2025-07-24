let
  userHome = "/home/alice";
in
  (import ./lib) {
    name = "hjem-xdg-linker";
    nodes = {
      node1 = {
        self,
        pkgs,
        inputs,
        lib,
        ...
      }: let
        inherit (lib.modules) mkIf;

        xdg = {
          clobber,
          altLocation,
        }: {
          cache = {
            home = mkIf altLocation (userHome + "/customCacheHome");
            files = {
              "foo" = {
                text = "Hello world!";
                inherit clobber;
              };
            };
          };
          config = {
            home = mkIf altLocation (userHome + "/customConfigHome");
            files = {
              "bar.json" = {
                generator = lib.generators.toJSON {};
                value = {bar = true;};
                inherit clobber;
              };
            };
          };
          data = {
            home = mkIf altLocation (userHome + "/customDataHome");
            files = {
              "baz.toml" = {
                generator = (pkgs.formats.toml {}).generate "baz.toml";
                value = {baz = true;};
                inherit clobber;
              };
            };
          };
          state = {
            home = mkIf altLocation (userHome + "/customStateHome");
            files = {
              "foo" = {
                source = pkgs.writeText "file-bar" "Hello World!";
                inherit clobber;
              };
            };
          };
        };
      in {
        imports = [self.nixosModules.hjem];

        system.switch.enable = true;

        users.groups.alice = {};
        users.users.alice = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

        hjem = {
          linker = inputs.smfh.packages.${pkgs.system}.default;
          users = {
            alice = {
              enable = true;
            };
          };
        };

        specialisation = {
          defaultFilesGetLinked.configuration = {
            hjem.users.alice = {
              xdg = xdg {
                clobber = false;
                altLocation = false;
              };
            };
          };
          altFilesGetLinked.configuration = {
            hjem.users.alice = {
              files.".config/foo".text = "Hello world!";
              xdg = xdg {
                clobber = false;
                altLocation = true;
              };
            };
          };

          altFilesGetOverwritten.configuration = {
            hjem.users.alice = {
              files.".config/foo" = {
                text = "Hello new world!";
                clobber = true;
              };
              xdg = xdg {
                clobber = true;
                altLocation = true;
              };
            };
          };
        };
      };
    };

    testScript = {nodes, ...}: let
      baseSystem = nodes.node1.system.build.toplevel;
      specialisations = "${baseSystem}/specialisation";
    in
      # py
      ''
        node1.succeed("loginctl enable-linger alice")

        with subtest("Default file locations get liked"):
          node1.succeed("${specialisations}/defaultFilesGetLinked/bin/switch-to-configuration test")
          node1.succeed("test -L ${userHome}/.cache/foo")
          node1.succeed("test -L ${userHome}/.config/bar.json")
          node1.succeed("test -L ${userHome}/.local/share/baz.toml")
          node1.succeed("test -L ${userHome}/.local/state/foo")

        with subtest("Alternate file locations get linked"):
          node1.succeed("${specialisations}/altFilesGetLinked/bin/switch-to-configuration test")
          node1.succeed("test -L ${userHome}/customCacheHome/foo")
          node1.succeed("test -L ${userHome}/customConfigHome/bar.json")
          node1.succeed("test -L ${userHome}/customDataHome/baz.toml")
          node1.succeed("test -L ${userHome}/customStateHome/foo")
          # Same name as config.home test file to verify proper merging
          node1.succeed("test -L ${userHome}/.config/foo")
          node1.succeed("grep \"Hello world!\" ${userHome}/.config/foo")

        with subtest("Alternate file locations get overwritten when changed"):
          node1.succeed("${specialisations}/altFilesGetLinked/bin/switch-to-configuration test")
          node1.succeed("${specialisations}/altFilesGetOverwritten/bin/switch-to-configuration test")
          node1.succeed("test -L ${userHome}/customCacheHome/foo")
          node1.succeed("test -L ${userHome}/customConfigHome/bar.json")
          node1.succeed("test -L ${userHome}/customDataHome/baz.toml")
          node1.succeed("test -L ${userHome}/customStateHome/foo")
          node1.succeed("test -L ${userHome}/.config/foo")
          node1.succeed("grep \"Hello new world!\" ${userHome}/.config/foo")
      '';
  }
