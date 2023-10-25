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
            in
            {
              type = "app";
              program = "${pkgs.substituteAll {
                src = ./und.sh;
                inherit name flake;

                user = args.user or "";
                host = args.host or "";
                preUser = args.preUser or "";
                kexec = args.kexec or "";

                ssh = "${pkgs.openssh}/bin/ssh";
              }}";
            }))
        ]) [ "x86_64-linux" "aarch64-linux" ];
  };
}
