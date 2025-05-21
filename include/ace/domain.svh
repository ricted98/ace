`ifndef ACE_DOMAIN_SVH_
`define ACE_DOMAIN_SVH_

  //////////////////
  // Domain types //
  //////////////////

`define DOMAIN_BV_T(__width) \
    logic [__width-1:0]

`define DOMAIN_RULE_T(__bv_t) \
    struct packed { \
        __bv_t initiator; \
        __bv_t inner;     \
        __bv_t outer;     \
    }

`define DOMAIN_TYPEDEF_BV_T(__width, __bv_t) \
    typedef logic [__width-1:0] __bv_t;

`define DOMAIN_TYPEDEF_RULE_T(__bv_t, __set_t) \
    typedef struct packed { \
        __bv_t initiator; \
        __bv_t inner;     \
        __bv_t outer;     \
    } __set_t;

`define DOMAIN_TYPEDEF_ALL(__width, __bv_t, __set_t) \
    `DOMAIN_TYPEDEF_BV_T(__width, __bv_t) \
    `DOMAIN_TYPEDEF_RULE_T(__bv_t, __set_t)

`endif // ACE_DOMAIN_SVH_
