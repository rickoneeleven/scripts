# QinQ Configuration: Core as Intermediate Mapper (Access Port Method)

## Goal

To establish a Layer 2 QinQ tunnel between the London site and the Liverpool site over the JISC ISP network, carrying specific customer VLANs (C-VLANs, e.g., VLAN 111). This configuration uses the existing Core switch as the device performing the QinQ S-VLAN encapsulation/decapsulation, connecting to the local ToR switch (which originates the C-VLAN traffic) via the "QinQ Access Port Method".

**Key Parameters:**
*   **C-VLAN (Customer/Internal):** VLAN 111 (Example)
*   **S-VLAN (Service Provider/Tunnel):** VLAN 602 (Assigned by JISC)
*   **QinQ TPID (Tag Protocol Identifier):** 0x9100 (Required by JISC)

## Topology (Focus on London Side)

```mermaid
graph LR
    subgraph London Site
        ToR[London ToR Switch] -- Eth A (Trunk C-VLAN 111) --> CoreSR[London Core (RCP-SAP-CoreSR)\nRole: QinQ Mapper]
        CoreSR -- Eth X (QinQ Access Port / S-VLAN 602) --- CoreSR -- Eth Y (QinQ Trunk S-VLAN 602 / TPID 9100) --> ISP[(JISC Network)]
        ToR -- Access Ports --> EndDevices[Servers/PCs in VLAN 111]
    end

    ISP <-- S-VLAN 602 Tunnel --> Liverpool[Liverpool Site (Analogous Config)]

    style CoreSR fill:#f9f,stroke:#333,stroke-width:2px
```

*   **ToR Switch:** Trunks the internal C-VLAN (111) to the Core. May still hold the L3 SVI for VLAN 111 (e.g., `interface Vlan111`).
*   **Core Switch (RCP-SAP-CoreSR):** Acts solely as a Layer 2 QinQ mapper for this traffic path. **MUST NOT** have an active L3 SVI (`interface Vlan111`) for the C-VLAN being tunneled. Uses the special QinQ Access Port method on the ToR-facing interface.
*   **ISP Link:** Configured as a QinQ trunk carrying the S-VLAN (602) with the specific TPID (0x9100).

## Configuration Examples

*(Note: Interface numbers are examples, adjust based on your physical connections. Command syntax assumes Cisco-like IOS/NX-OS, adapt if using a different vendor)*

### 1. London ToR Switch Configuration

*   **Port facing Core Switch (e.g., Eth A):** This port sends standard tagged C-VLAN traffic *towards* the Core.

```
interface EthernetA  // Or Port-Channel connected to Core Eth X
  description "Trunk Link to Core - Carrying C-VLAN 111"
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 111 // Add other VLANs if needed, but 111 MUST be allowed
  no switchport access vlan
  ! Potentially add spanning-tree port type edge trunk or normal, depending on policy
!
```

### 2. London Core Switch (RCP-SAP-CoreSR) Configuration

*   **Global S-VLAN Definition:** Define the S-VLAN and mark it for QinQ operation.

```
! Define the S-VLAN ID provided by the ISP
interface vlan 602
  description "QinQ S-VLAN for JISC Tunnel"
  vlan-stack   ! IMPORTANT: Marks this VLAN for QinQ operations. (Syntax might be 'dot1q-tunnel' or similar on other platforms)
  no shutdown
!
```

*   **Port facing ToR Switch (e.g., Eth X - QinQ Ingress/Egress):** This uses the specific QinQ Access Port configuration.

```
interface EthernetX // Connected to ToR Eth A (e.g., 1/1/35:1)
  description "Link from ToR - QinQ Ingress/Egress for S-VLAN 602"
  no shutdown
  switchport mode access       ! *** Yes, ACCESS mode ***
  switchport access vlan 602   ! *** Assign to the S-VLAN ***
  spanning-tree disable        ! Recommended for QinQ ports to avoid STP issues
  ! or potentially configure BPDU Filter/Guard depending on exact needs/vendor
!
```

*   **Port facing ISP (e.g., Eth Y - QinQ Trunk):** This is the external QinQ trunk.

```
interface EthernetY // Connected to JISC (e.g., 1/1/27:1)
  description "Link to ISP JISC - QinQ Trunk S-VLAN 602"
  no shutdown
  switchport mode trunk
  switchport trunk tpid 0x9100   ! *** TPID required by ISP ***
  switchport trunk allowed vlan 602 ! *** ONLY allow the S-VLAN ***
  mtu 9216                     ! Accommodate QinQ overhead (S-Tag = 4 bytes)
  spanning-tree disable        ! Often recommended/required on P2P ISP links
  no switchport access vlan
!
```

*   **CRITICAL Prerequisite:** Ensure the L3 interface for the C-VLAN is NOT active on this Core switch.

```
! On the Core Switch (RCP-SAP-CoreSR)
! Ensure this interface does NOT exist or is shutdown:
! no interface Vlan111
! OR
! interface Vlan111
!   shutdown
!
```

### 3. Liverpool Site Configuration

The configuration on the Liverpool Core (CS-01) and its connected ToR switch would mirror the London setup precisely, using the same S-VLAN (602) and TPID (0x9100) on the ISP-facing link, and the corresponding local C-VLAN(s) and interface numbers for Liverpool.

## Explanation of Key Concepts

1.  **Core as L2 Mapper:** By removing/disabling `interface Vlan111` on the Core, we dedicate it to Layer 2 functions for this traffic path, avoiding the conflict of routing and QinQ mapping on the same SVI.
2.  **ToR-Core Link (QinQ Access Port Method):**
    *   The ToR sends standard 802.1Q tagged frames (C-Tag VLAN 111) over its trunk port (Eth A).
    *   The Core receives these tagged frames on its port Eth X.
    *   Because Eth X is configured as `switchport mode access`, `switchport access vlan 602`, *and* `interface Vlan 602` is marked `vlan-stack`, the switch applies special QinQ logic:
        *   **Ingress (ToR -> Core):** It accepts the incoming tagged frame (normally dropped by an access port), treats the *entire frame* (including the C-Tag 111) as payload, and associates it internally with S-VLAN 602.
        *   **Egress (Core -> ToR):** When traffic arrives from the ISP in S-VLAN 602 destined for Eth X, the Core removes the outer S-Tag (VLAN 602) and forwards the original inner frame (still tagged with C-VLAN 111) out Eth X towards the ToR.
    *   This `trunk -> access` setup **is valid and standard** for this specific QinQ ingress/egress method.
3.  **Core-ISP Link (QinQ Trunk):**
    *   This is a standard QinQ trunk port.
    *   `switchport trunk tpid 0x9100`: Tells the Core to use the ISP's required TPID when adding the S-Tag (VLAN 602) for outgoing traffic, and to expect incoming traffic tagged with S-VLAN 602 to use this TPID.
    *   `switchport trunk allowed vlan 602`: Ensures only the outer tunnel S-VLAN traverses this link.
    *   `mtu 9216`: Increases the interface MTU to handle the extra 4 bytes of the S-Tag without fragmenting standard 1500-byte Ethernet frames.

## Traffic Flow Summary

*   **London ToR -> Liverpool ToR:**
    1.  Frame (C-Tag 111) leaves London ToR Eth A.
    2.  Arrives London Core Eth X -> Associated with S-VLAN 602 (C-Tag 111 preserved).
    3.  Leaves London Core Eth Y with Outer Tag S-VLAN 602 (TPID 0x9100) + Inner Tag C-VLAN 111.
    4.  Traverses JISC network.
    5.  Arrives Liverpool Core ISP Port -> S-Tag 602 processed.
    6.  Leaves Liverpool Core ToR-facing Port (configured like London Eth X) -> S-Tag 602 stripped.
    7.  Arrives Liverpool ToR Trunk Port as Frame (C-Tag 111).
*   **Liverpool ToR -> London ToR:** Reverse of the above.

This configuration should provide the desired Layer 2 QinQ tunnel using your existing Core and ToR switches. Remember to apply analogous configurations on the Liverpool side.