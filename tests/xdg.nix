let
  userHome = "/home/alice";
in
  (import ./lib) {
    name = "hjem-xdg";
    nodes = {
      node1 = {
        self,
        lib,
        pkgs,
        ...
      }: {
        imports = [self.nixosModules.hjem];

        users.groups.alice = {};
        users.users.alice = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

        hjem.users = {
          alice = {
            enable = true;
            xdg = {
              enable = true;
              cache = {
                home = userHome + "/customCacheHome";
                files = {
                  "foo" = {
                    text = "Hello world!";
                  };
                };
              };
              config = {
                home = userHome + "/customConfigHome";
                files = {
                  "bar.json" = {
                    generator = lib.generators.toJSON {};
                    value = {bar = true;};
                  };
                };
              };
              data = {
                home = userHome + "/customDataHome";
                files = {
                  "baz.toml" = {
                    generator = (pkgs.formats.toml {}).generate "baz.toml";
                    value = {baz = true;};
                  };
                };
              };
              state = {
                home = userHome + "/customStateHome";
                files = {
                  "foo" = {
                    source = pkgs.writeText "file-bar" "Hello World!";
                  };
                };
              };
            };
          };
        };

        # Also test systemd-tmpfiles internally
        systemd.user.tmpfiles = {
          rules = [
            "d %h/user_tmpfiles_created"
          ];

          users.alice.rules = [
            "d %h/only_alice"
          ];
        };
      };
    };

    testScript = ''
      machine.succeed("loginctl enable-linger alice")
      machine.wait_until_succeeds("systemctl --user --machine=alice@ is-active systemd-tmpfiles-setup.service")

      # Test file created by Hjem
      machine.succeed("[ -L ~alice/customCacheHome/foo ]")
      machine.succeed("[ -L ~alice/customConfigHome/bar.json ]")
      machine.succeed("[ -L ~alice/customDataHome/baz.toml ]")
      machine.succeed("[ -L ~alice/customStateHome/foo ]")

      # Test regular files, created by systemd-tmpfiles
      machine.succeed("[ -d ~alice/user_tmpfiles_created ]")
      machine.succeed("[ -d ~alice/only_alice ]")
    '';
  }
