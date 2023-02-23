# nixbld-cgroups
Simple CLI tool for nixbld (nix-daemon) cgroups resource slicing

## What is it?
This repo contains nixos module which consists of two things - bash CLI tool `nixbld-cgroups` and systemd --user service `nixbld-dbus-monitor`.

### nixbld-cgroups
It allows to dynamically set required cgroups properties on nix-daemon. For a UX simplification, cgroups properties should be pre-configured with module's options

### nixbld-dbus-monitor
It is a systemctl --user service which automates very frequent usecase. When a PC screen is locked (dbus ScreenSaver event is fired) it gives nix-daemon full PC resources,
and when the user unlocks a screen it returns to previous state (slice).

## Motivation
I have my moderately powerfull desktop PC which I use for remote work, nix hacking and gaming. Sometimes those activities do overlap, 
and I have to rebuild cmake, perl, whatever, before nix-build is ready to build my one-line version bump of a package. 
Depending on a parallel activity, I'd like to be able to give a different amount of resources (mostly CPUs) to nix-daemon,
so that my work/game is not crippled by a rebuild. 
Setting nix cores statically in a configuration.nix is to rigid, because I want to dynamically balance between the build speed and usability of my PC.
