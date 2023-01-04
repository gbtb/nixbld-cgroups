rec {
  description = "Tool for simple resource limiting of nix builds with help of cgroups";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tool-config = {
      url = "path:./config.nix";
      flake = false;
    };
  };

  outputs = inputs@{ flake-parts, tool-config, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # To import a flake module
        # 1. Add foo to inputs
        # 2. Add foo as a parameter to the outputs function
        # 3. Add here: foo.flakeModule

      ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
      perSystem = { config, self', inputs', pkgs, system, ... }:
        with builtins;
        let
          nproc_ = pkgs.runCommandLocal "get-nproc" {} ''
            mkdir $out
            echo $(nproc) > $out/value.nix
          '';
          nproc = import "${nproc_}/value.nix";
          default-config = import tool-config { inherit nproc; };
          profiles = attrNames default-config.profiles;
          profilesJson = pkgs.writeText "nixbld-cgroups-profiles" (
          let preparedProfiles = 
            mapAttrs 
              (name: attrs: 
                let props = mapAttrs (name: value: name + "=" + (toString value)) attrs; in
                concatStringsSep "\n" (attrValues props)
              )
            default-config.profiles;
          in
          toJSON preparedProfiles
          );
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
                  availableProfiles="${builtins.toString profiles}"
                  cat "${profilesJson}"
                  echo "Available profiles: [$availableProfiles]"
                  cpus=""
                  profile=""
                  shopt -s extglob
                  while :; do
                      case $1 in
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
                          -p|--profile)
                            if [[ $2 == +([a-z0-9]) ]]; then
                              profile=$2
                              shift 1;
                            else
                                fail 'ERROR: "--profile" requires a non-empty argument with a name of the profile';
                            fi
                            ;;
                          *)               # Default case: No more options, so break out of the loop.
                              break
                      esac
                      shift
                  done
                echo "CPU: $cpus, Profile: $profile"/
                if [[ "$cpus" != "" ]] && [[ $profile != "" ]]; then
                  error "You can use either profile or the number of cpus as an argument";
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

                if [[ "$profile" != "" ]]; then
                  profileJson=$(jq ."$profile" < ${profilesJson})
                  if [[ "$profileJson" == "null" ]]; then
                    error "Profile with name $profile wasn't configured"
                    exit 1
                  fi
                fi

          '';
          };
        in
        {
          # Per-system attributes can be defined here. The self' and inputs'
          # module parameters provide easy access to attributes of the same
          # system.

          # Equivalent to  inputs'.nixpkgs.legacyPackages.hello;
          apps.default = {
            type = "app";
            program = "${nixbld-cgroups}/bin/nixbld-cgroups";
          };
        };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.
      };
    };
}
