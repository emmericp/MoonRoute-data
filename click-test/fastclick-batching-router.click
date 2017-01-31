 /*
  * tested with fastclick commit 8f3cd4fe6e85fcbe0c07fa2e15a7457d8a1af733, DPDK 2.2.0
  * simple unidirectional ipv4 fastclick dpdk router
  * doesn't do ARP lookups and error handling so it's slightly faster than a real router
  * based on snippets from fastclick/*.conf and IPOutputCombo
  */

define($smac 90:e2:ba:c3:76:6e)
define($srcip 10.0.0.1)

ip :: Strip(14)
    -> CheckIPHeader(INTERFACES 10.0.0.1/255.255.255.0)
    -> rt :: RangeIPLookup(
	10.1.0.10/255.255.255.255 1
	);

//Explained in loop.click
define($verbose 3)
define($blocking true)


//###################
// TX
//###################
td :: ToDPDKDevice(1, BLOCKING $blocking, VERBOSE $verbose)


//###################
// RX
//###################
fd0 :: FromDPDKDevice(0, PROMISC true, VERBOSE $verbose)
-> c1 :: Classifier(12/0800, 12/0806 20/0001, 12/0806 20/0002, -)

c1[0] -> Paint(0) -> ip
c1[1] -> Print("ARP QUERY") -> arp_r :: ARPResponder($srcip $smac) -> Print("OUR RESP") ->  td
c1[2] -> Print("ARP RESP") -> Discard
c1[3] -> Print("OTHER") -> Discard

outc :: IPOutputCombo(1, $srcip, 1500)



rt[0] -> Discard
rt[1] -> outc


outc[0] -> td
outc[1] -> Discard
outc[2] -> Discard
outc[3] -> Discard
outc[4] -> Discard

ControlSocket("TCP", 12345)
