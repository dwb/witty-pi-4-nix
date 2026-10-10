{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bash,
  coreutils,
  curl,
  gawk,
  gnugrep,
  gnused,
  i2c-tools,
  libgpiod,
  systemd,
  util-linux,
}:

let
  runtimePath = lib.makeBinPath [
    coreutils
    curl
    gawk
    gnugrep
    gnused
    i2c-tools
    libgpiod
    util-linux
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "wittypi4";
  version = "4.23-unstable-2026-04-07";

  src = fetchFromGitHub {
    owner = "uugear";
    repo = "Witty-Pi-4";
    rev = "d466cbc18aaea619c1f41ddb170789a661be3338";
    hash = "sha256-jKErvlb1TipjsimuxeNTgPkqpBq6oLHzNmYBvC+noWg=";
  };

  sourceRoot = "${finalAttrs.src.name}/Software/wittypi";

  dontConfigure = true;
  dontBuild = true;

  # The scripts are linked into a writable home directory at runtime by
  # wittypi-setup-home, since upstream reads schedule.wpi and the hooks from
  # next to them.
  #
  # nixos.patch:
  # - Puts runtime dependencies on PATH, sets a locale that exists on NixOS,
  #   and drops sudo, lsb_release and dpkg.
  # - Logs to syslog (journald) as `wittypi` instead of the unrotated
  #   wittyPi.log and schedule.log. Hook output goes to stderr, which the
  #   service sends to the journal (not a pipe to logger, so hooks that
  #   background a command don't block); the daemon's stdout can be discarded.
  # - Uses libgpiod instead of WiringPi's `gpio`, which refuses to run unless
  #   it can identify the board from the Raspberry Pi kernel or firmware
  #   device tree. daemon.sh exits rather than shutting down if waiting for
  #   the shutdown signal fails.
  patches = [ ./nixos.patch ];

  postPatch = ''
    substituteInPlace utilities.sh \
      --subst-var-by path ${runtimePath} \
      --subst-var-by systemdPath ${lib.getBin systemd}/bin

    # Catch WiringPi calls added upstream that the patch doesn't cover.
    if grep -n 'gpio -g' *.sh; then
      echo "unpatched WiringPi calls remain" >&2
      exit 1
    fi
  '';

  installPhase = ''
    runHook preInstall

    share=$out/share/wittypi
    mkdir -p $share $out/bin
    cp -r schedules $share/
    install -m 0755 \
      daemon.sh runScript.sh wittyPi.sh utilities.sh \
      afterStartup.sh beforeScript.sh beforeShutdown.sh \
      $share/

    for f in wittypi wittypi-daemon wittypi-setup-home; do
      substitute ${./scripts}/$f.sh $out/bin/$f \
        --subst-var-by bash ${bash} \
        --subst-var-by share $share \
        --subst-var out
    done
    chmod +x $out/bin/*

    runHook postInstall
  '';

  meta = {
    description = "Client software (daemon and CLI) for the UUGear Witty Pi 4 RTC and power management board";
    homepage = "https://github.com/uugear/Witty-Pi-4";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "wittypi";
  };
})
