{
  config,
  lib,
  ...
}: let
  inherit (builtins) isList;
  inherit (lib.options) mkOption;
  inherit (lib.types) attrsOf listOf oneOf int path str;
  inherit (lib.attrsets) mapAttrsToList;
  inherit (lib.strings) concatStringsSep;

  cfg = config.environment;

  toString = env:
    if isList env
    then concatStringsSep ":" env
    else builtins.toString env;

  toConf = attrs:
    concatStringsSep "\n"
    (mapAttrsToList (name: value: "export ${name}=\"${toString value}\"") attrs);
in {
  options.environment = {
    variables = mkOption {
      default = {};
      example = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
      description = ''
        A set of environment variables used in the user environment.
        These variables will be set as systemd environment
        variables, using `environment.d`. The value of each
        variable can be either a string or a list of strings. The
        latter is concatenated, interspersed with colon
        characters.
      '';
      type = attrsOf (oneOf [(listOf (oneOf [int str path])) int str path]);
    };
  };

  config = {
    files.".profile".text = toConf cfg.variables;
  };
}
