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
        xdg = {clobber}: {
          enable = true;
          cache = {
            home = userHome + "/customCacheHome";
            files = {
              "foo" = {
                text = "Hello world!";
                inherit clobber;
              };
            };
          };
          config = {
            home = userHome + "/customConfigHome";
            files = {
              "bar.json" = {
                generator = lib.generators.toJSON {};
                value = {bar = true;};
                inherit clobber;
              };
            };
          };
          data = {
            home = userHome + "/customDataHome";
            files = {
              "baz.toml" = {
                generator = (pkgs.formats.toml {}).generate "baz.toml";
                value = {baz = true;};
                inherit clobber;
              };
            };
          };
          state = {
            home = userHome + "/customStateHome";
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
          filesGetsLinked.configuration = {
            hjem.users.alice = {
              files.".config/foo".text = "Hello world!";
              xdg = xdg {clobber = false;};
            };
          };

          filesGetsOverwritten.configuration = {
            hjem.users.alice = {
              files.".config/foo" = {
                text = "Hello new world!";
                clobber = true;
              };
              xdg = xdg {clobber = true;};
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

        with subtest("File gets linked"):
          node1.succeed("${specialisations}/filesGetsLinked/bin/switch-to-configuration test")
          node1.succeed("test -L ${userHome}/customCacheHome/foo")
          node1.succeed("test -L ${userHome}/customConfigHome/bar.json")
          node1.succeed("test -L ${userHome}/customDataHome/baz.toml")
          node1.succeed("test -L ${userHome}/customStateHome/foo")
          # Same name as config.home test file to verify proper merging
          node1.succeed("test -L ${userHome}/.config/foo")
          node1.succeed("grep \"Hello world!\" ${userHome}/.config/foo")

        with subtest("File gets overwritten when changed"):
          node1.succeed("${specialisations}/filesGetsLinked/bin/switch-to-configuration test")
          node1.succeed("${specialisations}/filesGetsOverwritten/bin/switch-to-configuration test")
          node1.succeed("test -L ${userHome}/customCacheHome/foo")
          node1.succeed("test -L ${userHome}/customConfigHome/bar.json")
          node1.succeed("test -L ${userHome}/customDataHome/baz.toml")
          node1.succeed("test -L ${userHome}/customStateHome/foo")
          node1.succeed("test -L ${userHome}/.config/foo")
          node1.succeed("grep \"Hello new world!\" ${userHome}/.config/foo")
      '';
  }
