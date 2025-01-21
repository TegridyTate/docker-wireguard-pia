#!/bin/bash

# This script is run once a port has been successfully forwarded
# The port number is passed as the first argument

[[ "$FIREWALL" =~ ^[0-1]$ ]] || FIREWALL=1

if [ $FIREWALL -eq 1 ]; then
  iptables -A INPUT -p tcp -i wg0 --dport "$1" -j ACCEPT
  iptables -A INPUT -p udp -i wg0 --dport "$1" -j ACCEPT
  echo "$(date): Allowing incoming traffic on port $1"
fi

# Set env var PF_DEST_IP to forward on to another address
# eg PF_DEST_IP=192.168.1.48
if [ -n "$PF_DEST_IP" ] && [ -n "$FWD_IFACE" ]; then
  iptables -t nat -A PREROUTING -p tcp --dport "$1" -j DNAT --to-destination "$PF_DEST_IP:$1"
  iptables -t nat -A PREROUTING -p udp --dport "$1" -j DNAT --to-destination "$PF_DEST_IP:$1"
  iptables -A FORWARD -i wg0 -o "$FWD_IFACE" -p tcp -d "$PF_DEST_IP" --dport "$1" -j ACCEPT
  iptables -A FORWARD -i wg0 -o "$FWD_IFACE" -p udp -d "$PF_DEST_IP" --dport "$1" -j ACCEPT
  echo "$(date): Forwarding incoming VPN traffic on port $1 to $PF_DEST_IP:$1"
fi

# Retrieve the forwarded port from the WireGuard container
PORT=$(cat /pia-shared/port.dat)

# Define qBittorrent Web API details
QBITTORRENT_URL="http://$QBITTORRENT_HOST:$QBITTORRENT_PORT/api/v2"

# Login to qBittorrent Web API
COOKIE_JAR=$(mktemp)
curl -s -X POST \
  -c "$COOKIE_JAR" \
  -d "username=$QBITTORRENT_USERNAME&password=$QBITTORRENT_PASSWORD" \
  "$QBITTORRENT_URL/auth/login"

# Extract the SID from the cookie
SID=$(grep SID "$COOKIE_JAR" | awk '{print $NF}')

if [ -z "$SID" ]; then
  echo "Failed to authenticate with qBittorrent Web API"
  rm "$COOKIE_JAR"
  exit 1
fi

# Get the current listening port
CURRENT_PORT=$(curl -s --cookie "SID=$SID" "$QBITTORRENT_URL/app/preferences" | jq -r '.listen_port')

# Print out the current port
echo "Current qBittorrent port is: $CURRENT_PORT"

# Print out the port to be set
echo "Setting qBittorrent port to $PORT"

# Compare the current port with the new port and update if necessary
if [ "$CURRENT_PORT" != "$PORT" ]; then
  echo "Updating qBittorrent port to: $PORT"
  curl -s -X POST \
    --cookie "SID=$SID" \
    --data "json={\"listen_port\":$PORT}" \
    "$QBITTORRENT_URL/app/setPreferences"
  echo "qBittorrent port updated to: $PORT"
else
  echo "Port is already set correctly."
fi

# Clean up the cookie file
rm "$COOKIE_JAR"