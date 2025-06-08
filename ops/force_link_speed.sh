#!/bin/bash
#
#
if [ $# -lt 2 ];then
  echo "usage:$0 {DEV} {10G|25G|40G|50G|100G|200G|400G|800G} {1X|2X|4X|8X}"
  echo "nX value must match SPEED"
  exit 1
fi
DEV=${1}
shift
SPEED=${1}
shift
XVAL=${1}
shift
#
# 2. Disable Auto-Negotiation
# Set the port to not use auto-negotiation:

mlxconfig -d ${DEV} -y set PHY_AUTO_NEG_P1=AUTO_NEG_DISABLED
# (Use P2 for port 2 if needed.)

# 3. Force Link Speed and FEC
# Set the desired speed (e.g., ${SPEED}_4X) and FEC (e.g., RS-FEC):

# 10G	0x1
# 25G	0x2
# 40G	0x4
# 50G_1X	0x8
# 50G_2X	0x10
# 100G_4X	0x200
# 200G_4X	0x400
# 400G_8X	0x800
case ${SPEED}${XVAL} in
10G)
  PHY_RATE_MASK=0x1
  XVAL=""
  ;;
25G)
  PHY_RATE_MASK=0x2
  XVAL=""
  ;;
40G)
  PHY_RATE_MASK=0x4
  XVAL=""
  ;;
50G1X)
  PHY_RATE_MASK=0x8
  XVAL="_1X"
  ;;
50G2X)
  PHY_RATE_MASK=0x8
  XVAL="_2X"
  ;;
100G4X)
  PHY_RATE_MASK=0x200
  ;;
200G|200G4X)
  PHY_RATE_MASK=0x400
  XVAL="_4X"
  ;;
400G8X)
  PHY_RATE_MASK=0x800
  XVAL="_8X"
  ;;
400G4X)
  PHY_RATE_MASK=0x1000
  XVAL="_4X"
  ;;
800G|800G8X)
  PHY_RATE_MASK=0x8000
  XVAL="_8X"
  ;;
*)
  echo "invalid setting speed=[${SPEED}] X=[${XVAL}] for script"
  exit 1
esace
mlxconfig -d ${DEV} -y set PHY_RATE_MASK_P1=${PHY_RATE_MASK}  # For ${SPEED}_4X
mlxconfig -d ${DEV} -y set PHY_RATE_MASK_OVERRIDE_P1=TRUE
mlxconfig -d ${DEV} -y set PHY_FEC_OVERRIDE_P1=0x2  # For RS-FEC
#
# Then use mlxlink to apply and verify:

mlxlink -d ${DEV} --speeds ${SPEED}_4X
mlxlink -d ${DEV} --link_mode_force --speeds ${SPEED}${XVAL}
mlxlink -d ${DEV} --fec RS --fec_speed ${SPEED}
# (Replace ${SPEED}_4X and RS with your desired speed and FEC.)

# 4. Optional: Bring Link Down and Up
# To ensure changes take effect:

mlxlink -d ${DEV} --port_state DN
mlxlink -d ${DEV} --port_state UP
# Or use the toggle command:

mlxlink -d ${DEV} -a TG
#
# 5. Verify Settings
# Check the current settings:

mlxlink -d ${DEV} --show_module --show_device --show_fec -c -e | egrep 'Auto Negotiation:|Speed:|FEC:'

#Look for:

# Auto Negotiation: FORCE - <your speed>
# Speed: <your speed>
# FEC: <your FEC>

# Summary Table
# Step	Command Example
# Disable auto-negot	mlxconfig -d ${DEV} -y set PHY_AUTO_NEG_P1=AUTO_NEG_DISABLED
# Force speed	mlxconfig -d ${DEV} -y set PHY_RATE_MASK_P1=0x200 (for 200G_4X)
# Force FEC	mlxconfig -d ${DEV} -y set PHY_FEC_OVERRIDE_P1=0x2 (RS-FEC)
# Apply via mlxlink	mlxlink -d ${DEV} --link_mode_force --speeds ${SPEED}_4X --fec RS
# Verify settings	mlxlink -d ${DEV} --show_module --show_device --show_fec -c -e
# Note:
# Always ensure the peer device (switch, router, or other NIC) is configured to match the forced speed and FEC settings to avoid link issues.
# For more details, see the NVIDIA ConnectX-7 Adapter User Manual and MFT documentation.
# 
# Related
# Why does the module info still show no FEC despite forcing RS-FEC settings
# What commands can definitively disable auto-negotiation on my ConnectX-7 NIC
# How can I confirm if the NIC is truly operating in forced ${SPEED}_4X mode
# Is there a way to verify if auto-negotiation is still active after configuration
# What troubleshooting steps are recommended when link status shows negotiation failure
# 
