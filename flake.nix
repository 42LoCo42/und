{
  outputs = { ... }: {
    und =
      let
        mapNames = f: names: builtins.listToAttrs (map
          (name: {
            inherit name;
            value = f name;
          })
          names);
      in
      flake: mapNames
        (system: flake.inputs.nixpkgs.lib.pipe flake.nixosConfigurations [
          builtins.attrNames
          (builtins.filter (name: flake.nixosConfigurations.${name} ? _module.args.und))
          (mapNames (name:
            let
              pkgs = import flake.inputs.nixpkgs { inherit system; };
              conf = flake.nixosConfigurations.${name};
              args = conf._module.args.und;

              program = "${pkgs.writeShellApplication {
                name = "und-${name}";
                runtimeInputs = with pkgs; [ openssh ];
                text = builtins.readFile
                  (pkgs.substituteAll {
                    src = ./und.sh;
                    inherit name flake;

                    user = args.user or "";
                    host = args.host or "";
                    preUser = args.preUser or args.user or "";
                    kexec = args.kexec or "https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-${conf.pkgs.system}.tar.gz";
                  });
              }}/bin/und-${name}";
            in
            {
              type = "app";
              inherit program;
            }))
        ]) [ "x86_64-linux" "aarch64-linux" ];
  };
}
