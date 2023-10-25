{
  outputs = { ... }: {
    und = self: self.inputs.nixpkgs.lib.pipe self.nixosConfigurations [
      builtins.attrNames
      (builtins.filter (name: self.nixosConfigurations.${name} ? _module.args.und))
      (map (name:
        let
          conf = self.nixosConfigurations.${name};
          pkgs = conf.pkgs;
          args = conf._module.args.und;

          kexec = args.kexec or "https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-${pkgs.system}.tar.gz";

          preConn = "${args.preUser or args.user}@${args.host}";
          kexecConn = "root@${args.host}";
          conn = "${args.user}@${args.host}";

          nix = ''nix --extra-experimental-features "'nix-command flakes'"'';
        in
        {
          name = pkgs.system;
          value = {
            "${name}-install" = {
              type = "app";
              program = "${pkgs.writeShellScript "${name}-install" ''
                set -e
                info() { echo "[32;1m$*[m"; }
                info "Installing ${name} on ${preConn}"

                info "Processing options"
                while (($#)); do
                  case "$1" in
                    --no-format)   NO_FORMAT=1;;
                    --no-kexec)    NO_KEXEC=1;;
                    --no-reboot)   NO_REBOOT=1;;
                    --save-hwconf) shift; SAVE_HWCONF="$1";;
                  esac
                  shift
                done

                ((NO_KEXEC)) || {
                  info "Placing marker file"
                  file="$(mktemp -p /dev/shm -t und.XXXXXXXX)"
                  (set -x; ssh -t "${preConn}" touch "$file")

                  info "Downloading kexec tarball"
                  (set -x; ssh -t "${preConn}" curl -fLOz "$(basename "${kexec}")" "${kexec}")

                  info "Unpacking kexec tarbarll"
                  (set -x; ssh -t "${preConn}" tar xvf "$(basename "${kexec}")")

                  info "Running kexec"
                  (set -x; ssh -t "${preConn}" sudo ./kexec/run)

                  info "Waiting for machine to reboot"
                  while sleep 5; do
                    (set -x; ssh -o ConnectTimeout=5 "${kexecConn}" test ! -f "$file") && break || true
                    info "Still waiting"
                  done
                }

                [ -n "$SAVE_HWCONF" ] && {
                  info "Saving hardware configuration to $SAVE_HWCONF"
                  (set -x; ssh "${kexecConn}" nixos-generate-config \
                    --show-hardware-config \
                    --no-filesystems \
                  | tee "$SAVE_HWCONF")

                  info "You can now edit the hardware configuration!"
                  read -p "[33;1mPress ENTER when done"
                }

                info "Uploading flake"
                (set -x; nix copy "${self}" --to "ssh://${kexecConn}")

                ((NO_FORMAT)) || {
                  info "Formatting disks"
                  (set -x; ssh -t "${kexecConn}" ${nix} run disko -- -m disko -f "${self}#${name}")
                }

                info "Installing the system"
                (set -x; ssh -t "${kexecConn}" nixos-install -v \
                  --no-channel-copy \
                  --no-root-password \
                  --flake "${self}#${name}")

                info "Exporting all ZFS pools"
                (set -x; ssh -t "${kexecConn}" zpool export -a)

                ((NO_REBOOT)) || {
                  info "Rebooting"
                  (set -x; ssh -t "${kexecConn}" reboot)
                }
              ''}";
            };
            "${name}" = {
              type = "app";
              program = "${pkgs.writeShellScript "${name}" ''
                set -e
                info() { echo "[32;1m$*[m"; }
                info "Updating ${name} on ${conn}"

                info "Uploading flake"
                (set -x; nix copy "${self}" --to "ssh://${conn}")

                info "Building configuration"
                (set -x; ssh -t "${conn}" sudo nixos-rebuild switch -L --flake "${self}")
              ''}";
            };
          };
        }))
      builtins.listToAttrs
    ];
  };
}
