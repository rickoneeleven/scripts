# QinQ Configuration: ToR as Intermediate Mapper (Access Port Method)

## Goal

To establish a Layer 2 QinQ tunnel between the London site and the Liverpool site over the JISC ISP network, carrying **specific production customer VLANs (C-VLANs)**. This configuration uses the local Top-of-Rack (ToR) switch as the device performing the QinQ S-VLAN encapsulation/decapsulation, connecting to the Core switch via a trunk and using the "QinQ Access Port Method" logic *between* the Core and ToR link.

**Key Parameters:**
*   **C-VLANs (Customer/Internal):** **VLANs 10, 110, 111** (Specifically requested for tunneling)
*   **S-VLAN (Service Provider/Tunnel):** VLAN 602 (Assigned by JISC)
*   **QinQ TPID (Tag Protocol Identifier):** 0x9100 (Required by JISC)

## CRITICAL PREREQUISITE: Disabling ToR Switch SVIs (for Tunneled VLANs)

**This remains the most crucial step, but now applies to the ToR switch.**

The ToR switch designated to perform the QinQ mapping **MUST NOT** have active Layer 3 Switched Virtual Interfaces (SVIs, e.g., `interface Vlan10` with an `ip address`) for **ANY** of the C-VLANs that are being tunneled through the S-VLAN (specifically **VLANs 10, 110, 111** in this case).

**Why is this essential (Now on the ToR)?**

Leaving the SVIs active on the mapping ToR switch creates the same fundamental conflict as it would on the Core:

1.  **Routing vs. Bridging Conflict:** An active SVI tells the ToR it might need to act as a Layer 3 interface for that C-VLAN subnet locally. The QinQ configuration, however, tells the ToR to blindly *bridge* (encapsulate) traffic *received for that C-VLAN on the designated QinQ port (the link from the Core)* into the S-VLAN tunnel. The switch cannot logically do both for the same VLAN entering via that path.
2.  **Potential Routing/ARP Issues:** While less likely if the Core is the primary gateway, having an active SVI on the ToR for a tunneled VLAN could still lead to ARP confusion or unintended local switching/routing attempts if traffic somehow originates or terminates directly at the ToR's IP for that VLAN. It bypasses the intended L2 tunnel mechanism.
3.  **Unpredictable Behavior:** Control plane traffic associated with the active SVI might be incorrectly handled locally instead of being transparently tunneled.

**Verification (Liverpool ToR - RCP-SPI-TOR-01):**
Based on the provided configuration for `RCP-SPI-TOR-01`:
*   `interface Vlan10`: Exists, `no shutdown`, **NO IP address** -> OK for tunneling.
*   `interface Vlan110`: Exists, `no shutdown`, **NO IP address** -> OK for tunneling.
*   `interface Vlan111`: Exists, `no shutdown`, **NO IP address** -> OK for tunneling.
*   (`interface Vlan2592`: *Does* have an IP, but is not listed for tunneling -> OK).

**Conclusion:** The prerequisite *is currently met* on RCP-SPI-TOR-01 for the specified C-VLANs (10, 110, 111).

**Action:** Before applying or activating the QinQ configuration, *always* double-check and ensure that **no SVIs** corresponding to the C-VLANs you intend to tunnel (10, 110, 111) have IP addresses configured or are administratively active in an L3 sense on the ToR switches (Liverpool and London) acting as the QinQ mappers.

*(Note: The Core switch SVIs for VLANs 10, 110, 111 will remain active as they are the L3 gateways for devices at the local site, but they are no longer involved in the QinQ mapping process itself).*

## Configuration Examples (Focusing on Liverpool - London mirrors this)

*(Note: Interface numbers are examples, adjust based on your physical connections. Using `ethernet1/1/35:1` as a placeholder for the JISC connection on the ToR - replace with your actual chosen free port. Command syntax assumes Dell SmartFabric OS10.)*

### 1. Liverpool Core Switch (RCP-SPI-CS-01) Configuration

*   **Cleanup:** Remove any previous QinQ configuration related to S-VLAN 602.
*   **Port facing ToR Switch (Port-Channel 100):** This port sends standard tagged C-VLAN traffic *towards* the ToR. It remains a standard trunk.

```bash
! On RCP-SPI-CS-01

! --- Verification/Cleanup ---
show running-configuration interface vlan 602  ! Should ideally return nothing or be removable
show running-configuration interface ethernet 1/1/28:1 ! Verify previous JISC port config is removed/repurposed

config terminal

! Ensure S-VLAN 602 is removed if previously configured for QinQ here
no interface vlan 602

! Ensure the old JISC port is default/reconfigured (example)
interface ethernet 1/1/28:1
  description Repurposed Port / Link Down
  shutdown
  no switchport access vlan  ! Remove previous config
  no spanning-tree disable  ! Remove previous config
  ! etc... return to default or desired state

! --- Configuration for Link to ToR ---
! Port-Channel 100 configuration remains largely the same, just ensure C-VLANs are allowed.
interface port-channel100
  description "Link to TOR Switches"
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan add 10,110,111  // *** ENSURE 10, 110, 111 are allowed ***
  ! (Keep existing allowed VLANs as needed)
  vlt-port-channel 100

! --- SVI Status ---
! SVIs for 10, 110, 111 REMAIN ACTIVE on the Core - This is expected.
! show running-configuration interface vlan 10
! show running-configuration interface vlan 110
! show running-configuration interface vlan 111

end
write memory
```

### 2. Liverpool ToR Switch (RCP-SPI-TOR-01) Configuration

*   **Global S-VLAN Definition:** Define the S-VLAN and mark it for QinQ operation.

```bash
! On RCP-SPI-TOR-01
config terminal

! Define the S-VLAN ID provided by the ISP
interface vlan 602
  description "QinQ S-VLAN for JISC Tunnel (Mapped on ToR)"
  vlan-stack   ! IMPORTANT: Marks this VLAN for QinQ operations in OS10
  no shutdown

!
```

*   **Port facing Core Switch (Port-Channel 100 - QinQ Ingress/Egress):** This port receives tagged C-VLANs from the Core and applies the QinQ Access Port logic. **Apply this config to Po100 on BOTH ToR switches in the VLT pair.**

```bash
! On RCP-SPI-TOR-01 (and its VLT Peer)

interface port-channel100
  description "Link from Core - QinQ Ingress/Egress for S-VLAN 602"
  no shutdown
  switchport mode access       ! *** Yes, ACCESS mode ***
  switchport access vlan 602   ! *** Assign to the S-VLAN ***
  ! Remove trunk commands if they exist:
  no switchport mode trunk
  no switchport trunk allowed vlan
  spanning-tree bpdufilter enable ! Recommended for QinQ Access ports to avoid STP loops/issues
  ! OR potentially 'spanning-tree disable' if preferred and understood
  vlt-port-channel 100
!
```

*   **Port facing ISP (e.g., Eth 1/1/35:1 - QinQ Trunk):** This is the external QinQ trunk. **Apply only on the ToR where the JISC circuit is physically connected.**

```bash
! On RCP-SPI-TOR-01 (or whichever ToR gets the JISC connection)

! Choose a free port, e.g., ethernet1/1/35:1 - MODIFY AS NEEDED
interface ethernet1/1/35:1
  description "Link to ISP JISC - QinQ Trunk S-VLAN 602"
  no shutdown
  switchport mode trunk
  switchport trunk tpid 0x9100      ! *** TPID required by ISP ***
  switchport trunk allowed vlan 602 ! *** ONLY allow the S-VLAN ***
  mtu 9216                        ! Accommodate QinQ overhead (S-Tag = 4 bytes) + C-Tag + L2/IP/TCP headers
  spanning-tree disable           ! Recommended/Required on P2P ISP links
  no switchport access vlan
!
```

*   **Verification of SVI Status on ToR (Mandatory):** Ensure the L3 interfaces for **ALL** C-VLANs being tunneled (10, 110, 111) are **NOT active** (have no IP address).

```bash
! On RCP-SPI-TOR-01 (and VLT Peer)

! CONFIRM these interfaces do NOT have IP addresses configured
! show running-configuration interface Vlan10 | include ip address  (Should return nothing)
! show running-configuration interface Vlan110 | include ip address (Should return nothing)
! show running-configuration interface Vlan111 | include ip address (Should return nothing)

! If they somehow had IPs, remove them:
! config t
!   interface Vlan10
!     no ip address
!   interface Vlan110
!     no ip address
!   interface Vlan111
!     no ip address
! end

end
write memory
!
```

### 3. London Site Configuration

The configuration on the **London ToR** and **London Core** switches would **mirror this new Liverpool setup**:

*   **London Core:** Configured like RCP-SPI-CS-01 (Standard trunk to ToR allowing C-VLANs 10, 110, 111; SVIs for 10, 110, 111 remain active; No QinQ config).
*   **London ToR:** Configured like RCP-SPI-TOR-01 (Defines S-VLAN 602 `vlan-stack`; Core-facing port [e.g., Po100] is `switchport mode access vlan 602`; ISP-facing port is QinQ trunk for S-VLAN 602 with TPID 0x9100 and MTU 9216; **Must verify London ToR has no active SVIs for 10, 110, 111**).

## Explanation of Key Concepts (Updated)

1.  **ToR as L2 Mapper:** By ensuring the ToR has no L3 SVIs for the tunneled C-VLANs (10, 110, 111), the ToR is dedicated to Layer 2 QinQ mapping for this path. The Core handles L3 routing locally.
2.  **Core->ToR Link (QinQ Access Port Method):**
    *   The Core sends standard tagged C-VLAN frames (10, 110, 111) over its trunk port (Po100).
    *   The ToR receives these on its specially configured `access` port (Po100) mapped to the `vlan-stack` enabled S-VLAN (602).
    *   This port automatically encapsulates incoming C-VLAN tagged frames (10, 110, 111) into S-VLAN 602 (preserving the C-Tag) and decapsulates traffic coming *back* from S-VLAN 602 (stripping the S-Tag) before sending towards the Core.
    *   This `trunk (Core) -> access (ToR)` setup implements the QinQ Access Port method.
3.  **ToR->ISP Link (QinQ Trunk):**
    *   Standard QinQ trunk on the ToR's ISP-facing port using the ISP's TPID (0x9100), carrying only S-VLAN 602, with increased MTU.

## Traffic Flow Summary (Updated)

*   **Server (VLAN 10) London -> Server (VLAN 10) Liverpool:**
    1.  Frame (C-Tag 10) leaves London Server -> London ToR.
    2.  London ToR sends frame (C-Tag 10) -> London Core (via standard trunk, e.g., Po100).
    3.  London Core routes/switches if needed, then sends frame (C-Tag 10) -> London ToR (via standard trunk Po100).
    4.  Arrives London ToR Po100 (QinQ Access Port) -> Associated with S-VLAN 602 (C-Tag 10 preserved).
    5.  Leaves London ToR ISP Port (QinQ Trunk) with Outer Tag S-VLAN 602 (TPID 0x9100) + Inner Tag C-VLAN 10.
    6.  Traverses JISC network.
    7.  Arrives Liverpool ToR ISP Port (QinQ Trunk) -> S-Tag 602 processed.
    8.  Leaves Liverpool ToR Po100 (QinQ Access Port) -> S-Tag 602 stripped. Frame now has only C-Tag 10.
    9.  Arrives Liverpool Core Po100 (Standard Trunk) as Frame (C-Tag 10).
    10. Liverpool Core routes/switches frame -> Liverpool ToR (Standard Trunk).
    11. Liverpool ToR sends frame (C-Tag 10) -> Liverpool Server.
*   The same flow applies concurrently for frames tagged C-VLAN 110 and 111.
*   **Liverpool -> London:** Reverse of the above.

## VLT Considerations (Single JISC Connection)

*   The configuration for `interface port-channel100` (QinQ Access Port) **must be identical on both VLT ToR peers**.
*   The configuration for `interface vlan 602` (`vlan-stack`) **must be present on both VLT ToR peers**.
*   The QinQ Trunk configuration (ISP-facing port) is **only applied to the specific ToR switch** where the JISC circuit physically terminates.
*   Traffic originating from servers connected to the *other* ToR (the one *without* the direct JISC connection) will traverse the VLT Peer Link (VLTi) to reach the ToR with the active QinQ trunk port for egress. Similarly, return traffic arriving on the QinQ trunk port might need to cross the VLTi to reach servers connected to the peer ToR. This is normal VLT operation but concentrates the QinQ traffic egress/ingress on one switch and the VLTi.