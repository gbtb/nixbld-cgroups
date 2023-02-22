{ pkgs, lib, config, ... }:
with builtins;
with lib;
let
  #systemdLib = import "${inputs.nixpkgs}/nixos/lib/systemd-lib.nix" { inherit config pkgs; inherit (pkgs) lib; };
  #profiles = systemdLib.sliceToUnit "test" {aliases = null; wantedBy = null; requiredBy = null; enable = true; overrideStrategy = "asDropin"; };
  cfg = config.services.nixbld-dbus-monitor;
  nproc_ = pkgs.runCommandLocal "get-nproc" { } ''
    mkdir $out
    n=$(nproc)
    #echo $((n / 2)) > $out/value.nix
    echo $n > $out/value.nix
  '';
  nproc = import "${nproc_}/value.nix";
  slicesNames = attrNames cfg.slices;
  slicesJson = pkgs.writeText "nixbld-cgroups-slices" (
    let
      preparedSlices =
        mapAttrs
          (name: attrs:
            let props = mapAttrs (name: value: name + "=" + (toString value)) attrs; in
            concatStringsSep " " (attrValues props)
          )
          cfg.slices;
    in
    toJSON preparedSlices
  );
  description = "Tool for simple resource limiting of nix builds with help of cgroups";
  nixbld-cgroups = pkgs.writeShellApplication {
    name = "nixbld-cgroups";
    runtimeInputs = with pkgs; [ jq ];
    text = ''
                error() {
                    echo "$@" 1>&2
                }

                fail() {
                    error "$@"
                    return 1
                }
      show_help() {
            cat << EOF
            Usage: ''${0##*/} [-h] [-f] [executable name]
            ${description}

                -h          display this help and exit
                -f          print only path to /nix/store folder

      EOF
      }
                        availableSlices="${builtins.toString slicesNames}"
                        #cat "${slicesJson}"
                        echo "Available slices: [$availableSlices]"
                        cpus=""
                        slice=""
                        shopt -s extglob
                        while :; do
                            case ''${1-default} in
                                -h|-\?|--help)
                                    show_help    # Display a usage synopsis.
                                    exit
                                    ;;
                                -c|--cpus)
                                  if [[ $2 == +([0-9-]) ]]; then
                                    cpus=$2
                                    shift 1;
                                  else
                                      fail 'ERROR: "--cpus" requires a non-empty argument with number of cpus.';
                                  fi
                                  ;;
                                -p|--slice)
                                  if [[ $2 == +([a-zA-Z0-9]) ]]; then
                                    slice=$2
                                    shift 1;
                                  else
                                      fail 'ERROR: "--slice" requires a non-empty argument with a name of the slice';
                                  fi
                                  ;;
                                *)               # Default case: No more options, so break out of the loop.
                                    break
                            esac
                            shift
                        done
                      echo "CPU: $cpus, Slice: ''${slice:-Not set}"
                      if [[ "$cpus" != "" ]] && [[ $slice != "" ]]; then
                        error "You can use name of the slice or the number of cpus as an argument";
                      fi
                      nproc=$(nproc)
                      if [[ $cpus -ge $nproc ]]; then
                        error "You can't set cpu $cpus to value greater than the number of CPUs available: $nproc"
                        exit 1;
                      fi

                      if [[ "$cpus" != "" ]]; then
                        systemctl set-property nix-daemon.service AllowedCPUs="$cpus"
                        exit 0
                      fi

                      if [[ "$slice" != "" ]]; then
                        sliceJson=$(jq -r ."$slice" < ${slicesJson})
                        if [[ "$sliceJson" == "null" ]]; then
                          error "Slice with the name $slice wasn't configured"
                          exit 1
                        fi

                        echo "${slicesJson}"
                        echo "$sliceJson"
                        a="systemctl set-property --runtime nix-daemon.service $sliceJson"
                        $a
                      fi

    '';
  };
  systemdScript = pkgs.writeShellScript "nixbld-dbus-monitor"
    ''dbus-monitor "type='signal',path=/org/freedesktop/ScreenSaver" | sed -u -n -e "s/   boolean true/yandex-disk start/p" -e "s/   boolean false/yandex-disk end/p"'';
in
rec {
  lib = {
    share = a: b: builtins.floor (a * b);
    toAllowedCpus = x: "0-${toString x}";
  };
  module = {
    options = {
      services.nixbld-dbus-monitor = {
        enable = mkEnableOption "dbus-monitor watching for ScreenSaver";
        slices = mkOption {
          description = "Definition of systemd slices, available for the nixbld-cgroups tool";
          type = types.attrsOf types.anything;
          default = {
            allCores = { AllowedCPUs = lib.toAllowedCpus (nproc - 1); };
            browsing = { AllowedCPUs = lib.toAllowedCpus (lib.share nproc 0.7); };
            work = { AllowedCPUs = lib.toAllowedCpus (lib.share nproc 0.5); };
            gaming = { AllowedCPUs = lib.toAllowedCpus (lib.share nproc 0.2); };
          };
        };
        lockscreenProfile = mkOption {
          type = types.enum (attrNames cfg.slices);
          default = builtins.head (attrNames cfg.slices);
          example = "";
          description = "";
        };
      };
    };
    config = mkIf cfg.enable {
      environment.systemPackages = [ nixbld-cgroups ];
      systemd.user.services.nixbld-dbus-monitor = {
        wantedBy = [ "multi-user.target" ];
        #environment = { DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" };
        path = [ pkgs.dbus nixbld-cgroups ];
        serviceConfig.ExecStart = systemdScript;
      };
    };
  };
}
