#ifndef MG_BITMASK_H
#define MG_BITMASK_H
#include <stdint.h>

struct mg_bitmask{
  uint16_t size;
  uint8_t n_blocks;
  uint64_t mask[0];
};
struct mg_bitmask * mg_bitmask_create(uint16_t size);
void mg_bitmask_free(struct mg_bitmask * mask);
void mg_bitmask_set_n_one(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_set_all_one(struct mg_bitmask * mask);
uint8_t mg_bitmask_get_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_set_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_clear_all(struct mg_bitmask * mask);
void mg_bitmask_clear_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_and(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_xor(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_or(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_not(struct mg_bitmask * mask1, struct mg_bitmask * result);
//uint8_t mg_bitmask_iterate_get(struct mg_bitmask * mask, uint16_t* i, uint64_t* submask);
//void mg_bitmask_iterate_set(struct mg_bitmask * mask, uint16_t* i, uint64_t** submask, uint8_t value);

// to start iterating: i initialized to 0, submask initialized (value does not matter)
// XXX: this will go horribly wrong, if called for an i>=mask.size
inline uint8_t mg_bitmask_iterate_get(struct mg_bitmask * mask, uint16_t* i, uint64_t* submask){
  //printf("get start i = %u\n", *i);
  //uint64_t a = rte_rdtsc();
  if(unlikely(*i%64 == 0)){
    *submask = mask->mask[*i/64];
  }
  uint8_t result = ((*submask & 1ULL) != 0ULL);
  *submask = *submask>>1;
  *i = *i +1;
  //printf("get done i = %u\n", *i);
  //uint64_t b = rte_rdtsc();
  //printf("iterat: %lu\n", b-a);
  return result;
}

// to start iterating: i initialized to 0, submask UNinitialized
// XXX: this will go horribly wrong, if called for an i>=mask.size
inline void mg_bitmask_iterate_set(struct mg_bitmask * mask, uint16_t* i, uint64_t** submask, uint8_t value){
  //printf("set start i = %u\n", *i);
  if(unlikely(((*i)%64) == 0)){
    *submask = &mask->mask[*i/64];
    //printf("mod\n");
    //*submask = 0ULL; // not needed, as we shift through in the end anyways
  }
  //printf("pshift\n");
  **submask = (**submask)>>1;
  //printf("ashift\n");
  if(value){
    //printf("true\n");
    **submask = **submask | 0x8000000000000000UL;
  }
  //printf("msk %lx\n", **submask);
  *i = *i + 1;
  if(unlikely(*i==mask->size)){
    //printf("end\n");
    **submask = **submask>>(*i%64);
    //printf("msk %lx\n", **submask);
  }
  //printf("set done i = %u\n", *i);
}
inline uint8_t mg_bitmask_get_bit_inline(struct mg_bitmask * mask, uint16_t n){
  return ( (mask->mask[n/64] & (1ULL<< (n&0x3f))) != 0);
}

inline void mg_bitmask_set_bit_inline(struct mg_bitmask * mask, uint16_t n){
  //printf(" CC set bit nr %d\n", n);
  //printhex("mask = ", mask->mask, 8*3);
  mask->mask[n/64] |= (1ULL<< (n&0x3f));
  //printhex("mask = ", mask->mask, 8*3);
}
inline void mg_bitmask_clear_bit_inline(struct mg_bitmask * mask, uint16_t n){
  mask->mask[n/64] &= ~(1ULL<< (n&0x3f));
}
#endif
