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
  slicesNames = attrNames cfg.slices.available;
  slicesJson = pkgs.writeText "nixbld-cgroups-slices" (
    let
      preparedSlices =
        mapAttrs
          (name: attrs:
            let props = mapAttrs (name: value: name + "=" + (toString value)) attrs; in
            concatStringsSep " " (attrValues props)
          )
          cfg.slices.available;
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
                        stateD="''${XDG_STATE_HOME:-''$HOME/.local/state/nixbld-cgroups}"
                        echo "$stateD"
                        mkdir -p "$stateD"
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
                                --clean-state)
                                  daemonD="/etc/systemd/system.control/nix-daemon.service.d"
                                  echo "Root permissions required to delete slices from $daemonD"
                                  sudo find "$daemonD" -maxdepth 1 -type f -delete
                                  sudo systemctl daemon-reload
                                  rm "$stateD"/*
                                  ;;
                                --previous-slice)
                                  slice=$(cat "$stateD/prev_state")
                                  echo "Enabling previous slice: $slice"
                                  rm "$stateD/prev_state"
                                  ;;
                                -s|--slice)
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
                        cmd="systemctl set-property --runtime nix-daemon.service $sliceJson"
                        $cmd
                        touch "$stateD/current_state"
                        mv "$stateD/current_state" "$stateD/prev_state"
                        echo "$slice" > "$stateD/current_state"
                      fi

    '';
  };
  onStopCmd = if cfg.slices.onScreenSaverStop == "previousSlice" then "--previous-slice" else "--slice ${cfg.slices.onScreenSaverStop}";
  systemdScript = pkgs.writeShellScript "nixbld-dbus-monitor"
    ''dbus-monitor "type='signal',path=/org/freedesktop/ScreenSaver" \
    | sed -u -n -e "s/   boolean true/nixbld-cgroups --slice ${cfg.slices.onScreenSaverStart}/p" \
    -e "s/   boolean false/nixbld-cgroups ${onStopCmd}/p"'';
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
        slices.available = mkOption {
          description = "Definition of systemd slices, available for the nixbld-cgroups tool";
          type = types.attrsOf types.anything;
          default = {
            allCores = { AllowedCPUs = lib.toAllowedCpus (nproc - 1); };
            browsing = { AllowedCPUs = lib.toAllowedCpus (lib.share nproc 0.7); };
            work = { AllowedCPUs = lib.toAllowedCpus (lib.share nproc 0.5); };
            gaming = { AllowedCPUs = lib.toAllowedCpus (lib.share nproc 0.2); };
          };
        };
        slices.onScreenSaverStart = mkOption {
          type = types.enum slicesNames;
          default = builtins.head slicesNames;
          example = "allCores";
          description = "Slice that would be set when ScreenSaver starts";
        };
        slices.onScreenSaverStop = mkOption {
          type = types.enum (["previousSlice"] ++ slicesNames);
          default = "previousSlice";
          description = ''Slice that would be set when screen saver stops. Could be set to a name of one the slices or "previousSlice" to restore whatever slice was active before a start of the screen saver'';
        };
      };
    };
    config = mkIf cfg.enable {
      environment.systemPackages = [ nixbld-cgroups ];
      systemd.user.services.nixbld-dbus-monitor = {
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.dbus nixbld-cgroups ];
        serviceConfig.ExecStart = systemdScript;
      };
    };
  };
}
