# QinQ Configuration: Core as Intermediate Mapper (Access Port Method)

## Goal

To establish a Layer 2 QinQ tunnel between the London site and the Liverpool site over the JISC ISP network, carrying **multiple production customer VLANs (C-VLANs)** trunked from the local ToR switch. This configuration uses the existing Core switch as the device performing the QinQ S-VLAN encapsulation/decapsulation, connecting to the ToR via the "QinQ Access Port Method".

**Key Parameters:**
*   **C-VLANs (Customer/Internal):** Multiple VLANs (e.g., 10, 20, 30, etc. - The specific list depends on requirements)
*   **S-VLAN (Service Provider/Tunnel):** VLAN 602 (Assigned by JISC)
*   **QinQ TPID (Tag Protocol Identifier):** 0x9100 (Required by JISC)

## CRITICAL PREREQUISITE: Disabling Core Switch SVIs

**This is the most crucial step for this configuration to function correctly.**

The Core switch designated to perform the QinQ mapping **MUST NOT** have active Layer 3 Switched Virtual Interfaces (SVIs, e.g., `interface Vlan10`, `interface Vlan20`) for **ANY** of the C-VLANs that are being tunneled through the S-VLAN.

**Why is this essential?**

Leaving the SVIs active on the mapping Core switch creates a fundamental conflict:

1.  **Routing vs. Bridging Conflict:** The active SVI tells the Core switch it is the Layer 3 gateway for that C-VLAN subnet. It will try to *route* traffic destined for that subnet locally and ARP for hosts within it. The QinQ configuration, however, tells the Core to blindly *bridge* (encapsulate) traffic for that C-VLAN into the S-VLAN tunnel when received on the designated QinQ port. The switch cannot logically do both for the same VLAN.
2.  **Routing Failures:** When the Core needs to send traffic to a device in a tunneled C-VLAN at the *remote* site, its routing table will point to the local SVI. It will attempt local ARP resolution instead of sending the traffic into the L2 QinQ tunnel. This **will cause routing to the remote site for that VLAN to fail.**
3.  **ARP Confusion:** The Core's ARP table may become unstable or contain incorrect entries as it gets confused between local ARP attempts via the SVI and potential responses coming back through the L2 tunnel.
4.  **Unpredictable Behavior:** Control plane traffic (like routing protocol updates, CDP/LLDP for the C-VLAN) associated with the active SVI might be incorrectly injected into the tunnel or handled locally, leading to unpredictable network behavior.

**Consequence:** Failure to disable the relevant SVIs on the mapping Core switch **will prevent Layer 3 communication** across the QinQ tunnel for those specific C-VLANs.

**Action:** Before applying or activating the QinQ configuration, ensure all SVIs corresponding to the C-VLANs you intend to tunnel are either **deleted** or administratively **shut down** on the Core switches (London and Liverpool) acting as the QinQ mappers.

## Configuration Examples

*(Note: Interface numbers are examples, adjust based on your physical connections. Replace `10,20,30` with your actual list/range of C-VLANs. Command syntax assumes Cisco-like IOS/NX-OS, adapt if using a different vendor)*

### 1. London ToR Switch Configuration

*   **Port facing Core Switch (e.g., Eth A):** This port sends standard tagged C-VLAN traffic *towards* the Core.

```
! Define the C-VLANs locally if not already done
vlan 10,20,30
  name Production_VLAN_10 ! etc.
!
interface EthernetA  // Or Port-Channel connected to Core Eth X
  description "Trunk Link to Core - Carrying Production C-VLANs"
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30 // *** Add ALL C-VLANs to be tunneled ***
  ! Alternatively, use ranges or 'add'/'remove' commands as appropriate
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

*   **Verification of SVI Status (Mandatory):** Ensure the L3 interfaces for **ALL** C-VLANs being tunneled are **NOT active**.

```
! On the Core Switch (RCP-SAP-CoreSR)
! CONFIRM these interfaces do NOT exist or are shutdown for ALL C-VLANs in the tunnel (e.g., 10, 20, 30)

! Option 1: Check they don't exist
! show run | include interface Vlan10
! show run | include interface Vlan20
! show run | include interface Vlan30
! ... etc ... (Should return nothing)

! Option 2: Check they are shutdown
! show ip interface brief | include Vlan10.*down
! show ip interface brief | include Vlan20.*down
! show ip interface brief | include Vlan30.*down
! ... etc ... (Should show 'administratively down' or similar)

! If necessary, configure:
! config t
!   no interface Vlan10
!   no interface Vlan20
!   no interface Vlan30
!   ... etc ...
!   OR
!   interface Vlan10
!     shutdown
!   interface Vlan20
!     shutdown
!   interface Vlan30
!     shutdown
!   ... etc ...
! end
! write memory
!
```

### 3. Liverpool Site Configuration

The configuration on the Liverpool Core (CS-01) and its connected ToR switch would mirror the London setup precisely, using the same S-VLAN (602) and TPID (0x9100) on the ISP-facing link, and allowing the corresponding local C-VLANs (e.g., 10, 20, 30) on the ToR-Core trunk. The Liverpool Core must also have the SVIs for these C-VLANs disabled as per the **CRITICAL PREREQUISITE**.

## Explanation of Key Concepts

1.  **Core as L2 Mapper:** By removing/disabling the relevant L3 SVIs, the Core is dedicated to Layer 2 QinQ mapping for this path.
2.  **ToR-Core Link (QinQ Access Port Method):**
    *   The ToR sends standard tagged C-VLAN frames.
    *   The Core receives these on the specially configured `access` port (Eth X) mapped to the `vlan-stack` enabled S-VLAN (602).
    *   This port automatically encapsulates various incoming C-VLAN tagged frames into S-VLAN 602 (preserving the C-Tag) and decapsulates traffic coming from S-VLAN 602 (stripping the S-Tag) before sending towards the ToR.
    *   This `trunk -> access` setup is standard for this QinQ method.
3.  **Core-ISP Link (QinQ Trunk):**
    *   Standard QinQ trunk using the ISP's TPID (0x9100), carrying only S-VLAN 602, with increased MTU.

## Traffic Flow Summary

*   **London ToR -> Liverpool ToR:**
    1.  Frame (e.g., C-Tag 10) leaves London ToR Eth A.
    2.  Arrives London Core Eth X -> Associated with S-VLAN 602 (C-Tag 10 preserved).
    3.  Leaves London Core Eth Y with Outer Tag S-VLAN 602 (TPID 0x9100) + Inner Tag C-VLAN 10.
    4.  Traverses JISC network.
    5.  Arrives Liverpool Core ISP Port -> S-Tag 602 processed.
    6.  Leaves Liverpool Core ToR-facing Port -> S-Tag 602 stripped.
    7.  Arrives Liverpool ToR Trunk Port as Frame (C-Tag 10).
*   The same flow applies concurrently for frames tagged with other tunneled C-VLANs (20, 30, etc.).
*   **Liverpool ToR -> London ToR:** Reverse of the above.

This configuration should reflect your requirement to tunnel multiple production VLANs using this method. Remember that disabling the corresponding SVIs on the Core switches acting as mappers is absolutely mandatory for successful L3 communication over the tunnel.