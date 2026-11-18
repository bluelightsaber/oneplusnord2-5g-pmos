#!/usr/bin/env python3
"""denniz Type-C (DENNIZ_TYPEC=1): make the MT6360 TCPC + TCPM usable as a sink-only port. Idempotent.
1. tcpci_mt6360.c: the tree's post-probe alert unmask (added for chopin) rewrites TCPC_ALERT_MASK without
   TCPC_ALERT_POWER_STATUS, overriding tcpci_init(): TCPM never hears VBUS and sticks in SNK_DEBOUNCED.
2. tcpm.c: a sink-only port does not toggle, so a source that is already there at boot (or still there after a
   detach) never produces a CC change event and is never attached: attach from the cached CC state instead.
Usage: patch-typec.py <kernel tree>
"""
import sys, pathlib
K = pathlib.Path(sys.argv[1]); T = K / "drivers/usb/typec/tcpm"

f = T / "tcpci_mt6360.c"; s = f.read_text()
if "denniz: VBUS alert" not in s:
    a = "\t\t\t   TCPC_ALERT_RX_HARD_RST | TCPC_ALERT_CC_STATUS;\n\n\t\tret = mti->tdata.regmap"
    assert s.count(a) == 1, "mt6360 mask anchor"
    s = s.replace(a, "\t\t\t   TCPC_ALERT_RX_HARD_RST | TCPC_ALERT_CC_STATUS |\n"
                     "\t\t\t   TCPC_ALERT_POWER_STATUS;\t/* denniz: VBUS alert, as tcpci_init() (controls_vbus) */\n\n"
                     "\t\tret = mti->tdata.regmap")
    f.write_text(s)

f = T / "tcpm.c"; s = f.read_text()
if "denniz: sink-only" not in s:
    a = ("\t\ttcpm_set_cc(port, TYPEC_CC_RD);\n\t\tif (port->port_type == TYPEC_PORT_DRP)\n"
         "\t\t\ttcpm_set_state(port, SRC_UNATTACHED, PD_T_DRP_SRC);\n\t\tbreak;\n\tcase SNK_ATTACH_WAIT:")
    assert s.count(a) == 1, "SNK_UNATTACHED anchor"
    s = s.replace(a, "\t\ttcpm_set_cc(port, TYPEC_CC_RD);\n"
        "\t\t/* denniz: sink-only ports do not toggle, so a source already present (at boot, or still there\n"
        "\t\t * after a detach) never raises a CC change: attach from the cached CC state */\n"
        "\t\tif (port->port_type == TYPEC_PORT_SNK && tcpm_port_is_sink(port)) {\n"
        "\t\t\ttcpm_set_state(port, SNK_ATTACH_WAIT, 0);\n\t\t\tbreak;\n\t\t}\n"
        "\t\tif (port->port_type == TYPEC_PORT_DRP)\n"
        "\t\t\ttcpm_set_state(port, SRC_UNATTACHED, PD_T_DRP_SRC);\n\t\tbreak;\n\tcase SNK_ATTACH_WAIT:")
    f.write_text(s)
print("typec patch applied")
