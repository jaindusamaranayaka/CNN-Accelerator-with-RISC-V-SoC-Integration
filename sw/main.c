#include <stdint.h>
#include <stdbool.h>

#define UART_BASE       0x10000000
#define IMG_BRAM_BASE   0x20000000
#define OUT_BRAM_BASE   0x30000000
#define MAC_CTRL_BASE   0x40000000
#define GPIO_BASE       0x50000000

#define UART_DATA       (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_STATUS     (*(volatile uint32_t*)(UART_BASE + 0x04))

#define MAC_CTRL        (*(volatile uint32_t*)(MAC_CTRL_BASE + 0x00))
#define MAC_WEIGHTS_0   (*(volatile uint32_t*)(MAC_CTRL_BASE + 0x04))
#define MAC_WEIGHTS_1   (*(volatile uint32_t*)(MAC_CTRL_BASE + 0x08))
#define MAC_WEIGHTS_2   (*(volatile uint32_t*)(MAC_CTRL_BASE + 0x0C))
#define MAC_BIAS        (*(volatile uint32_t*)(MAC_CTRL_BASE + 0x10))
#define MAC_SHIFT       (*(volatile uint32_t*)(MAC_CTRL_BASE + 0x14))

#define OUT_RESULT      (*(volatile uint32_t*)(OUT_BRAM_BASE + 0x00))

#define GPIO_OUT        (*(volatile uint32_t*)(GPIO_BASE + 0x00))

#define MAC_CTRL_ENABLE      (1u << 0)
#define MAC_CTRL_RESULT_RDY  (1u << 1)

#define IMAGE_SIZE   784
#define KERNEL_TAPS  9
#define NUM_WINDOWS  676   /* (28-2) * (28-2) valid 3x3 windows */

static void uart_putchar(char c) {
    while ((UART_STATUS & 0x1) == 0);
    UART_DATA = (uint32_t)c;
}

static char uart_getchar(void) {
    while ((UART_STATUS & 0x2) == 0);
    return (char)(UART_DATA & 0xFF);
}

static void uart_send_byte(uint8_t b) {
    uart_putchar((char)b);
}

static void display_hex(uint32_t val) {
    GPIO_OUT = val;
}

static void load_weights(const int8_t weights[KERNEL_TAPS], int16_t bias, uint8_t shift_s) {
    uint32_t w0 = (uint32_t)(uint8_t)weights[0]
                | ((uint32_t)(uint8_t)weights[1] << 8)
                | ((uint32_t)(uint8_t)weights[2] << 16)
                | ((uint32_t)(uint8_t)weights[3] << 24);

    uint32_t w1 = (uint32_t)(uint8_t)weights[4]
                | ((uint32_t)(uint8_t)weights[5] << 8)
                | ((uint32_t)(uint8_t)weights[6] << 16)
                | ((uint32_t)(uint8_t)weights[7] << 24);

    uint32_t w2 = (uint32_t)(uint8_t)weights[8];

    MAC_WEIGHTS_0 = w0;
    MAC_WEIGHTS_1 = w1;
    MAC_WEIGHTS_2 = w2;
    MAC_BIAS      = (uint32_t)(uint16_t)bias;
    MAC_SHIFT     = (uint32_t)(shift_s & 0x1F);
}

int main(void) {
    display_hex(0x00000000);

    while (1) {
        char token = uart_getchar();
        if (token != 'S') continue;

        display_hex(0x11111111);

        /* Receive 9 weight bytes, 2 bias bytes, 1 shift byte */
        int8_t  weights[KERNEL_TAPS];
        int16_t bias;
        uint8_t shift_s;

        for (int i = 0; i < KERNEL_TAPS; i++)
            weights[i] = (int8_t)uart_getchar();

        uint8_t bias_lo = (uint8_t)uart_getchar();
        uint8_t bias_hi = (uint8_t)uart_getchar();
        bias    = (int16_t)((uint16_t)bias_hi << 8 | bias_lo);
        shift_s = (uint8_t)uart_getchar();

        load_weights(weights, bias, shift_s);

        /* Enable the datapath pipeline */
        MAC_CTRL = MAC_CTRL_ENABLE;

        display_hex(0x22222222);

        /* Stream 784 pixel bytes into the sliding window */
        volatile uint8_t *img = (volatile uint8_t *)IMG_BRAM_BASE;
        for (int i = 0; i < IMAGE_SIZE; i++)
            img[i] = (uint8_t)uart_getchar();

        display_hex(0x33333333);

        /* Collect NUM_WINDOWS convolution results and send back */
        uint32_t results_sent = 0;
        while (results_sent < NUM_WINDOWS) {
            if (MAC_CTRL & MAC_CTRL_RESULT_RDY) {
                uint32_t val = OUT_RESULT;  /* reading clears result_ready */
                uart_send_byte('R');
                uart_send_byte((uint8_t)(val & 0xFF));
                results_sent++;
            }
        }

        /* Disable pipeline */
        MAC_CTRL = 0;

        display_hex(0x44444444);
    }

    return 0;
}
