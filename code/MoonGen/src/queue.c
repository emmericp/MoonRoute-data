#include <rte_config.h>
#include <rte_common.h>
#include <rte_ring.h>
#include <rte_mbuf.h>
#include "queue.h"


int mg_queue_enqueue_export(struct rte_ring *r, void *obj){

  struct rte_mbuf* buf = (struct rte_mbuf*)obj;
  // FIXME: remove this debugging output, as soon, as it does not occur anymore
  if(obj == NULL){
    printf("enqAHHH NULLLLL\n");
    exit(0);
  }
  //printf("enq len = %u\n", buf->pkt.data_len);
  int result =  rte_ring_mp_enqueue_bulk(r, &obj, 1);
  //printf("f");
  return result;
}

int mg_queue_dequeue_export(struct rte_ring *r, void **obj_p){
  //printf("a\n");
  int result = rte_ring_mc_dequeue_bulk(r, obj_p, 1);
  //printf("b\n");
  if(result == 0){
    struct rte_mbuf* buf = (struct rte_mbuf*)(*obj_p);
    // FIXME: remove this debugging output, as soon, as it does not occur anymore
    if(buf == NULL){
      printf("deqAHHH NULLLLL\n");
      exit(0);
    }
    //printf("deq len = %u\n", buf->pkt.data_len);
  }
  //printf("c\n");
  return result;
}

unsigned mg_queue_count_export(const struct rte_ring *r)
{
	uint32_t prod_tail = r->prod.tail;
	uint32_t cons_tail = r->cons.tail;
	return ((prod_tail - cons_tail) & r->prod.mask);
}
