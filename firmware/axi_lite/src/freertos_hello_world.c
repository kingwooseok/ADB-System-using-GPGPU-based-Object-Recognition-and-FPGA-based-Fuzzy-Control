/*
 * Adaptive Driving Beam: FreeRTOS/lwIP receiver.
 * UDP payload: x_left x_right size (normalized floats).
 * size is bounding-box area / image area, mapped to the RTL Width input.
 * PS-to-PL input: AXI4-Lite reference.
 * AXI4-Lite: configuration writes and result reads.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "app_config.h"

#include "xparameters.h"
#include "xil_printf.h"
#include "xil_io.h"

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"

#include "netif/xadapter.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/init.h"
#include "lwip/inet.h"

#define OFF_FUZZ            0x000
#define MF_STRIDE_BYTES     0x18

#define OFF_RULE_DC_BASE    0x100
#define OFF_RULE_LIN_BASE   0x128

#define OFF_DEFUZZ_DC_BASE  0x200
#define OFF_DEFUZZ_LIN_BASE 0x214

#define OFF_INPUT           0x300
#define OFF_IN_ANGLE        (OFF_INPUT + 0x00)
#define OFF_IN_VEL          (OFF_INPUT + 0x04)
#define OFF_IN_WIDTH        (OFF_INPUT + 0x08)
#define OFF_CTRL            (OFF_INPUT + 0x0C)

#define OFF_OUT_DC          0x00
#define OFF_OUT_LIN         0x04

#define MF_OFF_A          0x00
#define MF_OFF_B          0x04
#define MF_OFF_C          0x08
#define MF_OFF_D          0x0C
#define MF_OFF_SLOPE_AB   0x10
#define MF_OFF_SLOPE_DC   0x14

enum {
    MF_ANG_NB = 0, MF_ANG_NM = 1, MF_ANG_ZE = 2, MF_ANG_PM = 3, MF_ANG_PB = 4,
    MF_VEL_SLOW = 5, MF_VEL_FAST = 6,
    MF_WID_SHORT = 7, MF_WID_LONG  = 8
};

typedef struct {
    float x_left;
    float x_right;
    float size;
} CoordData_t;

static struct netif server_netif;
static QueueHandle_t xCoordQueue;
static SemaphoreHandle_t xFuzzyReady;

#define ABS_F(x) (((x) < 0.0f) ? -(x) : (x))

static inline float clamp_f(float v, float lo, float hi){
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static inline float x_norm_to_yaw_deg(float x_norm) {
    return (x_norm - 0.5f) * CAMERA_HFOV_DEG;
}

static inline float ang_scale(void) {
    return (1000.0f / (CAMERA_HFOV_DEG * 0.5f));
}

static inline void Fuzzy_Write(u32 offset, s32 value) {
    Xil_Out32(FUZZY_BASE_ADDR + offset, (u32)value);
}

static inline s32 Fuzzy_Read(u32 offset) {
    return (s32)Xil_In32(FUZZY_BASE_ADDR + offset);
}

static void Fuzzy_Config_MF(int mf_index, s32 a, s32 b, s32 c, s32 d) {
    s32 slope_ab = 0;
    s32 slope_dc = 0;
    if (b > a) slope_ab = (255 * 256) / (b - a);
    if (d > c) slope_dc = (255 * 256) / (d - c);

    u32 base = OFF_FUZZ + (mf_index * MF_STRIDE_BYTES);
    Fuzzy_Write(base + MF_OFF_A, a);
    Fuzzy_Write(base + MF_OFF_B, b);
    Fuzzy_Write(base + MF_OFF_C, c);
    Fuzzy_Write(base + MF_OFF_D, d);
    Fuzzy_Write(base + MF_OFF_SLOPE_AB, slope_ab);
    Fuzzy_Write(base + MF_OFF_SLOPE_DC, slope_dc);
}

static void Fuzzy_Config_Rule(int rule_index, s32 action_index) {
    if (rule_index >= 0 && rule_index <= 9) {
        Fuzzy_Write(OFF_RULE_DC_BASE + (rule_index * 4), action_index);
    } else if (rule_index == 10 || rule_index == 11) {
        Fuzzy_Write(OFF_RULE_LIN_BASE + ((rule_index - 10) * 4), action_index);
    }
}

static void Fuzzy_Config_Defuzz(int defuzz_index, s32 singleton_value) {
    if (defuzz_index >= 0 && defuzz_index <= 4) {
        Fuzzy_Write(OFF_DEFUZZ_DC_BASE + (defuzz_index * 4), singleton_value);
    } else if (defuzz_index == 5 || defuzz_index == 6) {
        Fuzzy_Write(OFF_DEFUZZ_LIN_BASE + ((defuzz_index - 5) * 4), singleton_value);
    }
}

static inline void Fuzzy_Write_Input(s32 ang_in, s32 vel_in, s32 wid_in) {
    Fuzzy_Write(OFF_IN_ANGLE, ang_in);
    Fuzzy_Write(OFF_IN_VEL,   vel_in);
    Fuzzy_Write(OFF_IN_WIDTH, wid_in);
    Fuzzy_Write(OFF_CTRL,     1);
}

static void Fuzzy_System_Init(void) {
    xil_printf("[FUZZY] Init start (HFOV=55)\r\n");

    Fuzzy_Config_MF(MF_ANG_NB, -1000, -1000,  -650,  -300);
    Fuzzy_Config_MF(MF_ANG_NM,  -650,  -300,  -300,     0);
    Fuzzy_Config_MF(MF_ANG_ZE,  -180,   -60,    60,   180);
    Fuzzy_Config_MF(MF_ANG_PM,     0,   300,   300,   650);
    Fuzzy_Config_MF(MF_ANG_PB,   300,   650,  1000,  1000);

    Fuzzy_Config_MF(MF_VEL_SLOW,   0,    0,    90,   160);
    Fuzzy_Config_MF(MF_VEL_FAST, 120, 180,   600,   600);

    Fuzzy_Config_MF(MF_WID_SHORT,   0,    0,   180,   280);
    Fuzzy_Config_MF(MF_WID_LONG,  220, 320,  1000,  1000);

    #define RULE_IDX(angle5, vel2) ((angle5)*2 + (vel2))
    #define VEL_SLOW 0
    #define VEL_FAST 1

    Fuzzy_Config_Rule(RULE_IDX(0, VEL_SLOW), 4);
    Fuzzy_Config_Rule(RULE_IDX(1, VEL_SLOW), 3);
    Fuzzy_Config_Rule(RULE_IDX(2, VEL_SLOW), 2);
    Fuzzy_Config_Rule(RULE_IDX(3, VEL_SLOW), 1);
    Fuzzy_Config_Rule(RULE_IDX(4, VEL_SLOW), 0);

    Fuzzy_Config_Rule(RULE_IDX(0, VEL_FAST), 3);
    Fuzzy_Config_Rule(RULE_IDX(1, VEL_FAST), 2);
    Fuzzy_Config_Rule(RULE_IDX(2, VEL_FAST), 2);
    Fuzzy_Config_Rule(RULE_IDX(3, VEL_FAST), 2);
    Fuzzy_Config_Rule(RULE_IDX(4, VEL_FAST), 1);

    Fuzzy_Config_Rule(10, 0);
    Fuzzy_Config_Rule(11, 1);

    Fuzzy_Config_Defuzz(0, -45);
    Fuzzy_Config_Defuzz(1, -20);
    Fuzzy_Config_Defuzz(2,   0);
    Fuzzy_Config_Defuzz(3,  20);
    Fuzzy_Config_Defuzz(4,  45);
    Fuzzy_Config_Defuzz(5,  10);
    Fuzzy_Config_Defuzz(6,  50);

    xil_printf("[FUZZY] Init done\r\n");
}

static void print_ip_settings(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw) {
    xil_printf("\r\n--- IP Config ---\r\n");
    xil_printf("Board IP: %s\r\n", ipaddr_ntoa(ip));
    xil_printf("Netmask : %s\r\n", ipaddr_ntoa(mask));
    xil_printf("Gateway : %s\r\n", ipaddr_ntoa(gw));
    xil_printf("-----------------\r\n");
}

static void network_init_thread(void *p);
static void producer_udp_task(void *p);
static void fuzzy_init_task(void *p);
static void fuzzy_runtime_task(void *p);

int main(void) {
    xil_printf("\r\n--- START: UDP -> (yaw/vel/width) -> AXI-Lite ---\r\n");
    xCoordQueue = xQueueCreate(QUEUE_LENGTH, sizeof(CoordData_t));
    xFuzzyReady = xSemaphoreCreateBinary();

    if (!xCoordQueue || !xFuzzyReady) {
        xil_printf("Queue/Semaphore create failed.\r\n");
        return -1;
    }

    sys_thread_new("network_init", network_init_thread, NULL, THREAD_STACKSIZE, DEFAULT_THREAD_PRIO);
    vTaskStartScheduler();
    return 0;
}

static void network_init_thread(void *p) {
    (void)p;
    ip_addr_t ipaddr, netmask, gw;
    unsigned char mac_ethernet_address[] = BOARD_MAC_ADDR;

    lwip_init();
    if (!inet_aton(MY_IP_ADDR, &ipaddr) ||
        !inet_aton(MY_NETMASK, &netmask) ||
        !inet_aton(MY_GATEWAY, &gw)) {
        xil_printf("Invalid network configuration\r\n");
        vTaskDelete(NULL);
        return;
    }

    if (!xemac_add(&server_netif, &ipaddr, &netmask, &gw, mac_ethernet_address, XPAR_XEMACPS_0_BASEADDR)) {
        xil_printf("Error adding N/W interface\r\n");
        vTaskDelete(NULL);
        return;
    }

    netif_set_default(&server_netif);
    netif_set_up(&server_netif);
    print_ip_settings(&ipaddr, &netmask, &gw);

    sys_thread_new("xemacif_input", (void (*)(void *))xemacif_input_thread, &server_netif, THREAD_STACKSIZE, DEFAULT_THREAD_PRIO);
    sys_thread_new("producer_udp", producer_udp_task, NULL, THREAD_STACKSIZE, DEFAULT_THREAD_PRIO);
    sys_thread_new("fuzzy_init", fuzzy_init_task, NULL, THREAD_STACKSIZE, DEFAULT_THREAD_PRIO);
    sys_thread_new("fuzzy_run", fuzzy_runtime_task, NULL, THREAD_STACKSIZE, DEFAULT_THREAD_PRIO);

    vTaskDelete(NULL);
}

static void producer_udp_task(void *p) {
    (void)p;
    int sock;
    struct sockaddr_in server_addr, remote_addr;
    socklen_t addr_len = sizeof(remote_addr);
    char recv_buf[1024];
    int recv_len;
    CoordData_t d;
    char trailing;

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        xil_printf("Socket Error\r\n");
        vTaskDelete(NULL);
        return;
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(UDP_SERVER_PORT);
    server_addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        xil_printf("Bind Error\r\n");
        lwip_close(sock);
        vTaskDelete(NULL);
        return;
    }
    xil_printf("[Producer] Ready on port %d\r\n", UDP_SERVER_PORT);

    while (1) {
        addr_len = sizeof(remote_addr);
        recv_len = recvfrom(sock, recv_buf, sizeof(recv_buf) - 1, 0, (struct sockaddr *)&remote_addr, &addr_len);
        if (recv_len > 0) {
            recv_buf[recv_len] = 0;
            if (sscanf(recv_buf, "%f %f %f %c", &d.x_left, &d.x_right,
                       &d.size, &trailing) == 3 &&
                isfinite(d.x_left) && isfinite(d.x_right) && isfinite(d.size)) {
                (void)xQueueSend(xCoordQueue, &d, 0);
            }
        }
    }
}

static void fuzzy_init_task(void *p) {
    (void)p;
    Fuzzy_System_Init();
    xSemaphoreGive(xFuzzyReady);
    vTaskDelete(NULL);
}

static void fuzzy_runtime_task(void *p) {
    (void)p;
    xSemaphoreTake(xFuzzyReady, portMAX_DELAY);

    CoordData_t r;
    float yaw_prev = 0.0f;
    TickType_t last_tick = xTaskGetTickCount();
    TickType_t last_rx_tick = last_tick;
    const float k = ang_scale();

    while (1) {
        if (xQueueReceive(xCoordQueue, &r, pdMS_TO_TICKS(20)) == pdPASS) {
            last_rx_tick = xTaskGetTickCount();

            r.x_left  = clamp_f(r.x_left,  0.0f, 1.0f);
            r.x_right = clamp_f(r.x_right, 0.0f, 1.0f);
            if (r.x_right < r.x_left) { float t = r.x_left; r.x_left = r.x_right; r.x_right = t; }

#if SIZE_IS_PERCENT
            r.size = r.size / 100.0f;
#endif
            r.size = clamp_f(r.size, 0.0f, 1.0f);

            float thL = x_norm_to_yaw_deg(r.x_left);
            float thR = x_norm_to_yaw_deg(r.x_right);
            float yaw = 0.5f * (thL + thR);

            TickType_t now = xTaskGetTickCount();
            float dt_ms = (float)(now - last_tick) * (1000.0f / configTICK_RATE_HZ);
            if (dt_ms < 1.0f) dt_ms = 1.0f;
            last_tick = now;

            float dyaw = ABS_F(yaw - yaw_prev);
            yaw_prev = yaw;
            float vel = dyaw;
#if VEL_USE_DEG_PER_SEC
            vel = dyaw * (1000.0f / dt_ms);
#endif

            s32 ang_in = (s32)(yaw * k);
            s32 vel_in = (s32)(vel * k);
            s32 wid_in = (s32)(r.size * 1000.0f);

            if (ang_in >  1200) ang_in =  1200;
            if (ang_in < -1200) ang_in = -1200;
            if (vel_in < 0) vel_in = 0;
            if (vel_in > 2000) vel_in = 2000;
            if (wid_in < 0) wid_in = 0;
            if (wid_in > 1000) wid_in = 1000;

            Fuzzy_Write_Input(ang_in, vel_in, wid_in);

            for(volatile int dly=0; dly<500; dly++);

            s32 res_dc  = Fuzzy_Read(OFF_OUT_DC);
            s32 res_lin = Fuzzy_Read(OFF_OUT_LIN);

            xil_printf("[CHK] In(A:%d, V:%d, W:%d) -> Out(DC:%d, LIN:%d)\r\n",
                       (int)ang_in, (int)vel_in, (int)wid_in, (int)res_dc, (int)res_lin);
        }

        TickType_t t = xTaskGetTickCount();
        float since_ms = (float)(t - last_rx_tick) * (1000.0f / configTICK_RATE_HZ);
        if (since_ms > RX_TIMEOUT_MS) {
            Fuzzy_Write_Input(0, 0, 0);
            last_rx_tick = t;

        }
    }
}
