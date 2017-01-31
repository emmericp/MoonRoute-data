#ifndef MG_QUEUE_H
#define MG_QUEUE_H
#include <inttypes.h>

#include <rte_config.h>
#include <rte_common.h>
#include <rte_ring.h>

unsigned mg_queue_count_export(const struct rte_ring *r);
int mg_queue_dequeue_export(struct rte_ring *r, void **obj_p);
int mg_queue_enqueue_export(struct rte_ring *r, void *obj);

#endif
