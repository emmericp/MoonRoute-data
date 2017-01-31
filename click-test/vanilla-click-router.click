// Shared IP input path and routing table
ip :: Strip(14)
    -> CheckIPHeader(INTERFACES 10.0.0.1/255.255.255.0 10.1.0.1/255.255.255.0)
    -> rt :: RangeIPLookup(
	10.1.0.10/255.255.255.255 2
	);

// ARP responses are copied to each ARPQuerier.
arpt :: Tee(2);

// Input and output paths for eth0
c0 :: Classifier(12/0806 20/0001, 12/0806 20/0002, 12/0800, -);
FromDPDKDevice(0) -> c0;
out0 :: ToDPDKDevice(0);
c0[0] -> ar0 :: ARPResponder(10.0.0.1 00:00:C0:3B:71:EF) -> out0;
arpq0 :: ARPQuerier(10.0.0.1, 00:00:C0:3B:71:EF) -> out0;
c0[1] -> arpt;
arpt[0] -> [1]arpq0;
c0[2] -> Paint(1) -> ip;
c0[3] -> Print("eth0 non-IP") -> Discard;

// Input and output paths for eth1
c1 :: Classifier(12/0806 20/0001, 12/0806 20/0002, 12/0800, -);
FromDPDKDevice(1) -> c1;
out1 :: ToDPDKDevice(1);
c1[0] -> ar1 :: ARPResponder(10.1.0.1 00:00:C0:CA:68:EF) -> out1;
arpq1 :: ARPQuerier(10.1.0.1, 00:00:C0:CA:68:EF) -> out1;
c1[1] -> arpt;
arpt[1] -> [1]arpq1;
c1[2] -> Paint(2) -> ip;
c1[3] -> Print("eth1 non-IP") -> Discard;

// no local delivery
rt[0] -> Discard;

// Forwarding path for eth0
rt[1] -> DropBroadcasts
    -> cp0 :: PaintTee(1)
    -> gio0 :: IPGWOptions(10.0.0.1)
    -> FixIPSrc(10.0.0.1)
    -> dt0 :: DecIPTTL
    -> [0]arpq0;
dt0[1] -> ICMPError(10.0.0.1, timeexceeded) -> rt;
gio0[1] -> ICMPError(10.0.0.1, parameterproblem) -> rt;
cp0[1] -> ICMPError(10.0.0.1, redirect, host) -> rt;

// Forwarding path for eth1
rt[2] -> DropBroadcasts
    -> cp1 :: PaintTee(2)
    -> gio1 :: IPGWOptions(10.1.0.1)
    -> FixIPSrc(10.1.0.1)
    -> dt1 :: DecIPTTL
    -> [0]arpq1;
dt1[1] -> ICMPError(10.1.0.1, timeexceeded) -> rt;
gio1[1] -> ICMPError(10.1.0.1, parameterproblem) -> rt;
cp1[1] -> ICMPError(10.1.0.1, redirect, host) -> rt;


ControlSocket("TCP", 12345)
