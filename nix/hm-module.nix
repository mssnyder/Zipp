{ zipp-client }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.zipp;
in

{
  options.programs.zipp = {
    enable = lib.mkEnableOption "Zipp desktop client";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      description = "URL of the Zipp server (e.g. https://messaging.example.com).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (zipp-client.override { serverUrl = cfg.serverUrl; })
    ];
  };
}
