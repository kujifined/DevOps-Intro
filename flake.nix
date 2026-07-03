{
  description = "Reproducible QuickNotes build with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { nixpkgs, ... }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          quicknotes = pkgs.buildGoModule {
            pname = "quicknotes";
            version = "0.1.0";

            src = ./app;

            env.CGO_ENABLED = "0";
            vendorHash = null;

            ldflags = [
              "-s"
              "-w"
            ];

            postInstall = ''
              if [ -f "$out/bin/app" ]; then
                mv "$out/bin/app" "$out/bin/quicknotes"
              fi

              if [ ! -x "$out/bin/quicknotes" ]; then
                echo "expected $out/bin/quicknotes to exist"
                find "$out/bin" -maxdepth 1 -type f -print || true
                exit 1
              fi
            '';
          };

          imageRoot = pkgs.runCommand "quicknotes-image-root" { } ''
            mkdir -p "$out/share/quicknotes" "$out/tmp"
            cp ${./app/seed.json} "$out/share/quicknotes/seed.json"
            chmod 1777 "$out/tmp"
          '';

          docker = pkgs.dockerTools.buildImage {
            name = "quicknotes";
            tag = "nix";

            copyToRoot = pkgs.buildEnv {
              name = "quicknotes-rootfs";
              paths = [
                quicknotes
                imageRoot
                pkgs.fakeNss
              ];
              pathsToLink = [
                "/bin"
                "/etc"
                "/share"
                "/tmp"
              ];
            };

            config = {
              Entrypoint = [ "/bin/quicknotes" ];
              ExposedPorts = {
                "8080/tcp" = { };
              };
              User = "65532:65532";
              Env = [
                "ADDR=:8080"
                "DATA_PATH=/tmp/quicknotes/notes.json"
                "SEED_PATH=/share/quicknotes/seed.json"
              ];
            };
          };
        in
        {
          inherit quicknotes docker;
          default = quicknotes;
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.go
              pkgs.golangci-lint
              pkgs.gopls
            ];

            env.CGO_ENABLED = "0";
          };
        });
    };
}
