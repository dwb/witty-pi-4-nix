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
  # Upstream appends to wittyPi.log and schedule.log in that directory
  # without rotation. Messages go to syslog (journald) as `wittypi` instead;
  # stdout is left for the console, so the daemon's stdout can be discarded
  # without losing anything.
  postPatch = ''
    substituteInPlace utilities.sh \
      --replace-fail 'export LC_ALL=en_GB.UTF-8' \
        'export LC_ALL=C.UTF-8
    export PATH="${runtimePath}:$PATH:${lib.getBin systemd}/bin"
    . ${./scripts/gpio.sh}' \
      --replace-fail '"$(lsb_release -si)"' '"NixOS"' \
      --replace-fail 'dpkg --print-architecture' 'uname -m' \
      --replace-fail 'sudo ' "" \
      --replace-fail 'echo $msg >> $wittypi_home/wittyPi.log' \
        'logger -t wittypi -- "$1"'

    # Hook output goes to stderr, which the service sends to the journal.
    # Not a pipe to logger, so hooks that background a command don't block.
    substituteInPlace daemon.sh \
      --replace-fail '>> "$cur_dir/wittyPi.log" 2>&1' '1>&2' \
      --replace-fail '>> "$cur_dir/schedule.log" &' '>/dev/null &'

    substituteInPlace wittyPi.sh \
      --replace-fail '. "$my_dir/runScript.sh" | tee -a "$my_dir/schedule.log"' \
        '(. "$my_dir/runScript.sh")'

    # WiringPi's `gpio` fails unless it can identify the board from the
    # Raspberry Pi kernel or firmware device tree, and daemon.sh then shuts
    # down as if requested. Use libgpiod instead (helpers in gpio.sh).
    substituteInPlace utilities.sh \
      --replace-fail 'gpio -g mode $halt_pin in' "" \
      --replace-fail 'gpio -g mode $halt_pin up' 'gpio_input_pullup $halt_pin'

    substituteInPlace daemon.sh wittyPi.sh \
      --replace-fail 'hash gpio ' 'hash gpioget '

    substituteInPlace wittyPi.sh \
      --replace-fail '$(gpio -g read $CHRG_PIN)' '$(gpio_read_pullup $CHRG_PIN)' \
      --replace-fail '$(gpio -g read $STDBY_PIN)' '$(gpio_read_pullup $STDBY_PIN)'

    substituteInPlace daemon.sh \
      --replace-fail 'gpio -g mode $HALT_PIN up' 'gpio_input_pullup $HALT_PIN' \
      --replace-fail 'gpio -g mode $HALT_PIN in' "" \
      --replace-fail 'gpio -g mode $CHRG_PIN up' 'gpio_input_pullup $CHRG_PIN' \
      --replace-fail 'gpio -g mode $CHRG_PIN in' "" \
      --replace-fail 'gpio -g mode $STDBY_PIN up' 'gpio_input_pullup $STDBY_PIN' \
      --replace-fail 'gpio -g mode $STDBY_PIN in' "" \
      --replace-fail '[ $(gpio -g read $HALT_PIN) == '"'1'"' ]' \
        '[ "$(gpio_read_pullup $HALT_PIN)" == '"'1'"' ]' \
      --replace-fail 'gpio -g mode $SYSUP_PIN out
    gpio -g write $SYSUP_PIN 1
    sleep 0.1
    gpio -g write $SYSUP_PIN 0
    sleep 0.1
    gpio -g write $SYSUP_PIN 1
    sleep 0.1
    gpio -g write $SYSUP_PIN 0
    sleep 0.1
    gpio -g mode $SYSUP_PIN in' \
        'gpio_pulse_twice $SYSUP_PIN' \
      --replace-fail 'gpio -g wfi $HALT_PIN falling' \
        'if ! gpio_wait_falling $HALT_PIN; then
      log "Unable to wait for GPIO-$HALT_PIN, exiting without shutting down."
      exit 1
    fi'

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
