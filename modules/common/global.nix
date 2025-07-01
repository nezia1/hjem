{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.options) mkOption;
  inherit (lib.types) nullOr bool listOf package either singleLineStr attrs path;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  manifests = let
    mapFiles = _: files:
      lib.attrsets.foldlAttrs (
        accum: _: value:
          if value.enable -> value.source == null
          then accum
          else
            accum
            ++ lib.singleton {
              type = "symlink";
              inherit (value) source target;
            }
      ) []
      files;

    writeManifest = username: let
      name = "manifest-${username}.json";
    in
      pkgs.writeTextFile {
        inherit name;
        destination = "/${name}";
        text = builtins.toJSON {
          clobber_by_default = cfg.users."${username}".clobberFiles;
          version = 1;
          files = mapFiles username cfg.users."${username}".files;
        };
        checkPhase = ''
          set -e
          CUE_CACHE_DIR=$(pwd)/.cache
          CUE_CONFIG_DIR=$(pwd)/.config

          ${lib.getExe pkgs.cue} vet -c ${../../manifest/v1.cue} $target
        '';
      };
  in
    pkgs.symlinkJoin
    {
      name = "hjem-manifests";
      paths = map writeManifest (builtins.attrNames enabledUsers);
    };

  cfg = config.hjem;
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
    linker = mkOption {
      default = null;
      description = ''
        Method to use to link files.

        `null` will use `systemd-tmpfiles`, which is only supported on Linux.

        This is the default file linker on Linux, as it is the more mature
        linker, but it has the downside of leaving behind symlinks that may
        not get invalidated until the next GC, if an entry is removed from
        {option}`hjem.<user>.files`.

        Specifying a package will use a custom file linker that uses an
        internally-generated manifest. The custom file linker must use this
        manifest to create or remove links as needed, by comparing the manifest
        of the currently activated system with that of the new system.
        This prevents dangling symlinks when an entry is removed from
        {option}`hjem.<user>.files`.

        :::{.note}
        This linker is currently experimental; once it matures, it may become
        the default in the future.
        :::
      '';
      type = nullOr package;
    };

    linkerOptions = mkOption {
      default = [];
      description = ''
        Additional arguments to pass to the linker.

        This is for external linker modules to set, to allow extending the default set of hjem behaviours.
        It accepts either a list of strings, which will be passed directly as arguments, or an attribute set, which will be
        serialized to JSON and passed as `--linker-opts options.json`.
      '';
      type = either (listOf singleLineStr) attrs;
    };

    manifests = mkOption {
      type = path;
      default = manifests;
      readOnly = true;
      description = ''
        Path to the derivation containing all currently built manifests.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.linker == null -> pkgs.stdenv.hostPlatform.isLinux;
        message = "The systemd-tmpfiles linker is only supported on Linux; on other platforms, use the manifest linker.";
      }
    ];
  };
}
