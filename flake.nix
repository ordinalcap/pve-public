{
  description = "Portable Proxmox project interface: VM module, NixOS baseline, and versioned contracts";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      example = builtins.fromJSON (builtins.readFile ./examples/handoff.json);
      contractCheck = pkgs.writeShellApplication {
        name = "pve-contract";
        runtimeInputs = [ pkgs.check-jsonschema ];
        text = ''
          if [[ $# != 2 ]]; then
            echo "usage: pve-contract request|handoff FILE" >&2
            exit 2
          fi
          case "$1" in
            request) schema=${./schemas/project-v1.json} ;;
            handoff) schema=${./schemas/handoff-v1.json} ;;
            *) echo "expected request or handoff" >&2; exit 2 ;;
          esac
          exec check-jsonschema --schemafile "$schema" "$2"
        '';
      };
      guest = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.guest
          {
            networking.hostName = "example-guest";
            pve.operatorKeys = example.operator_keys;
            pve.privateMtu = example.private_mtu;
          }
        ];
      };
    in
    {
      nixosModules.guest = import ./nix/guest.nix;
      packages.${system}.contract-check = contractCheck;
      formatter.${system} = pkgs.nixfmt;
      checks.${system} = {
        guest = guest.config.system.build.toplevel;
        contracts =
          pkgs.runCommand "pve-contract-examples"
            {
              nativeBuildInputs = [
                contractCheck
                pkgs.jq
              ];
            }
            ''
              pve-contract request ${./examples/project.json}
              pve-contract handoff ${./examples/handoff.json}
              jq '. + {api_token: "not-a-secret"}' ${./examples/handoff.json} > forbidden.json
              if pve-contract handoff forbidden.json; then
                echo "handoff accepted credential-bearing metadata" >&2; exit 1
              fi
              jq '.schema_version = 2' ${./examples/handoff.json} > future.json
              if pve-contract handoff future.json; then
                echo "unknown contract version accepted" >&2; exit 1
              fi
              touch "$out"
            '';
      };
    };
}
