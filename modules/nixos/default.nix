{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.modules) mkIf;
  inherit (lib.options) mkOption literalExpression;
  inherit (lib.trivial) pipe;
  inherit (lib.strings) optionalString;
  inherit (lib.attrsets) mapAttrsToList;
  inherit (lib.types) bool attrsOf submoduleWith listOf raw attrs submodule;
  inherit (builtins) filter attrValues mapAttrs getAttr concatLists;

  cfg = config.hjem;
  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  hjemModule = submoduleWith {
    description = "Hjem NixOS module";
    class = "hjem";
    specialArgs =
      cfg.specialArgs
      // {
        inherit pkgs;
        osConfig = config;
      };
    modules =
      concatLists
      [
        [
          ../common.nix
          ({name, ...}: let
            user = getAttr name config.users.users;
          in {
            user = user.name;
            directory = user.home;
            clobberFiles = cfg.clobberByDefault;
          })
        ]
        # Evaluate additional modules under 'hjem.users.<name>' so that
        # module systems built on Hjem are more ergonomic.
        cfg.extraModules
      ];
  };
in {
  options.hjem = {
    clobberByDefault = mkOption {
      type = bool;
      default = false;
      description = ''
        The default override behaviour for files managed by Hjem.

        While `true`, existing files will be overriden with new files on rebuild.
        The behaviour may be modified per-user by setting {option}`hjem.users.<name>.clobberFiles`
        to the desired value.
      '';
    };

    users = mkOption {
      default = {};
      type = attrsOf hjemModule;
      description = "Home configurations to be managed";
    };

    extraModules = mkOption {
      type = listOf raw;
      default = [];
      description = ''
        Additional modules to be evaluated as a part of the users module
        inside {option}`config.hjem.users.<name>`. This can be used to
        extend each user configuration with additional options.
      '';
    };

    specialArgs = mkOption {
      type = attrs;
      default = {};
      example = literalExpression "{ inherit inputs; }";
      description = ''
        Additional `specialArgs` are passed to Hjem, allowing extra arguments
        to be passed down to to all imported modules.
      '';
    };
  };

  config = {
    users.users = (mapAttrs (_: v: {inherit (v) packages;})) enabledUsers;

    # Constructed rule string that consists of the type, target, and source
    # of a tmpfile. Files with 'null' sources are filtered before the rule
    # is constructed.
    systemd.user.tmpfiles.users =
      mapAttrs (_: u: {
        rules = pipe u.files [
          attrValues
          (filter (f: f.enable && f.source != null))
          (map (
            file:
            # L+ will recreate, i.e., clobber existing files.
            "L${optionalString file.clobber "+"} '${file.target}' - - - - ${file.source}"
          ))
        ];
      })
      enabledUsers;

    warnings =
      concatLists
      (mapAttrsToList (
          user: v:
            map (
              warning: "${user} profile: ${warning}"
            )
            v.warnings
        )
        enabledUsers);

    assertions =
      concatLists
      (mapAttrsToList (user: config:
        map ({
          assertion,
          message,
          ...
        }: {
          inherit assertion;
          message = "${user} profile: ${message}";
        })
        config.assertions)
      enabledUsers);
  };
}
