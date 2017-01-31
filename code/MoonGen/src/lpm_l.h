/*-
 *   BSD LICENSE
 *
 *   Copyright(c) 2010-2014 Intel Corporation. All rights reserved.
 *   All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef __INCLUDE_MG_TABLE_LPM_H__
#define __INCLUDE_MG_TABLE_LPM_H__

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @file
 * RTE Table LPM for IPv4
 *
 * This table uses the Longest Prefix Match (LPM) algorithm to uniquely
 * associate data to lookup keys.
 *
 * Use-case: IP routing table. Routes that are added to the table associate a
 * next hop to an IP prefix. The IP prefix is specified as IP address and depth
 * and cover for a multitude of lookup keys (i.e. destination IP addresses)
 * that all share the same data (i.e. next hop). The next hop information
 * typically contains the output interface ID, the IP address of the next hop
 * station (which is part of the same IP network the output interface is
 * connected to) and other flags and counters.
 *
 * The LPM primitive only allows associating an 8-bit number (next hop ID) to
 * an IP prefix, while a routing table can potentially contain thousands of
 * routes or even more. This means that the same next hop ID (and next hop
 * information) has to be shared by multiple routes, which makes sense, as
 * multiple remote networks could be reached through the same next hop.
 * Therefore, when a route is added or updated, the LPM table has to check
 * whether the same next hop is already in use before using a new next hop ID
 * for this route.
 *
 * The comparison between different next hops is done for the first
 * “entry_unique_size” bytes of the next hop information (configurable
 * parameter), which have to uniquely identify the next hop, therefore the user
 * has to carefully manage the format of the LPM table entry (i.e.  the next
 * hop information) so that any next hop data that changes value during
 * run-time (e.g. counters) is placed outside of this area.
 *
 ***/

#include <stdint.h>

#include "rte_table.h"

//struct mg_table_lpm_routes {
//  struct mg_lpm4_table_entry entries[64];
//  uint64_t hit_mask;
//};
/** LPM table parameters */
struct rte_table_lpm_params {
	/** Maximum number of LPM rules (i.e. IP routes) */
	uint32_t n_rules;

	/** Number of bytes at the start of the table entry that uniquely
	identify the entry. Cannot be bigger than table entry size. */
	uint32_t entry_unique_size;

	/** Byte offset within input packet meta-data where lookup key (i.e.
	the destination IP address) is located. */
	uint32_t offset;
};


void *
mg_table_lpm_create(void *params, int socket_id, uint32_t entry_size);
int
mg_table_lpm_free(void *table);
int
mg_table_entry_add_simple(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry);
int
mg_table_lpm_entry_add(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry,
	int *key_found,
	void **entry_ptr);
int
mg_table_lpm_entry_delete(
	void *table,
  uint32_t ip,
  uint8_t depth,
	int *key_found,
	void *entry);
int
mg_table_lpm_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	uint64_t *lookup_hit_mask,
	void **entries);
#ifdef __cplusplus
}
void ** mg_lpm_table_allocate_entry_prts(uint16_t n_entries);
int mg_table_lpm_lookup_big_burst(
	void *table,
	struct rte_mbuf **pkts,
	struct mg_bitmask* pkts_mask,
	struct mg_bitmask* lookup_hit_mask,
	void **entries);
int mg_table_lpm_lookup_big_burst2_queue(
	void *table,
	struct rte_mbuf **pkts,
	struct mg_bitmask* in_mask,
	struct mg_bitmask* out_mask,
  struct rte_ring *r,
	void **entries);
int mg_table_lpm_apply_route(
	struct rte_mbuf **pkts,
  struct mg_bitmask* pkts_mask,
	void **entries,
  uint16_t offset_entry,
  uint16_t offset_pkt,
  uint16_t size);
int mg_table_lpm_apply_route_single(
	struct rte_mbuf *pkt,
	void **entry,
  uint16_t offset_entry,
  uint16_t offset_pkt,
  uint16_t size);
int mg_table_lpm_lookup_single(
	void *table,
	struct rte_mbuf *pkt,
	void **entry);
#endif

#endif
