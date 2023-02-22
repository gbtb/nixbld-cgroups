{ moduleWithSystem, ... }:
{
  flake.nixosModules.default = moduleWithSystem (
    perSystem@{ pkgs }:
    nixos@{ ... }:
      with pkgs.lib;
      let cfg = config.services.nixbld-dbus-monitor;
      in
      {
        options = {
          services.nixbld-dbus-monitor = {
            enable = mkEnableOption "dbus-monitor watching for ScreenSaver";
            lockscreenProfile = mkOption {
              type = types.enum profiles;
              default = builtins.head profiles;
              example = "";
              description = "";
            };
          };
        };
        config = lib.mkIf cfg.enable {
          systemd.services.nixbld-dbus-monitor = {
            wantedBy = [ "multi-user.target" ];
            path = [ pkgs.dbus pkgs.nix-daemon-cgroups ];
            serviceConfig.ExecStart = ''dbus-monitor "type='signal',path=/org/freedesktop/ScreenSaver" | sed -u -n -e "s/   boolean true/yandex-disk start/p" -e "s/   boolean false/yandex-disk end/p"'';
          };
        };
      }
  );
}
