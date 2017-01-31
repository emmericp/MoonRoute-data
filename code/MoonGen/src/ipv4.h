#ifndef MG_IPV4_H
#define MG_IPV4_H
#include <inttypes.h>
#include <rte_config.h>
#include <rte_common.h>
#include <rte_mbuf.h>
#include "bitmask.h"

void mg_ipv4_check_valid(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask
    );

void mg_ipv4_check_valid2(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask
    );
uint8_t mg_ipv4_check_valid_single(
    struct rte_mbuf *pkt
    );

void mg_ipv4_decrement_ttl(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask
    );

void mg_ipv4_decrement_ttl_queue(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask,
    struct rte_ring *r
    );

#endif
