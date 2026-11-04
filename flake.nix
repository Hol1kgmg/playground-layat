{
  description = "Agent skills managed by layat";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    layat.url = "github:yasunori0418/layat";
    layat.inputs.nixpkgs.follows = "nixpkgs";
    skills = {
      url = "github:Hol1kgmg/SKILL";
      flake = false;
    };
  };

  outputs = { nixpkgs, layat, skills, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      skillNames = builtins.attrNames (nixpkgs.lib.filterAttrs (_: t: t == "directory") (builtins.readDir "${skills}/skills"));
    in
    {
      layat = forAllSystems (system: {
        skills = layat.lib.mkManifest {
          pkgs = nixpkgs.legacyPackages.${system};
          root = layat.lib.projectRoot;
          entries = nixpkgs.lib.genAttrs' skillNames (name:
            nixpkgs.lib.nameValuePair ".agents/skills/layat-${name}" { src = skills; subpath = "skills/${name}"; });
        };
      });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            packages = [ pkgs.gitleaks pkgs.lefthook pkgs.jq layat.packages.${system}.layat ];
            shellHook = ''
              layat apply skills --no-wait
              lefthook install >/dev/null
            '';
          };
        });
    };
}
