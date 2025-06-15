{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) literalExpression mkOption;
  inherit (lib.strings) optionalString;
  inherit (lib.trivial) pipe;
  inherit (lib.types) attrs attrsOf listOf raw submoduleWith;
  inherit (lib.meta) getExe;
  inherit (builtins) filter attrValues mapAttrs getAttr concatLists concatStringsSep typeOf toJSON;

  cfg = config.hjem;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  userModule = submoduleWith {
    description = "Hjem user module";
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
          ../common/user.nix
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
  imports = [../common/global.nix];

  options.hjem = {
    users = mkOption {
      default = {};
      type = attrsOf userModule;
      description = "Home configurations to be managed";
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

    extraModules = mkOption {
      type = listOf raw;
      default = [];
      description = ''
        Additional modules to be evaluated as a part of the users module
        inside {option}`config.hjem.users.<name>`. This can be used to
        extend each user configuration with additional options.
      '';
    };
  };
  config = mkMerge [
    {
      users.users = (mapAttrs (_: v: {inherit (v) packages;})) enabledUsers;
    }

    # Constructed rule string that consists of the type, target, and source
    # of a tmpfile. Files with 'null' sources are filtered before the rule
    # is constructed.
    (mkIf (cfg.linker == null) {
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
    })

    (
      mkIf (cfg.linker != null)
      {
        systemd.services.hjem-activate = {
          requiredBy = ["sysinit-reactivation.target"];
          before = ["sysinit-reactivation.target"];
          script = let
            linkerExe = getExe cfg.linker;
            linkerOpts =
              if (typeOf cfg.linkerOptions == "set")
              then ''--linker-opts "${toJSON cfg.linkerOptions}"''
              else concatStringsSep " " cfg.linkerOptions;
          in ''
            mkdir -p /var/lib/hjem

            for manifest in ${cfg.manifests}/*; do
              if [ ! -f /var/lib/hjem/$(basename $manifest) ]; then
                ${linkerExe} ${linkerOpts} activate $manifest
                continue
              fi

              ${linkerExe} ${linkerOpts} diff $manifest /var/lib/hjem/$(basename $manifest)
            done

            cp -rT ${cfg.manifests} /var/lib/hjem
          '';
        };
      }
    )
  ];
}
