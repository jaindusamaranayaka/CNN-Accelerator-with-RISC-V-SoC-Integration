#include <stdint.h>
#include <stdbool.h>

// ---------------------------------------------------------
// Memory Map Definitions
// ---------------------------------------------------------
#define UART_BASE       0x10000000
#define IMG_BRAM_BASE   0x20000000
#define OUT_BRAM_BASE   0x30000000
#define MAC_CTRL_BASE   0x40000000
#define GPIO_BASE       0x50000000

// UART Registers
#define UART_DATA       (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_STATUS     (*(volatile uint32_t*)(UART_BASE + 0x04))

// GPIO Register
#define GPIO_OUT        (*(volatile uint32_t*)(GPIO_BASE + 0x00))

// ---------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------
void uart_putchar(char c) {
    // Wait until TX is ready (bit 0 of status)
    while ((UART_STATUS & 0x1) == 0);
    UART_DATA = c;
}

char uart_getchar() {
    // Wait until RX is valid (bit 1 of status)
    while ((UART_STATUS & 0x2) == 0);
    return (char)(UART_DATA & 0xFF);
}

void display_hex(uint32_t val) {
    GPIO_OUT = val;
}

// ---------------------------------------------------------
// Main Firmware
// ---------------------------------------------------------
int main() {
    // 1. Initialization
    display_hex(0x00000000); // Clear display
    
    // 2. Main Loop
    while (1) {
        // Wait for 'S' character (Start token) from laptop
        char start_token = uart_getchar();
        if (start_token != 'S') {
            continue;
        }

        display_hex(0x11111111); // Indicate receiving

        // 3. Receive 28x28 image (784 bytes) from UART and write to BRAM
        volatile uint8_t* img_bram = (volatile uint8_t*)IMG_BRAM_BASE;
        for (int i = 0; i < 784; i++) {
            img_bram[i] = uart_getchar();
        }

        display_hex(0x22222222); // Indicate processing

        // 4. Trigger Hardware MAC
        volatile uint32_t* mac_ctrl = (volatile uint32_t*)MAC_CTRL_BASE;
        *mac_ctrl = 1; // Start MAC
        while((*mac_ctrl & 0x2) == 0); // Wait for done flag

        // 5. Read Classification Result from Output BRAM
        // Assuming the final classification result is stored at the first word of OUT_BRAM
        volatile uint32_t* out_bram = (volatile uint32_t*)OUT_BRAM_BASE;
        uint32_t real_digit = out_bram[0];

        // 6. Output result to 7-segment display and send back over UART
        display_hex(real_digit);
        uart_putchar('R'); // Result token
        uart_putchar((char)real_digit);
    }

    return 0;
}
