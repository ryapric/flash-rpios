ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
  ssid="{{SSID}}"
  psk="{{PSK}}"
}
