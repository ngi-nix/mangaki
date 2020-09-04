{ poetry2nix }:
{ src }:

poetry2nix.mkPoetryApplication {
  inherit src;# prevents unnecessary sanitizing which causes problems
  projectDir = src; # so it can find pyproject.toml and poetry.lock
  overrides = poetry2nix.overrides.withDefaults (final: prev:
    with final;
    {

      dephell = prev.dephell.overridePythonAttrs (_: {
        postPatch = ''
          # [heavily] relax pip version constraint
          sed -i "s@'pip[^']*'@'pip'@" setup.py
        '';
      });

    });

  postPatch = ''
    sed -i "s@FIXTURE_DIR.*@FIXTURE_DIR = '${src}/fixtures'@" mangaki/mangaki/settings.py
  '';
}
