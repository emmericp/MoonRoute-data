#include "ipv4.h"
#include "bitmask.h"
#include <rte_config.h>
#include <rte_common.h>
#include <rte_mbuf.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_ring.h>
#include <stdlib.h>

union ip4_address {
  uint8_t		uint8[4];
  uint32_t	uint32;
};

union ip4_address mg_ipv4_get_random_address(){
  union ip4_address result;
  result.uint32 = rand();
  //result.uint32 = 0;
  return result;
}

void mg_ipv4_check_valid2(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask
    ){
  //printf("start check valid\n");
  mg_bitmask_clear_all(out_mask);
  uint16_t i = 0;
  uint64_t iterator_mask = 0;
  uint16_t i_o = 0;
  uint64_t * iterator_mask_2 = 0;
  //printf("loop\n");
  while(i<in_mask->size){
    //printf("i=%u\n", i);
    uint8_t value = 0;
    if(mg_bitmask_iterate_get(in_mask, &i, &iterator_mask)){
      //printf("have to process\n");
      uint16_t flags = pkts[i-1]->ol_flags;
      if(
          (((PKT_RX_IPV4_HDR | PKT_RX_IPV4_HDR_EXT) & flags) != 0)
          &&
          ((PKT_RX_IP_CKSUM_BAD & flags) == 0)
          &&
          (pkts[i-1]->pkt.data_len >= 20)
          &&
          // we do not check this against the real header length, but against 20
          // as we do not support reading/writing options in the ip header anyways
          (((struct ipv4_hdr*)(pkts[i]->pkt.data + ETHER_HDR_LEN))->total_length >=20)
        ){
        //printf("is valid\n");
        value = 1;
      }
    }
    //printf("set: %u\n", value);
    //printf("i=%u\n", i);
    mg_bitmask_iterate_set(out_mask, &i_o, &iterator_mask_2, value);
  }
  //printf("done check valid\n");
}

// for each packet, which is valid IPv4, the corresponding bit in the
// out_mask is set.
// for each packet, which is invalid, the corresponding bit in the out_mask
// is cleared.
// Note, that if a bit in in_mask is not set, the corresponding bit in the
// out_mask is not touched.
void mg_ipv4_check_valid(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask
    ){
  uint16_t i;
  for(i=0; i< in_mask->size; i++){
    if(mg_bitmask_get_bit_inline(in_mask, i)){
      uint16_t flags = pkts[i]->ol_flags;
      if(
          (((PKT_RX_IPV4_HDR | PKT_RX_IPV4_HDR_EXT) & flags) != 0)
          &&
          ((PKT_RX_IP_CKSUM_BAD & flags) == 0)
          &&
          (pkts[i]->pkt.data_len >= 20)
          &&
          // we do not check this against the real header length, but against 20
          // as we do not support reading/writing options in the ip header anyways
          (((struct ipv4_hdr*)(pkts[i]->pkt.data + ETHER_HDR_LEN))->total_length >=20)
        ){
        mg_bitmask_set_bit_inline(out_mask, i);
      }else{
        mg_bitmask_set_bit_inline(out_mask, i);

      }
    }
  }
}
uint8_t mg_ipv4_check_valid_single(
    struct rte_mbuf *pkt
    ){
      uint16_t flags = pkt->ol_flags;
      if(
          (((PKT_RX_IPV4_HDR | PKT_RX_IPV4_HDR_EXT) & flags) != 0)
          &&
          ((PKT_RX_IP_CKSUM_BAD & flags) == 0)
          &&
          (pkt->pkt.data_len >= 20)
          &&
          // we do not check this against the real header length, but against 20
          // as we do not support reading/writing options in the ip header anyways
          (((struct ipv4_hdr*)(pkt->pkt.data + ETHER_HDR_LEN))->total_length >=20)
        ){
        return 1;
      }else{
        return 0;
      }
}


// enqueues all pkts with expired TTL into the given queue
void mg_ipv4_decrement_ttl_queue(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask,
    struct rte_ring *r
    ){
  uint16_t i;
  for(i=0; i< in_mask->size; i++){
    if(mg_bitmask_get_bit_inline(in_mask, i)){
      struct ipv4_hdr * ip_hdr = (struct ipv4_hdr*)(pkts[i]->pkt.data + ETHER_HDR_LEN);
      // according to RFC 1812 we should discard the packet, as soon as we
      // decrement to 0. So we check for ttl > 1 here:
      if(ip_hdr->time_to_live > 1){
        ip_hdr->time_to_live --;
        mg_bitmask_set_bit_inline(out_mask, i);
      }else{
        mg_bitmask_clear_bit_inline(out_mask, i);
        int result = rte_ring_mp_enqueue_bulk(r, (void*)(&pkts[i]), 1);
        if (result != 0){
          rte_pktmbuf_free(pkts[i]);
        }
      }
    }
  }
}
void mg_ipv4_decrement_ttl(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask
    ){
  uint16_t i;
  for(i=0; i< in_mask->size; i++){
    if(mg_bitmask_get_bit_inline(in_mask, i)){
      struct ipv4_hdr * ip_hdr = (struct ipv4_hdr*)(pkts[i]->pkt.data + ETHER_HDR_LEN);
      // according to RFC 1812 we should discard the packet, as soon as we
      // decrement to 0. So we check for ttl > 1 here:
      if(ip_hdr->time_to_live > 1){
        ip_hdr->time_to_live --;
        mg_bitmask_set_bit_inline(out_mask, i);
      }else{
        mg_bitmask_clear_bit_inline(out_mask, i);
      }
    }
  }
}

void mg_ipv4_print_ip(uint32_t ip){
  uint8_t * i = (uint8_t*)(&ip);
  printf("%d.%d.%d.%d\n", i[3], i[2], i[1], i[0]);
}
