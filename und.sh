#!/usr/bin/env bash
set -e

# import variables from nix

flake="@flake@"
name="@name@"
config="$flake#$name"

user="@user@"
host="@host@"
preUser="@preUser@"
kexec="@kexec@"

ssh="@ssh@"

info() {
	echo "[32;1m$*[m"
}

x() { (
	set -x
	"$@"
); }

info "Processing options"
while (($#)); do
	case "$1" in
	-u | --user)
		shift
		user="$1"
		;;
	-h | --host)
		shift
		host="$1"
		;;

	-p | --preUser)
		shift
		preUser="$1"
		;;
	-k | --kexec)
		shift
		kexec="$1"
		;;

	-l | --local) LOCAL=1 ;;
	-i | --install) INSTALL=1 ;;

	--no-format) NO_FORMAT=1 ;;
	--no-kexec) NO_KEXEC=1 ;;
	--no-reboot) NO_REBOOT=1 ;;

	--save-hwconf)
		shift
		SAVE_HWCONF="$1"
		;;
	esac
	shift
done

preConn="$preUser@$host"
kexecConn="root@$host"
conn="$user@$host"

main() {
	if ((INSTALL)); then
		if ((LOCAL)); then
			info "Installing $name locally"
		else
			info "Installing $name on $preConn"
			runKexec
			saveHWConf
			uploadFlake
			formatDisks
			runInstallation
		fi
	else
		if ((LOCAL)); then
			info "Updating $name locally"
		else
			info "Updating $name on $conn"
			uploadFlake

			info "Building configuration"
			x "$ssh" -t "$conn" sudo nixos-rebuild switch -L --flake "$flake"
		fi
	fi
}

runKexec() {
	((NO_KEXEC)) && return

	info "Placing marker file"
	file="$(mktemp -p /dev/shm -t und.XXXXXXXX)"
	x "$ssh" -t "$preConn" touch "$file"

	info "Downloading kexec tarball"
	x "$ssh" -t "$preConn" curl -fLOz "$(basename "$kexec")" "$kexec"

	info "Unpacking kexec tarbarll"
	x "$ssh" -t "$preConn" tar xvf "$(basename "${kexec}")"

	info "Running kexec"
	x "$ssh" -t "$preConn" sudo ./kexec/run

	info "Waiting for machine to reboot"
	while sleep 5; do
		if x "$ssh" -o ConnectTimeout=5 "$kexecConn" test ! -f "$file"; then break; fi
		info "Still waiting"
	done
}

saveHWConf() {
	[ -z "$SAVE_HWCONF" ] && return

	info "Saving hardware configuration to $SAVE_HWCONF"
	cmd=(sudo nixos-generate-config --show-hardware-config --no-filesystems)
	((LOCAL)) || cmd=("$ssh" "$kexecConn" "${cmd[@]}")
	x "${cmd[@]}" | tee "$SAVE_HWCONF"

	info "You can now edit the hardware configuration!"
	read -rp "[33;1mPress ENTER when done"
}

uploadFlake() {
	info "Uploading flake"
	x nix copy "$flake" --to "ssh://$kexecConn"
}

formatDisks() {
	((NO_FORMAT)) && return

	info "Formatting disks"
	cmd=(
		nix
		--extra-experimental-features
		"'nix-command flakes'"
		run disko --
		-m disko
		-f "$config"
	)
	((LOCAL)) || cmd=("$ssh" -t "$kexecConn" "${cmd[*]}")
	x echo "${cmd[@]}"
}

runInstallation() {
	info "Installing the system"
	x "$ssh" -t "$kexecConn" nixos-install -v \
		--no-channel-copy \
		--no-root-password \
		--flake "$config"

	info "Exporting all ZFS pools"
	x "$ssh" -t "$kexecConn" zpool export -a

	((NO_REBOOT)) && return

	info "Rebooting"
	x "$ssh" -t "$kexecConn" reboot
}

main
