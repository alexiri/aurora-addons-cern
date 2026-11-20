# aurora-addons-cern

An **addon repository** for [Aurora](https://github.com/alexiri/aurora): signed app packages for
CERN services that an Aurora instance administrator can register as an addon source.

| Package | What it gives an agent |
|---|---|
| `cern-phonebook` | People and e-group lookup in CERN's central directory (`xldap.cern.ch`, anonymous LDAPS, read-only): e-mail address, office, department, manager chain. Contract status and nationality are deliberately not offered. The gateway runs every search (its LDAP lane); the sandbox never gets a raw LDAP connection. |
| `cern-maps` | Buildings, rooms and points of interest on the CERN sites from the public CERN Maps services (`maps.cern.ch`): search, place details, building geocoding, and routes with walking, cycling and driving times. Read-only. |
| `cern-rotas` | One rota per connection from CERN's Accelerator Schedule Management (`asm.cern.ch`): who is on duty now and the assignments of the coming seven days ("who is on the Linux rota today?", "when is my next rota week?"). Read-only; the operator must allow `asm.cern.ch` (a private address) and trust the CERN Grid CA, see its setup guide. |

All three packages are credential-free: there is nothing to sign in to, and connecting one only grants an
agent the right to use it (every request still goes through your rules and the request log).

## Use it in Aurora

In Aurora, as an instance administrator: **Admin, Addon sources, Add**, and paste
`https://github.com/alexiri/aurora-addons-cern`. Review the signing-key fingerprint (it is the key in
[`aurora-addons.yaml`](aurora-addons.yaml); check it against what is published here, or ask the contact below),
confirm, then approve the packages on the Plugins page, add a connection and grant it. The format is
documented in Aurora's `docs/22-addon-repos.md`.

## Layout

```
aurora-addons.yaml          the repository manifest Aurora reads (generated, committed)
plugins/<id>/               one package: plugin.yaml, docs/setup.md, assets/icon.png (+ icon-dark.png), tests/*.yaml
releases/<id>-<ver>.release the immutable record of a published version: tag, sha256 (signed), size, unsigned sha256
scripts/manifest-head.yaml  the fixed top of the manifest (repo info, publisher, the PUBLIC signing key)
scripts/release.sh          build, test, sign, record and manifest generation
.github/workflows/release.yml  CI: verify on every push; sign and publish on a v* tag (a release, v1, v2, …)
```

## Releasing a version (maintainer)

A published version is **immutable**: the packages are signed archives published as GitHub release
assets and the manifest pins their sha256. A fix is a new version.

Each package has its own version (`package.version`). Releases of the repository are numbered on
their own, `v1`, `v2`, `v3`, …: a release carries every package version recorded since the previous
one, whichever packages those are. (The releases `v0.1.0` … `v0.1.3` predate this numbering and keep
their names.)

1. Change the package under `plugins/<id>/` and raise `package.version` in its `plugin.yaml`.
2. Locally, with the `aurora` CLI on the PATH (or `AURORA=/path/to/aurora`) and the private key file
   (`cern-release.key`, kept outside git; `.gitignore` excludes it):

   ```sh
   scripts/release.sh all --key cern-release.key
   ```

   This builds and fixture-tests every package, signs the archives, verifies each against the
   manifest's `signing_key`, writes `releases/<id>-<version>.release` for each new version and
   regenerates `aurora-addons.yaml`. A new record names the **next release**, one more than the
   highest `vN` tag on origin, and the script prints it (`scripts/release.sh next-tag` shows it too).
   Review the diff and commit it like any other change.
3. Push to `main`. CI rebuilds everything **without the key**, runs the fixtures, and fails if the
   manifest differs from what the sources, the records and `scripts/manifest-head.yaml` produce, or if
   a package's source no longer matches its recorded unsigned build (the build is deterministic).
4. Tag the commit with that release number (`git tag v4 && git push origin v4`; it is the `tag`
   field of the new records). Changing several packages before tagging is fine: every new record
   names the same pending release until its tag exists. The `publish` job (environment `release`, the secret
   `AURORA_CERN_SIGNING_KEY`) signs, checks the signed archives against the records, creates the
   GitHub Release with the archives as assets, and downloads them again to compare sha256 and size
   with the manifest. Re-running it for a tag that is already released fails.

Pull requests and forks build and test without the secret; signing is skipped and nothing is published.

CI builds the `aurora` CLI from source at the commit pinned in `AURORA_REV` of the workflow (the
Aurora repository publishes no binary releases yet). Changing the pin is a reviewed change.

## Trust

The signing key in `aurora-addons.yaml` is **this repository's own** key; the Aurora project key never
signs addons. Its private half lives in the owner's password manager and in the `release` environment of
this repository, never in git. Rotating it follows Aurora's `docs/22-addon-repos.md` ("Rotating the signing key").

CERN's marks are trademarks of CERN. The package icons are original monograms, not CERN artwork.

## Contact

Issues: <https://github.com/alexiri/aurora-addons-cern/issues>

## License

See [LICENSE](LICENSE).
