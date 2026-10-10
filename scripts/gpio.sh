# GPIO access through libgpiod, sourced by utilities.sh in place of
# WiringPi's `gpio`, which only works when it can identify the board from the
# Raspberry Pi kernel or firmware-provided device tree.
#
# Pins are BCM numbers, which are the line offsets on the GPIO controller
# driving the 40-pin header. Set WITTYPI_GPIO_CHIP to a chip name, number or
# path if it is not detected.

if [ -z "${WITTYPI_GPIO_CHIP:-}" ]; then
  WITTYPI_GPIO_CHIP=$(gpiodetect 2>/dev/null \
    | awk '/\[(pinctrl-bcm2835|pinctrl-bcm2711|pinctrl-rp1)\]/ { print $1; exit }')
  if [ -z "$WITTYPI_GPIO_CHIP" ]; then
    echo 'wittypi: GPIO header chip not found, set WITTYPI_GPIO_CHIP (see gpiodetect)' >&2
  fi
fi

# Make the pin an input with the internal pull-up enabled.
gpio_input_pullup()
{
  gpioget -c "$WITTYPI_GPIO_CHIP" --bias=pull-up "$1" >/dev/null
}

# Print the pin's value (0 or 1), reading it with the internal pull-up enabled.
gpio_read_pullup()
{
  gpioget -c "$WITTYPI_GPIO_CHIP" --bias=pull-up --numeric "$1"
}

# Drive the pin 1, 0, 1, 0 for 100ms each, then leave it as an input.
gpio_pulse_twice()
{
  gpioset -c "$WITTYPI_GPIO_CHIP" -p 100ms -t 100ms,100ms,100ms,0 "$1=1" \
    && gpioget -c "$WITTYPI_GPIO_CHIP" "$1" >/dev/null
}

# Block until a falling edge on the pin, with the internal pull-up enabled.
gpio_wait_falling()
{
  gpiomon -c "$WITTYPI_GPIO_CHIP" --bias=pull-up --edges=falling --num-events=1 "$1" >/dev/null
}
