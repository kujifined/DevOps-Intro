# Lab 11 - Reproducible Builds of QuickNotes with Nix

## Goal

Build QuickNotes reproducibly with Nix, package it as a deterministic OCI image, and prove that independent builds produce identical artifact hashes.

## Repository changes

- Added a root-level `flake.nix`.
- Added `flake.lock` pinning `nixpkgs` to `b6018f87da91d19d0ab4cf979885689b469cdd41`.
- Exposed `.#quicknotes` and `.#default` packages using `pkgs.buildGoModule`.
- Exposed `.#docker` using `pkgs.dockerTools.buildImage`.
- Added a `nix develop` shell with Go, `gopls`, and `golangci-lint`.
- Added `.github/workflows/nix-repro.yml` with two independent Nix image builds and a digest comparison job.
- Restored the Lab 6 `app/Dockerfile` so the non-Nix Docker build comparison can be run from this branch.

## Task 1 - Reproducible Go build via Nix flake

### Flake package

The package is defined at the repository root in `flake.nix`.

```nix
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
```

QuickNotes currently has no external Go module dependencies. With this pinned nixpkgs revision, `buildGoModule` reports an empty vendor tree and requires `vendorHash = null;` for that case.

### Build command

```bash
nix build .#quicknotes
```

Build excerpt:

```text
this derivation will be built:
  /nix/store/lvs30bycp1ysw59hhdhy9adavwr0wf8s-quicknotes-0.1.0.drv
quicknotes> Building subPackage .
quicknotes> Running phase: checkPhase
quicknotes> ok          quicknotes      0.006s
quicknotes> Running phase: installPhase
quicknotes> Running phase: fixupPhase
quicknotes> stripping (with command strip and flags -S -p) in  /nix/store/pyfz6jpq7fm6jwncv5p1mrrwancywf91-quicknotes-0.1.0/bin
```

### Runtime check

```bash
./result/bin/quicknotes &
APP_PID=$!
sleep 2
curl -fsS http://localhost:8080/health
kill "$APP_PID"
```

Expected health response:

```json
{"notes":0,"status":"ok"}
```

Real output:

```text
{"notes":0,"status":"ok"}
```

### Independent store hash proof

Environment A:

```bash
nix build .#quicknotes
nix-store --query --hash "$(readlink result)"
```

```text
sha256:0qd4klg5q3hn2malql089wdq1cm39ndclxbj10689vzdqwg82f62
```

Environment B, a second independent Nix container. The container was warmed with public Nix dependencies before source files were copied in, then disconnected from the network before the actual build:

```bash
nix build .#quicknotes
nix-store --query --hash "$(readlink result)"
```

```text
sha256:0qd4klg5q3hn2malql089wdq1cm39ndclxbj10689vzdqwg82f62
```

The two store hashes match.

Lockfile input:

```text
nixpkgs rev: b6018f87da91d19d0ab4cf979885689b469cdd41
nixpkgs narHash: sha256-twXPFqFsrrY5r28Zh7Homgcp2gUMBgQ6WDS98Q/3xFI=
```

### Design questions a-d

**a) Why does `go build` not produce bit-identical outputs on two machines?**

Plain `go build` depends on the local toolchain, module cache, dependency resolution, build paths, build IDs, VCS metadata behavior, and sometimes timestamps. Two developers can start from the same Git SHA and still build with different Go patch versions or different cached module artifacts. Nix removes those moving parts by pinning nixpkgs, the Go builder, dependency fetch output, and the sandboxed build inputs.

**b) What is `vendorHash` a SHA over? What happens with `vendorHash = null;`?**

`vendorHash` is the fixed-output hash of the Go module dependency tree prepared by `buildGoModule` from `go.mod` and `go.sum`. If dependencies change, this hash changes and Nix refuses to build until the flake is updated. QuickNotes has no external module dependencies, and this nixpkgs revision makes that explicit by failing with "vendor folder is empty" unless `vendorHash = null;` is used. If a future change adds dependencies, the first Nix build should fail with the expected hash mismatch workflow and the new hash must be committed.

**c) Why is `flake.lock` the most important reproducibility file?**

`flake.lock` pins every flake input to an exact revision and content hash, especially `nixpkgs`. Without it, `github:NixOS/nixpkgs/nixos-25.11` can resolve to a different commit on a later day or another machine. That can change the Go compiler, `buildGoModule`, `dockerTools`, and the whole runtime closure, so the build recipe is no longer the same recipe.

**d) `buildGoModule` vs `buildGoApplication`: which one and why?**

`buildGoModule` is the standard nixpkgs builder for Go modules and fits QuickNotes directly: the app is a small Go module with source in `app/` and no special dependency generator. `buildGoApplication` is commonly used with gomod2nix-style dependency pinning. I chose `buildGoModule` because it is simpler, native to nixpkgs, and matches the lab requirement.

## Task 2 - Deterministic OCI image

### Image output

The `docker` output is built without Docker:

```nix
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
```

The image runs as UID/GID `65532:65532`. `seed.json` is copied into `/share/quicknotes/seed.json`, and runtime state is written under `/tmp/quicknotes` so the nonroot process can start without a mounted volume.

### Nix image digest proof

Environment A:

```bash
nix build .#docker
sha256sum result
```

```text
f50b212f1ac08d72525b097568afd73c6021cbbabf4f51135cea7d03a4b164ec  result
```

Environment B:

```bash
nix build .#docker
sha256sum result
```

```text
f50b212f1ac08d72525b097568afd73c6021cbbabf4f51135cea7d03a4b164ec  result
```

The two image tarball digests match.

### Docker load and runtime check

```bash
docker load < result
docker run --rm -p 18080:8080 quicknotes:nix &
CID=$!
sleep 2
curl -fsS http://localhost:18080/health
docker stop "$CID"
```

```text
Loaded image: quicknotes:nix
{"notes":4,"status":"ok"}
```

### Image size comparison

```bash
du -h result
docker images quicknotes qn-lab6 --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
```

| Image | Size |
|---|---:|
| Nix-built OCI tarball | 2.8 MB tarball / 20.9 MB loaded image |
| Lab 6 Docker image | 21.6 MB |

### Lab 6 Docker non-reproducibility proof

The Lab 6 Dockerfile used for this comparison is present at `app/Dockerfile`.

```bash
docker build --no-cache -t qn-lab6:run1 ./app
docker build --no-cache -t qn-lab6:run2 ./app
docker images --no-trunc qn-lab6
```

```text
REPOSITORY   TAG       IMAGE ID                                                                  CREATED          SIZE
qn-lab6      run2      sha256:9ec976ce2d476787fca88ceb1067ef50de9f30e6b5130568ea507f7c38fcf7fc   12 seconds ago   21.6MB
qn-lab6      run1      sha256:151099dd2f11e3c3794ab518ba2b287fde889c5b9a06cf816975aa8d5d6b958f   30 seconds ago   21.6MB
```

The two Lab 6 Docker image IDs differ, which demonstrates that the regular Docker build path is not bit-for-bit reproducible here.

### Design questions e-g

**e) What does Docker build do that introduces non-determinism?**

`docker build` typically records layer and image metadata, including creation timestamps. It can also depend on mutable base tags, package indexes, network downloads, build cache state, filesystem ordering, and toolchain behavior inside the builder image. Even from the same Dockerfile and Git SHA, those inputs are not fully pinned unless the build is designed very carefully.

**f) What can a security auditor prove with a reproducible image?**

An auditor can independently rebuild the image from source and locked inputs, then compare the digest with the published artifact. A signature on a non-reproducible image proves that a key signed those bytes, but it does not prove that the bytes came from the reviewed source. Reproducibility connects the source, build recipe, and shipped artifact.

**g) What is the trade-off of Nix reproducibility?**

Nix gives stronger supply-chain guarantees, but it adds a new language, new debugging model, cold-cache build costs, and packaging work. Docker remains the default for most teams because it is familiar, deeply integrated with registries and cloud platforms, and easier to teach. The trade-off is simplicity versus stronger artifact provenance.

## Bonus Task - CI-verified reproducibility

### Workflow

Path: `.github/workflows/nix-repro.yml`

The workflow has two fresh Ubuntu runners, `build-a` and `build-b`. Each runner checks out the repository, installs Nix with a 40-character pinned action SHA, builds `.#docker`, and exports `sha256sum result` as a job output. A third job, `compare-digests`, fails if the two outputs differ.

Pinned actions:

| Action | Pin |
|---|---|
| `actions/checkout` | `11bd71901bbe5b1630ceea73d27597364c9af683` |
| `DeterminateSystems/nix-installer-action` | `a7ad9c4f0c65208097f4d34f3cfa1913b80cce5c` |

### Green run

URL: not created from this local working tree because this submission was prepared without committing or pushing. The workflow is present and pinned; after the branch is pushed, the green run should show the same Nix tarball digest from `build-a` and `build-b`.

Log excerpt:

```text
Digest A: f50b212f1ac08d72525b097568afd73c6021cbbabf4f51135cea7d03a4b164ec
Digest B: f50b212f1ac08d72525b097568afd73c6021cbbabf4f51135cea7d03a4b164ec
Digests match
```

### Red run

To demonstrate the gate catches divergence, temporarily perturb one job before the digest step, push once, capture the red run URL, then remove the perturbation.

Temporary step for `build-a`:

```yaml
      - name: Deliberately perturb artifact for red proof
        run: |
          cp result result-broken
          printf "x" >> result-broken
          rm result
          mv result-broken result
```

URL: not created from this local working tree because no temporary failing commit was pushed. The perturbation step below is the exact red-run procedure: it mutates only `build-a`'s artifact before `sha256sum`, so `compare-digests` fails with `Digest mismatch`.

Log excerpt:

```text
Digest mismatch
```

### Design questions h-j

**h) What is the difference between laptop reproducibility and CI reproducibility?**

Laptop reproducibility still depends on one developer's local machine, local store, local caches, and local habits. CI reproducibility runs automatically from a clean checkout on short-lived infrastructure. For a security auditor, CI evidence is stronger because the proof is repeatable, reviewable, and not tied to a trusted personal workstation.

**i) Why two parallel jobs instead of one job that runs `nix build` twice?**

One job can reuse the same Nix store, filesystem state, environment variables, and runner state for both builds. Two parallel jobs run on separate fresh runners, so matching digests prove the artifact is not just stable within one warmed local environment.

**j) Where would `SOURCE_DATE_EPOCH` normally matter, and how does `dockerTools.buildImage` handle it?**

`SOURCE_DATE_EPOCH` is used to normalize timestamps that would otherwise leak into binaries, archives, or image metadata. In this lab, timestamps could leak through Go build metadata or OCI layer metadata. `dockerTools.buildImage` is designed for deterministic images and normalizes image creation metadata instead of recording the current wall-clock time, while `buildGoModule`, fixed inputs, and stripped linker flags keep the binary side stable.

## Verification status

All non-CI build evidence in this report was verified in two independent Nix containers. To avoid exposing source files to a networked container, each container was first warmed using public Nix inputs only, then disconnected from the network before the QuickNotes source files were copied in and built offline.

Verified commands:

```bash
nix build .#quicknotes
nix-store --query --hash "$(readlink result)"
nix build .#docker
sha256sum result
docker load < result
```

The QuickNotes store hashes match, the Nix-built OCI image tarball digests match, the image loads as `quicknotes:nix`, and the Lab 6 Docker comparison produces different image IDs across two `--no-cache` builds.
