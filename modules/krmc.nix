{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib)
    mkOption
    mkDefault
    types
    ;

  cfg = config.krmc;

  krmcScriptSrc = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/maandr/action-runners/main/gitops/krmc.sh";
    sha256 = "sha256-99TFIujJJOajGj/4v+qg1ceJin+Mn2RtMooDBbfJ2KY=";
  };

  krmc = pkgs.writeShellApplication {
    name = "krmc";
    runtimeInputs = with pkgs; [
      kustomize
      kubeconform
      trivy
      yq
      jq
    ];
    text = builtins.readFile krmcScriptSrc;
    bashOptions = [
      "errexit"
      "pipefail"
    ];
    excludeShellChecks = [
      "SC2046" # = "Quote this to prevent word splitting"
      "SC2221" # = "This pattern always overrides a later one on line"
      "SC2222" # = "This pattern never matches because of a previous pattern on line"
      "SC2004" # = "$/${} is unnecessary on arithmetic variables"
      "SC2206" # = "Quote to prevent word splitting/globbing, or split robustly with mapfile or read -a."
      "SC2059" # = "Don't use variables in the printf format string. Use printf '..%s..' "$foo"."
    ];
    meta = {
      description = "KRMC (Kubernetes Resource Model Checker)";
      license = lib.licenses.mit;
      platforms = lib.platforms.all;
    };
  };

  optionalArg =
    argStr: value: lib.optionalString (value != null && value != "") "--${argStr}=${value}";

  optionalFlag = value: lib.optionalString (value != null) "--${value}";

  optionalListArg =
    argStr: values:
    lib.optionalString (
      values != null && values != [ ]
    ) "--${argStr}=${lib.concatStringsSep "," values}";

  krmc-check = pkgs.writeShellScriptBin "krmc-check" ''
    set -x
    ${lib.getExe krmc} check ${cfg.directory} \
      ${optionalArg "kubernetes-version" cfg.kubernetesVersion} \
      ${optionalListArg "trivy-severity" cfg.trivySeverity} \
      ${optionalArg "trivy-ignorefile" cfg.trivyIgnorefile} \
      ${optionalListArg "kubeconform-skip-resources" cfg.kubeconformSkipResources} \
      ${optionalListArg "kubeconform-ignore-filename-patterns" cfg.kubeconformignoreFilenamePatterns} \
      ${optionalListArg "ignore-dirs" cfg.ignoreDirs} \
      ${optionalFlag cfg.verbosity}
  '';
in
{
  options.krmc = {
    enable = lib.mkEnableOption "KRMC (Kubernetes Resource Model Checker)";

    directory = mkOption {
      type = types.str;
      default = ".";
      description = "Directory to check (default: .)";
    };
    verbosity = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Enable verbose output ('debug' or 'verbose')";
    };
    trivySeverity = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = "Trivy severity levels to fail on";
    };
    trivyIgnorefile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Trivy ignorefile to use (default: DIRECTORY/.trivyignore)";
    };
    kubernetesVersion = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Kubernetes version to check against";
    };
    kubeconformSkipResources = lib.mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = "Kubeconform resources to skip";
    };
    kubeconformignoreFilenamePatterns = lib.mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = "Kubeconform filename patterns to ignore";
    };
    ignoreDirs = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = "Directories to ignore";
    };
  };

  config = lib.mkIf config.krmc.enable {
    krmc.trivyIgnorefile = lib.mkDefault ''${cfg.directory}/.trivyignore'';

    packages = [
      krmc
      krmc-check
      pkgs.kubeconform
    ];
  };
}
