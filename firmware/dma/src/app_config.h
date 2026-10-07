#ifndef ADB_APP_CONFIG_H
#define ADB_APP_CONFIG_H

#include "xparameters.h"

/* Example LAN: configure the sender in the same subnet. */
#define MY_IP_ADDR       "192.168.10.20"
#define MY_NETMASK       "255.255.255.0"
#define MY_GATEWAY       "192.168.10.1"
#define BOARD_MAC_ADDR   { 0x02, 0x00, 0x00, 0x00, 0x00, 0x20 }
#define UDP_SERVER_PORT  5001

#define THREAD_STACKSIZE 2048
#define QUEUE_LENGTH     10
#define CAMERA_HFOV_DEG  (55.0f)
#define SIZE_IS_PERCENT  0
/* 0: absolute inter-frame yaw change; 1: degrees per second. */
#define VEL_USE_DEG_PER_SEC 0
#define RX_TIMEOUT_MS    200

/* Register address from the exported hardware platform. */
#define FUZZY_BASE_ADDR  XPAR_MY_FUZZY_IP_0_BASEADDR

/* Poll budgets are iteration limits, not measured time intervals. */
#define DMA_POLL_BUDGET  1000000U
#define DMA_RESET_BUDGET 1000000U

#endif
