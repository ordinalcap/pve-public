# pve-public

Versioned, public interface between a Proxmox platform and independent project repositories. This repository contains executable modules, not the private control plane. It has no dependency on a platform checkout, a particular project, or platform credentials.

## Ownership

- The private platform owns hosts, network isolation, storage policy, project pools/identities/ACLs, and image publication.
- A project owns its VM declarations, guest services, application code, and runtime secrets. Infrastructure and application code can stay in one repository.
- This repository owns the generic VM module, NixOS guest baseline, and versioned request/handoff shapes. Site configuration and operator access policy are explicit inputs.

## Contract v1

`schemas/project-v1.json` validates a project's JSON or YAML request. The platform still authorizes allocation and enforces cross-project constraints; schema validation is not permission or quota enforcement.

`schemas/handoff-v1.json` validates the nonsecret platform response. It includes endpoint, node, pool/user, template VMID, authorized storage/network identifiers, VMID range, MTU, and operator SSH public keys. It must never contain tokens, private keys, or passwords. Keep real handoffs in the private consuming repository, not here. The optional development-host attachment request is named `codelab` for compatibility with existing platform manifests.

The examples are synthetic. The example SSH public key is not a usable access identity; supply your platform's authorized keys for real guests. The template VMID identifies a platform resource, not an immutable image digest: a Git pin does not pin the contents of a template rebuilt in place. Coordinate template publication separately from module upgrades.

Validate a request or handoff without access to the private platform:

```sh
nix run github:ordinalcap/pve-public/v1.0.0#contract-check -- request project.yaml
nix run github:ordinalcap/pve-public/v1.0.0#contract-check -- handoff platform.json
```

## OpenTofu

Source `git::https://github.com/ordinalcap/pve-public.git//modules/vm?ref=v1.0.0`; pin an exact commit in production consumers. Required platform inputs are `node`, `template_vmid`, `pool`, `storage`, `ssd_storages`, `public_bridge` and `private_mtu`. The project supplies `name`, `vm_id`, `cores` and `memory_mib`, and optionally its `private_vnet` and disks. Input descriptions in `modules/vm/variables.tf` define the remaining options.

The resource address remains `proxmox_virtual_environment_vm.this`. Keep consuming module names unchanged when migrating an existing deployment. The module does not configure provider credentials: the caller supplies an environment-only scoped API token during authorized plan/apply, not in HCL or the handoff.

Data disks inherit the OS datastore unless overridden. SSD emulation comes from the explicit `ssd_storages` list, never a datastore naming convention. Data-bearing VMs default to protection; clear it explicitly before an intentional removal. Disk entries are append-only, and guest filesystem expansion is separate. CPU/memory changes may reboot a VM. Existing clones ignore template input changes to avoid replacing machines during a module update.

## NixOS

Import `pve-public.nixosModules.guest` from the root flake, following its pinned nixpkgs. Set `pve.privateMtu` to the handoff MTU and `pve.operatorKeys` to the platform access policy (consumers can use `lib.mkDefault` to permit explicit per-host overrides). Add project keys through `pve.authorizedKeys`. Evaluation refuses a guest with neither key list populated.

The baseline supplies the EFI boot/disk shape, guest agent, key-only ops access, DHCP, private-network routing policy, Tailscale tooling and ordinary host utilities. Projects add services and data mounts. It trusts the private interface and Tailscale interface in the guest firewall; the platform must enforce isolation between projects. This does not establish production or signer isolation by itself.

For Tailscale enrollment, an authorized deployer delivers the auth key to `/var/lib/tailscale/authkey` through a secret-safe channel; `pve-tailscale-join` consumes it after successful enrollment. No auth key belongs in Nix configuration or the store.

## Validation and releases

With Nix installed, `mise install && mise run check` runs OpenTofu formatting/validation, mocked plan tests, schema acceptance/rejection checks, and builds a representative guest. CI runs on every branch and pull request with read-only checkout permissions, no platform/application secrets, and SHA-pinned actions. No test applies resources or calls a live Proxmox API.

Release process: change and validate the public package in a worktree, review the integrated producer/consumer compatibility, merge green CI, and tag the reviewed commit. Consumers upgrade both OpenTofu and Nix pins together through reviewed changes. Breaking module or schema changes require a major release and an explicit migration. Keep old immutable release tags available; do not retarget them. New schema versions use new files rather than changing the meaning of v1. Check each public change for host details, keys and private source imports before publishing.

A consumer acceptance check starts from a clean checkout without private-platform Git or API credentials: OpenTofu backend-disabled init/validate, Nix contract evaluation, and guest builds must succeed. Privileged lifecycle qualification and production deployment are separate, explicitly authorized operations.
