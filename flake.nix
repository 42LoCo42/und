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

                info "Downloading kexec tarball"
                (set -x; ssh -t "${preConn}" curl -fLOz "$(basename "${kexec}")" "${kexec}")

                info "Unpacking kexec tarbarll"
                (set -x; ssh -t "${preConn}" tar xvf "$(basename "${kexec}")")

                info "Running kexec"
                (set -x; ssh -t "${preConn}" sudo ./kexec/run)

                info "Waiting for machine to reboot"
                sleep 5
                while sleep 5; do
                  (set -x; ssh -o ConnectTimeout=5 "${kexecConn}" test -f /etc/NIXOS) && break || true
                  echo "Still waiting"
                done

                info "Uploading flake..."
                (set -x; nix copy "${self}" --to "ssh://${kexecConn}")

                info "Formatting disks"
                (set -x; ssh -t "${kexecConn}" ${nix} run disko -- -m disko -f "${self}#${name}")

                info "Installing the system"
                (set -x; ssh -t "${kexecConn}" nixos-install -v \
                  --no-channel-copy \
                  --no-root-password \
                  --flake "${self}#${name}")
              ''}";
            };
            "${name}" = {
              type = "app";
              program = "${pkgs.writeShellScript "${name}" ''
                set -e
                info() { echo "[32;1m$*[m"; }
                info "Updating ${name} on ${conn}"

                info "Uploading flake..."
                (set -x; nix copy "${self}" --to "ssh://${conn}")

                info "Building configuration..."
                (set -x; ssh -t "${conn}" sudo nixos-rebuild switch -L --flake "${self}")
              ''}";
            };
          };
        }))
      builtins.listToAttrs
    ];
  };
}
