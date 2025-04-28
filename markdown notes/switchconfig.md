# QinQ Proof of Concept: Tunneling VLAN 111 via ToR on Dedicated Link

## Goal

To establish a Layer 2 QinQ tunnel **for Proof of Concept (PoC)** between the London site and the Liverpool site over the JISC ISP network, carrying **only C-VLAN 111**. This configuration uses the local Top-of-Rack (ToR) switch (TOR1 initially) as the device performing the QinQ S-VLAN encapsulation/decapsulation. A **new, dedicated DAC link** between Core1 and TOR1 (using port 1/1/56) is used to feed C-VLAN 111 into the QinQ process using the "Access Port Method". The existing Core-ToR link (Po100) handles all other standard traffic, including VLANs 10, 110, and management VLAN 2592.

**Key Parameters (PoC):**
*   **C-VLAN (Customer/Internal):** **VLAN 111 ONLY**
*   **S-VLAN (Service Provider/Tunnel):** VLAN 602 (Assigned by JISC)
*   **QinQ TPID (Tag Protocol Identifier):** 0x9100 (Required by JISC)
*   **Dedicated PoC Link:** Core1 Eth 1/1/56 <--> TOR1 Eth 1/1/56

## Architecture Overview (PoC)

1.  **QinQ Mapping Device:** TOR1 (RCP-SPI-TOR-01) in Liverpool.
2.  **QinQ C-VLAN Feed Link (PoC):** The *new* dedicated DAC on Eth 1/1/56 between Core1 and TOR1.
    *   Core1 side: Standard trunk allowing *only* C-VLAN 111.
    *   TOR1 side: Configured as `switchport mode access vlan 602` (QinQ Access Port).
3.  **Standard Traffic Link:** The *existing* Port-Channel 100 between Core and ToR.
    *   Remains a standard trunk on both sides.
    *   Carries all other required VLANs, including VLANs 10, 110, and management VLAN 2592.
    *   **Must NOT** allow the tunneled C-VLAN 111.
4.  **ISP Link:** TOR1 Eth 1/1/35:1 connected to JISC, configured as the QinQ trunk port.
5.  **Core Switch Role:** Acts as the L3 gateway for local subnets (including 10, 110, 111, 2592) but is *not* involved in QinQ mapping. Routes VLAN 111 traffic towards TOR1 via the dedicated Eth 1/1/56 link.
6.  **TOR1 Switch Role:** Performs QinQ mapping for C-VLAN 111 arriving on Eth 1/1/56, passes standard traffic (VLANs 10, 110, 2592, etc.) from Po100, and manages its own SVI (VLAN 2592) via Po100.
7.  **TOR2 (VLT Peer) Role:** Configuration updated for consistency, especially Po100 and S-VLAN 602 definition. Eth 1/1/56 pre-configured but inactive for PoC.

## CRITICAL PREREQUISITE: Disabling TOR Switch SVIs (for Tunneled VLAN 111)

The ToR switch performing the QinQ mapping (TOR1) **MUST NOT** have an active Layer 3 Switched Virtual Interface (SVI with an IP address) for the C-VLAN being tunneled (**VLAN 111**).

**Verification (Liverpool TOR1 - RCP-SPI-TOR-01):**
Based on the initially provided configuration:
*   `interface Vlan111`: Exists, `no shutdown`, **NO IP address** -> **OK for tunneling.**

**Conclusion:** The prerequisite *is met* on RCP-SPI-TOR-01 for the PoC C-VLAN 111.

## Configuration Examples (PoC - Focusing on Liverpool - London mirrors this for VLAN 111)

*(Using `ethernet1/1/56` for the **NEW dedicated PoC DAC link**. Using `ethernet1/1/35:1` on TOR1 as the JISC connection placeholder.)*

### 1. Liverpool Core1 Switch (RCP-SPI-CS-01) Configuration (PoC)

*   **Existing Link (Port-Channel 100):** Remove VLAN 111, ensure 10, 110, 2592 remain.
*   **New Dedicated Link (Eth 1/1/56):** Trunk port sending *only* C-VLAN 111 towards TOR1.

```bash
! On RCP-SPI-CS-01
config terminal

! --- Configuration for Existing Link to ToR (Standard Traffic) ---
interface port-channel100
  description "Link to TOR Switches (Std Traffic + Mgmt - PoC: VLAN 111 via Eth1/1/56)"
  no shutdown
  switchport mode trunk
  ! *** IMPORTANT: Remove tunneled C-VLAN 111, ensure others (10, 110, 2592) are present ***
  switchport trunk allowed vlan remove 111
  switchport trunk allowed vlan add 10,110,2592  ! Ensure these required VLANs are allowed
  ! (Verify existing allowed VLAN list is otherwise correct)

! --- Configuration for NEW Dedicated Link to TOR1 (QinQ Feed - VLAN 111 PoC) ---
interface ethernet1/1/56
  description "PoC Dedicated Link to TOR1 for QinQ C-VLAN 111"
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 111  ! *** ONLY allow the C-VLAN 111 for PoC ***
  no switchport access vlan

! --- SVI Status ---
! SVIs for 10, 110, 111, 2592 REMAIN ACTIVE on the Core - This is expected.
! show running-configuration interface Vlan111 (Should show IP 192.168.112.5/24)

end
write memory
```

### 2. Liverpool TOR1 Switch (RCP-SPI-TOR-01) Configuration (PoC)

*   **Global S-VLAN Definition:** Define S-VLAN 602 for QinQ.
*   **Existing Link (Port-Channel 100):** Standard trunk matching the Core, allowing 10, 110, 2592, excluding 111.
*   **New Dedicated Link (Eth 1/1/56):** QinQ Access Port for S-VLAN 602, receiving VLAN 111 from Core.
*   **ISP Link (Eth 1/1/35:1):** QinQ Trunk port.

```bash
! On RCP-SPI-TOR-01

config terminal

! --- Global S-VLAN Definition ---
interface vlan 602
  description "QinQ S-VLAN for JISC Tunnel (Mapped on ToR)"
  vlan-stack
  no shutdown

! --- Configuration for Existing Link to Core (Standard Traffic) ---
interface port-channel100
  description "Link to Core Switches (Std Traffic + Mgmt - PoC: VLAN 111 via Eth1/1/56)"
  no shutdown
  switchport mode trunk
  ! *** IMPORTANT: Mirror Core - Remove tunneled C-VLAN 111, ensure others (10, 110, 2592) are present ***
  switchport trunk allowed vlan remove 111
  switchport trunk allowed vlan add 10,110,2592  ! Ensure these required VLANs are allowed
  ! (Verify existing allowed VLAN list is otherwise correct)
  vlt-port-channel 100

! --- Configuration for NEW Dedicated Link from Core1 (QinQ Ingress - VLAN 111 PoC) ---
interface ethernet1/1/56
  description "PoC Dedicated Link from Core1 - QinQ Ingress for S-VLAN 602 (VLAN 111)"
  no shutdown
  switchport mode access
  switchport access vlan 602
  spanning-tree bpdufilter enable

! --- Configuration for Port facing ISP (QinQ Trunk) ---
interface ethernet1/1/35:1
  description "Link to ISP JISC - QinQ Trunk S-VLAN 602"
  no shutdown
  switchport mode trunk
  switchport trunk tpid 0x9100
  switchport trunk allowed vlan 602
  mtu 9216
  spanning-tree disable
  no switchport access vlan

! --- Verification of SVI Status on ToR ---
! CONFIRM tunneled VLAN (111) does NOT have an IP address
! show running-configuration interface Vlan111 | include ip address (Should return nothing)
! CONFIRM Management SVI (2592) IS active
! show running-configuration interface Vlan2592 | include ip address (Should show 172.24.192.6)

end
write memory
!
```

### 3. Liverpool TOR2 Switch (VLT Peer) Configuration (PoC)

*   Update Po100 to match TOR1.
*   Define S-VLAN 602.
*   Pre-configure Eth 1/1/56 (inactive).

```bash
! On RCP-SPI-TOR-01's VLT Peer (TOR2)

config terminal

! --- Global S-VLAN Definition --- (Apply on BOTH ToRs)
interface vlan 602
  description "QinQ S-VLAN for JISC Tunnel (Mapped on ToR)"
  vlan-stack
  no shutdown

! --- Configuration for Existing Link to Core (Standard Traffic) --- (Apply on BOTH ToRs)
interface port-channel100
  description "Link to Core Switches (Std Traffic + Mgmt - PoC: VLAN 111 via Eth1/1/56)"
  no shutdown
  switchport mode trunk
  ! *** IMPORTANT: Mirror TOR1 - Remove tunneled C-VLAN 111, ensure others (10, 110, 2592) are present ***
  switchport trunk allowed vlan remove 111
  switchport trunk allowed vlan add 10,110,2592  ! Ensure these required VLANs are allowed
  ! (Verify existing allowed VLAN list is otherwise correct)
  vlt-port-channel 100

! --- Pre-Configuration for NEW Dedicated Link from Core2 (QinQ Ingress - Future) ---
interface ethernet1/1/56
  description "PoC Dedicated Link from Core2 (Future) - QinQ Ingress for S-VLAN 602 (VLAN 111)"
  shutdown  ! Recommended to keep shutdown until physically connected
  switchport mode access
  switchport access vlan 602
  spanning-tree bpdufilter enable

end
write memory
!
```

### 4. London Site Configuration (PoC)

The configuration on the **London Core1** and **London TOR1** switches would **mirror this new Liverpool setup** *specifically for VLAN 111*:

*   **London Core1:** Po100 trunk removes VLAN 111, keeps 10, 110, Mgmt; New dedicated link Eth 1/1/56 trunking *only* C-VLAN 111; SVI for 111 remains active.
*   **London TOR1:** S-VLAN 602 `vlan-stack`; Po100 trunk removes 111, keeps 10, 110, Mgmt; New dedicated link Eth 1/1/56 as QinQ Access Port `access vlan 602`; ISP port as QinQ Trunk; **Must verify London TOR1 has no active SVI for 111**. Config applied consistently to London TOR2 VLT peer.

## Traffic Flow Summary (PoC - VLAN 111)

*   **Server (VLAN 111) London -> Server (VLAN 111) Liverpool:**
    1.  Frame (C-Tag 111) leaves London Server -> London TOR1.
    2.  London TOR1 sends frame (C-Tag 111) -> London Core1 (via standard trunk Po100).
    3.  London Core1 routes/switches, determines path is via QinQ tunnel -> Sends frame (C-Tag 111) out **dedicated PoC feed link Eth 1/1/56**.
    4.  Arrives London TOR1 **dedicated PoC feed port Eth 1/1/56** (QinQ Access Port) -> Associated with S-VLAN 602 (C-Tag 111 preserved).
    5.  Leaves London TOR1 ISP Port (QinQ Trunk) with Outer Tag S-VLAN 602 (TPID 0x9100) + Inner Tag C-VLAN 111.
    6.  Traverses JISC network.
    7.  Arrives Liverpool TOR1 ISP Port (QinQ Trunk) -> S-Tag 602 processed.
    8.  Leaves Liverpool TOR1 **dedicated PoC feed port Eth 1/1/56** (QinQ Access Port) -> S-Tag 602 stripped. Frame now has only C-Tag 111.
    9.  Arrives Liverpool Core1 via **dedicated PoC feed link Eth 1/1/56** (Standard Trunk) as Frame (C-Tag 111).
    10. Liverpool Core1 routes/switches frame -> Liverpool TOR1 (via standard trunk Po100).
    11. Liverpool TOR1 sends frame (C-Tag 111) -> Liverpool Server.
*   **Traffic for VLANs 10, 110, 2592:** Continues to flow normally over the Po100 trunk between Core and ToR, unaffected by the PoC changes or QinQ.
