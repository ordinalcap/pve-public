# Generic NixOS guest baseline. Platform-specific access policy and network MTU
# are explicit inputs supplied by the private platform handoff.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.pve;
in
{
  options.pve = {
    privateInterface = lib.mkOption {
      type = lib.types.str;
      default = "ens19";
      description = ''
        Guest name of the NIC on the project's private VNet (net1 on a q35 machine).
        DHCP from PVE gives it a stable address; the pushed default route and DNS are
        ignored so the public NIC (net0, ens18) stays the only way out.
      '';
    };

    privateMtu = lib.mkOption {
      type = lib.types.int;
      description = "MTU on the private NIC; must equal the VNet zone MTU from the platform handoff.";
    };

    opsUser = lib.mkOption {
      type = lib.types.str;
      default = "ops";
      description = "Break-glass/deploy account: key-only SSH, passwordless sudo, Nix trusted user.";
    };

    operatorKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Platform operator SSH public keys supplied by the handoff; override for restricted hosts.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "The project's own keys for the ops user, appended to pve.operatorKeys.";
    };

    tailscaleSsh = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Join with `tailscale up --ssh`. Off by default: Tailscale SSH takes over port 22
        for tailnet-sourced connections and answers to the tailnet SSH policy instead of
        authorized_keys, so a policy that denies the operator or the agent locks both
        keys out over MagicDNS. Plain OpenSSH over the tailnet honours the keys regardless.
        Only read at join time: on an already-joined guest run
        `sudo tailscale set --ssh=true` / `--ssh=false` to change it live.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.operatorKeys ++ cfg.authorizedKeys != [ ];
        message = "Supply pve.operatorKeys or pve.authorizedKeys to avoid a guest with no SSH access.";
      }
    ];
    # --- Boot / disk: the layout disk-image.nix produces (label ESP + label nixos, systemd-boot).
    # mkDefault so the image module's identical definitions win without conflict.
    boot.loader.systemd-boot.enable = lib.mkDefault true;
    boot.loader.efi.canTouchEfiVariables = false; # boots from \EFI\BOOT\BOOTX64.EFI; no NVRAM entries needed
    boot.loader.timeout = lib.mkDefault 1;
    boot.growPartition = lib.mkDefault true;
    fileSystems."/" = {
      device = lib.mkDefault "/dev/disk/by-label/nixos";
      fsType = lib.mkDefault "ext4";
      autoResize = lib.mkDefault true;
    };
    fileSystems."/boot" = {
      device = lib.mkDefault "/dev/disk/by-label/ESP";
      fsType = lib.mkDefault "vfat";
    };

    # NixOS only applies networking.hostName at boot (sysctl). The first switch after
    # a clone always renames the host, so apply it live: Tailscale and logs use it.
    system.activationScripts.pve-hostname = lib.mkIf (config.networking.hostName != "") (
      lib.stringAfter [ "etc" ] ''
        echo ${lib.escapeShellArg config.networking.hostName} > /proc/sys/kernel/hostname
      ''
    );
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "sd_mod"
    ];
    boot.kernelParams = [
      "console=tty0"
      "console=ttyS0,115200" # `qm terminal <vmid>` on the host is the break-glass console
    ];

    # --- Proxmox integration
    services.qemuGuest.enable = true;

    # --- Network: DHCP everywhere, but the private NIC never becomes a default route.
    networking.useNetworkd = true;
    networking.useDHCP = false;
    services.resolved.enable = true;
    systemd.network = {
      enable = true;
      networks = {
        "10-private" = {
          matchConfig.Name = cfg.privateInterface;
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
          };
          dhcpV4Config = {
            UseRoutes = false;
            UseGateway = false;
            UseDNS = false;
            UseNTP = false;
            UseDomains = false;
            UseHostname = false;
          };
          linkConfig = {
            RequiredForOnline = "no";
            MTUBytes = toString cfg.privateMtu;
          };
        };
        "20-public" = {
          matchConfig.Name = "en*";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = true;
          };
        };
      };
    };
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      # Project-internal traffic and the tailnet are trusted; the LAN side is not.
      trustedInterfaces = [
        cfg.privateInterface
        "tailscale0"
      ];
    };

    # --- Tailscale: join automatically if a project dropped an auth key at
    # /var/lib/tailscale/authkey (see README.md); the file is consumed.
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "client";
    };
    systemd.services.pve-tailscale-join = {
      description = "Join the tailnet with /var/lib/tailscale/authkey";
      after = [
        "tailscaled.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/var/lib/tailscale/authkey";
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.tailscale
        pkgs.jq
      ];
      # The key file is the only join credential: it is removed only once the
      # backend reports Running. Any other outcome keeps it and fails the unit,
      # so the next boot or `systemctl start pve-tailscale-join` retries.
      script = ''
        state=$(tailscale status --json | jq -r .BackendState)
        case "$state" in
          Running) ;;
          NeedsLogin | NoState | Stopped)
            tailscale up --auth-key file:/var/lib/tailscale/authkey ${lib.optionalString cfg.tailscaleSsh "--ssh"}
            state=$(tailscale status --json | jq -r .BackendState)
            ;;
          *)
            echo "tailscale backend is $state; keeping authkey for a later attempt" >&2
            exit 1
            ;;
        esac
        if [ "$state" != "Running" ]; then
          echo "join did not reach Running (state $state); keeping authkey" >&2
          exit 1
        fi
        rm -f /var/lib/tailscale/authkey
      '';
    };

    # --- Access: one ops account, keys only, no root login, no passwords anywhere.
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    users.mutableUsers = lib.mkDefault false;
    users.users.${cfg.opsUser} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.operatorKeys ++ cfg.authorizedKeys;
    };
    security.sudo.wheelNeedsPassword = false;

    # --- Nix: flakes on; ops can push closures with `nixos-rebuild --target-host ops@… --sudo`.
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        cfg.opsUser
      ];
      auto-optimise-store = true;
    };
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    # --- Baseline tooling; projects add the rest.
    environment.systemPackages = with pkgs; [
      curl
      git
      htop
      jq
      vim
    ];
    documentation.nixos.enable = false;
    time.timeZone = lib.mkDefault "UTC";

    system.stateVersion = lib.mkDefault "26.05";
  };
}
