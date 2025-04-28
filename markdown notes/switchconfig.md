# QinQ Configuration: ToR as Mapper via Dedicated Link (Access Port Method)

## Goal

To establish a Layer 2 QinQ tunnel between the London site and the Liverpool site over the JISC ISP network, carrying **specific production customer VLANs (C-VLANs: 10, 110, 111)**. This configuration uses the local Top-of-Rack (ToR) switch as the device performing the QinQ S-VLAN encapsulation/decapsulation. A **new, dedicated link** between the Core and ToR is used to feed the C-VLANs into the QinQ process using the "Access Port Method", while the existing Core-ToR link (Po100) handles standard traffic, including management VLANs.

**Key Parameters:**
*   **C-VLANs (Customer/Internal):** **VLANs 10, 110, 111** (Specifically requested for tunneling)
*   **S-VLAN (Service Provider/Tunnel):** VLAN 602 (Assigned by JISC)
*   **QinQ TPID (Tag Protocol Identifier):** 0x9100 (Required by JISC)

## Architecture Overview

1.  **QinQ Mapping Device:** The ToR switch (e.g., RCP-SPI-TOR-01 in Liverpool).
2.  **QinQ C-VLAN Feed Link:** A *new, dedicated physical link or Port-Channel* between Core and ToR.
    *   Core side: Standard trunk allowing *only* C-VLANs 10, 110, 111.
    *   ToR side: Configured as `switchport mode access vlan 602` (QinQ Access Port).
3.  **Standard Traffic Link:** The *existing* Port-Channel 100 between Core and ToR.
    *   Remains a standard trunk on both sides.
    *   Carries all other required VLANs, including management VLAN 2592.
    *   **Must NOT** allow the tunneled C-VLANs (10, 110, 111) if they only need to traverse the QinQ tunnel.
4.  **ISP Link:** The ToR port connected to JISC, configured as the QinQ trunk port.
5.  **Core Switch Role:** Acts as the L3 gateway for local subnets (including 10, 110, 111, 2592) but is *not* involved in QinQ mapping.
6.  **ToR Switch Role:** Performs QinQ mapping for C-VLANs arriving on the dedicated link, passes standard traffic from Po100, and manages its own SVI (e.g., VLAN 2592) via Po100.

## CRITICAL PREREQUISITE: Disabling ToR Switch SVIs (for Tunneled VLANs)

**This prerequisite still applies to the ToR switch acting as the QinQ mapper.**

The ToR switch performing the QinQ mapping **MUST NOT** have active Layer 3 Switched Virtual Interfaces (SVIs with IP addresses) for **ANY** of the C-VLANs being tunneled (specifically **VLANs 10, 110, 111**).

**Why:** Prevents routing/bridging conflicts on the ToR for the VLANs designated for L2 tunneling.

**Verification (Liverpool ToR - RCP-SPI-TOR-01):**
Based on the provided configuration for `RCP-SPI-TOR-01`:
*   `interface Vlan10`, `Vlan110`, `Vlan111`: Exist, `no shutdown`, **NO IP address** -> OK for tunneling.
*   `interface Vlan2592`: *Does* have an IP (`172.24.192.6/24`), but it is **not** being tunneled and will use the standard Po100 link -> OK.

**Conclusion:** The prerequisite *is currently met* on RCP-SPI-TOR-01 for the specified C-VLANs (10, 110, 111) with this dedicated link architecture.

**Action:** Always verify that no SVIs corresponding to the C-VLANs intended for tunneling (10, 110, 111) have active IP addresses on the mapping ToR switches (Liverpool and London).

## Configuration Examples (Focusing on Liverpool - London mirrors this)

*(Note: Interface numbers are examples. Using `ethernet1/1/48` on Core and `ethernet1/1/48` on ToR as placeholders for the **NEW dedicated QinQ feed link** - replace with actual chosen free ports. If using multiple physical links, create a new Port-Channel, e.g., Po101, and apply the config there. Using `ethernet1/1/35:1` on ToR as the JISC connection placeholder.)*

### 1. Liverpool Core Switch (RCP-SPI-CS-01) Configuration

*   **Cleanup:** Remove any previous QinQ config attempts from the Core.
*   **Existing Link (Port-Channel 100):** Standard trunk, carries non-tunneled VLANs including Mgmt (2592). **Crucially, REMOVE tunneled C-VLANs (10, 110, 111) from this trunk.**
*   **New Dedicated Link (e.g., Eth 1/1/48):** Trunk port sending *only* C-VLANs 10, 110, 111 towards the ToR.

```bash
! On RCP-SPI-CS-01
config terminal

! --- Verification/Cleanup ---
! Ensure no leftover QinQ config (no interface vlan 602, no QinQ on old ports)
! show running-configuration interface vlan 602
! show running-configuration interface ethernet 1/1/28:1 ! Example old port

! --- Configuration for Existing Link to ToR (Standard Traffic) ---
interface port-channel100
  description "Link to TOR Switches (Standard Traffic + Mgmt)"
  no shutdown
  switchport mode trunk
  ! *** IMPORTANT: Remove tunneled C-VLANs, ensure Mgmt VLAN is present ***
  switchport trunk allowed vlan remove 10,110,111
  switchport trunk allowed vlan add 2592  ! Ensure Mgmt VLAN is allowed
  ! (Keep other necessary existing allowed VLANs)
  ! LACP commands as appropriate (e.g., channel-group 100 mode active) on member interfaces (Eth1/1/53, 1/1/54)

! --- Configuration for NEW Dedicated Link to ToR (QinQ Feed) ---
! Choose a free port, e.g., ethernet1/1/48 - MODIFY AS NEEDED
! Or configure member ports and a new Port-Channel (e.g., Po101)
interface ethernet1/1/48  ! Or interface port-channel101
  description "Dedicated Link to ToR for QinQ C-VLANs (10, 110, 111)"
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 10,110,111  ! *** ONLY allow the C-VLANs to be tunneled ***
  no switchport access vlan
  ! Add to appropriate channel-group if using Port-Channel

! --- SVI Status ---
! SVIs for 10, 110, 111, 2592 REMAIN ACTIVE on the Core - This is expected.

end
write memory
```

### 2. Liverpool ToR Switch (RCP-SPI-TOR-01) Configuration

*   **Global S-VLAN Definition:** Define S-VLAN 602 for QinQ.
*   **Existing Link (Port-Channel 100):** Standard trunk matching the Core, allowing Mgmt VLAN 2592, excluding C-VLANs 10, 110, 111. **Apply identically to VLT Peer.**
*   **New Dedicated Link (e.g., Eth 1/1/48):** QinQ Access Port, receiving C-VLANs from Core and encapsulating into S-VLAN 602. **Apply identically to VLT Peer.**
*   **ISP Link (e.g., Eth 1/1/35:1):** QinQ Trunk port. **Apply only to the ToR with the physical JISC connection.**

```bash
! On RCP-SPI-TOR-01 (and its VLT Peer, where noted)

config terminal

! --- Global S-VLAN Definition --- (Apply on BOTH ToRs)
interface vlan 602
  description "QinQ S-VLAN for JISC Tunnel (Mapped on ToR)"
  vlan-stack   ! Marks this VLAN for QinQ operations in OS10
  no shutdown

! --- Configuration for Existing Link to Core (Standard Traffic) --- (Apply on BOTH ToRs)
interface port-channel100
  description "Link to Core Switches (Standard Traffic + Mgmt)"
  no shutdown
  switchport mode trunk
  ! *** IMPORTANT: Mirror Core - Remove tunneled C-VLANs, ensure Mgmt VLAN is present ***
  switchport trunk allowed vlan remove 10,110,111
  switchport trunk allowed vlan add 2592  ! Ensure Mgmt VLAN is allowed
  ! (Keep other necessary existing allowed VLANs)
  vlt-port-channel 100

! --- Configuration for NEW Dedicated Link from Core (QinQ Ingress/Egress) --- (Apply on BOTH ToRs)
! Choose the corresponding free port, e.g., ethernet1/1/48 - MODIFY AS NEEDED
! Or configure member ports and the new Port-Channel (e.g., Po101)
interface ethernet1/1/48  ! Or interface port-channel101
  description "Dedicated Link from Core - QinQ Ingress for S-VLAN 602"
  no shutdown
  switchport mode access       ! *** Yes, ACCESS mode ***
  switchport access vlan 602   ! *** Assign to the S-VLAN ***
  spanning-tree bpdufilter enable ! Recommended for QinQ Access ports
  ! If using Port-Channel, add: vlt-port-channel <new_ID, e.g., 101>

! --- Configuration for Port facing ISP (QinQ Trunk) --- (Apply ONLY on ToR with JISC connection)
! Choose a free port, e.g., ethernet1/1/35:1 - MODIFY AS NEEDED
interface ethernet1/1/35:1
  description "Link to ISP JISC - QinQ Trunk S-VLAN 602"
  no shutdown
  switchport mode trunk
  switchport trunk tpid 0x9100      ! *** TPID required by ISP ***
  switchport trunk allowed vlan 602 ! *** ONLY allow the S-VLAN ***
  mtu 9216                        ! Accommodate QinQ overhead
  spanning-tree disable           ! Recommended/Required on P2P ISP links
  no switchport access vlan

! --- Verification of SVI Status on ToR --- (Check on BOTH ToRs)
! CONFIRM tunneled VLANs (10, 110, 111) do NOT have IP addresses
! show running-configuration interface Vlan10 | include ip address  (Should return nothing)
! show running-configuration interface Vlan110 | include ip address (Should return nothing)
! show running-configuration interface Vlan111 | include ip address (Should return nothing)
! CONFIRM Management SVI (2592) IS active
! show running-configuration interface Vlan2592 | include ip address (Should show 172.24.192.6)

end
write memory
!
```

### 3. London Site Configuration

The configuration on the **London ToR** and **London Core** switches would **mirror this new Liverpool setup**:

*   **London Core:** Configured like RCP-SPI-CS-01 (Standard trunk Po100 excluding C-VLANs, allowing Mgmt; New dedicated link trunking *only* C-VLANs 10, 110, 111; Relevant SVIs active).
*   **London ToR:** Configured like RCP-SPI-TOR-01 (S-VLAN 602 `vlan-stack`; Po100 standard trunk excluding C-VLANs; New dedicated link as QinQ Access Port `access vlan 602`; ISP port as QinQ Trunk; **Must verify London ToR has no active SVIs for 10, 110, 111**).

## Explanation of Key Concepts (Updated for Dedicated Link)

1.  **ToR as L2 Mapper:** The ToR handles QinQ encapsulation/decapsulation. Verified no SVI conflict for tunneled VLANs (10, 110, 111).
2.  **Dedicated Core->ToR Link (QinQ Feed):**
    *   The Core sends standard tagged C-VLAN frames (10, 110, 111) over the *new dedicated trunk* port (e.g., EthX).
    *   The ToR receives these on its *new dedicated port* (e.g., EthY) configured in `access` mode for the `vlan-stack` S-VLAN (602).
    *   This dedicated `trunk (Core) -> access (ToR)` link implements the QinQ Access Port method cleanly, *only* for the specified C-VLANs.
3.  **Standard Core->ToR Link (Po100):** Operates as a normal trunk, carrying management VLAN 2592 and other non-tunneled traffic, unaffected by QinQ.
4.  **ToR->ISP Link (QinQ Trunk):** Standard QinQ trunk on the ToR's ISP-facing port.

## Traffic Flow Summary (Updated for Dedicated Link)

*   **Server (VLAN 10) London -> Server (VLAN 10) Liverpool:**
    1.  Frame (C-Tag 10) leaves London Server -> London ToR.
    2.  London ToR sends frame (C-Tag 10) -> London Core (via standard trunk Po100).
    3.  London Core routes/switches, determines path is via QinQ tunnel -> Sends frame (C-Tag 10) out **dedicated QinQ feed link** (e.g., EthX).
    4.  Arrives London ToR **dedicated QinQ feed port** (e.g., EthY - QinQ Access Port) -> Associated with S-VLAN 602 (C-Tag 10 preserved).
    5.  Leaves London ToR ISP Port (QinQ Trunk) with Outer Tag S-VLAN 602 (TPID 0x9100) + Inner Tag C-VLAN 10.
    6.  Traverses JISC network.
    7.  Arrives Liverpool ToR ISP Port (QinQ Trunk) -> S-Tag 602 processed.
    8.  Leaves Liverpool ToR **dedicated QinQ feed port** (e.g., EthY - QinQ Access Port) -> S-Tag 602 stripped. Frame now has only C-Tag 10.
    9.  Arrives Liverpool Core via **dedicated QinQ feed link** (e.g., EthX - Standard Trunk) as Frame (C-Tag 10).
    10. Liverpool Core routes/switches frame -> Liverpool ToR (via standard trunk Po100).
    11. Liverpool ToR sends frame (C-Tag 10) -> Liverpool Server.
*   The same flow applies concurrently for frames tagged C-VLAN 110 and 111.
*   **Management Traffic (VLAN 2592):** Flows normally over the Po100 trunk between Core and ToR, never touching the dedicated QinQ feed link or the QinQ encapsulation process.
*   **Liverpool -> London:** Reverse of the above flows.

## VLT Considerations (Single JISC Connection)

*   The configuration for the **existing Port-Channel 100** must be identical on both VLT ToR peers.
*   The configuration for the **new dedicated QinQ feed link** (whether a single port or a new Port-Channel like Po101) **must be identical on both VLT ToR peers**, including the `switchport mode access vlan 602` and `spanning-tree bpdufilter enable` commands (and `vlt-port-channel <ID>` if using a Port-Channel).
*   The `interface vlan 602 vlan-stack` definition **must be present on both VLT ToR peers**.
*   The QinQ Trunk configuration (ISP-facing port) is **only applied to the specific ToR switch** with the physical JISC connection.
*   Traffic needing QinQ encapsulation that originates via the ToR *without* the JISC link will use its local dedicated link (e.g., EthY) to receive the traffic from the Core, encapsulate it, and then forward it *across the VLTi* to the peer ToR which has the active JISC QinQ trunk port. Return traffic may also need to cross the VLTi.