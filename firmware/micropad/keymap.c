// MicroPad — firmware for the Work Louder Creator Micro (QMK, keymap "micropad")
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Two modes:
//  - "host": the MicroPad app on the Mac is connected. The pad sends no keycodes, only
//    raw events (key N down / up, encoder N +/-) over Raw HID.
//    The app decides the key colors.
//  - "standalone": if the app hasn't answered for 3 seconds, the pad behaves
//    like a normal keyboard with the keymap below.
//
// Protocol (32-byte packets):
//  Pad -> Mac
//    0x01 key      [1]=index 0-15 (row*4+col)  [2]=1 down / 0 up
//    0x02 encoder  [1]=index 0-1               [2]=1 clockwise / 0 counter-clockwise
//    0x03 hello    [1]=protocol version
//  Mac -> Pad
//    0x10 ping           (heartbeat, the pad answers with hello)
//    0x11 release        (the app is quitting: go standalone right away)
//    0x20 key colors     [1]=first index [2]=count (max 9) then r,g,b per key
//    0x21 fill           [1..3]=r,g,b for all keys
//    0x22 flash          [1..3]=r,g,b [4]=times (0 = until a key is pressed) [5]=phase length in 10 ms
//    0x23 brightness     [1]=0-255
//    0x24 indicators     [1]=bitmask of the 3 small LEDs
//    0x25 underglow      [1..3]=r,g,b

#include QMK_KEYBOARD_H
#include "raw_hid.h"
#include <string.h>

#ifndef RAW_EPSIZE
#    define RAW_EPSIZE 32
#endif

#define MP_PROTOCOL_VERSION 1
#define MP_HOST_TIMEOUT_MS 3000
#define MP_MAX_BRIGHTNESS 150 // same limit as the stock firmware (USB power budget)

enum mp_packets {
    MP_EVT_KEY        = 0x01,
    MP_EVT_ENCODER    = 0x02,
    MP_EVT_HELLO      = 0x03,
    MP_CMD_PING       = 0x10,
    MP_CMD_RELEASE    = 0x11,
    MP_CMD_KEY_COLORS = 0x20,
    MP_CMD_FILL       = 0x21,
    MP_CMD_FLASH      = 0x22,
    MP_CMD_BRIGHTNESS = 0x23,
    MP_CMD_INDICATORS = 0x24,
    MP_CMD_UNDERGLOW  = 0x25,
};

enum layers { _BASE, _FN };

// Keymap used only in standalone mode (app not running). Generic Mac shortcuts.
// Holding the bottom-left corner key opens the FN layer,
// which has QK_BOOT to enter the bootloader without unplugging.
const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [_BASE] = LAYOUT(
        KC_MPLY,  G(KC_Z),  LSG(KC_Z), KC_MUTE,
        G(KC_C),  G(KC_V),  G(KC_X),   G(KC_A),
        G(KC_S),  G(KC_F),  G(KC_T),   G(KC_W),
        MO(_FN),  LSG(KC_4), G(KC_SPC), KC_ENT
    ),
    [_FN] = LAYOUT(
        QK_BOOT,  RM_TOGG,  RM_NEXT,   _______,
        RM_VALD,  RM_VALU,  RM_HUED,   RM_HUEU,
        _______,  _______,  _______,   _______,
        _______,  _______,  _______,   _______
    ),
};

// ---------------------------------------------------------------------------
// State

static bool     host_active    = false;
static uint32_t host_last_seen = 0;
static uint8_t  key_rgb[MATRIX_ROWS * MATRIX_COLS][3];
static uint8_t  brightness     = MP_MAX_BRIGHTNESS;
static uint16_t pressed_mask   = 0;

static uint8_t  flash_rgb[3];
static uint8_t  flash_phases   = 0;     // even = on, odd = off
static bool     flash_sticky   = false; // flash until a key is pressed
static uint16_t flash_period   = 250;
static uint32_t flash_timer    = 0;

static uint8_t scale(uint8_t v) {
    return (uint16_t)v * brightness / 255;
}

static void send_packet(uint8_t a, uint8_t b, uint8_t c) {
    uint8_t buf[RAW_EPSIZE];
    memset(buf, 0, sizeof(buf));
    buf[0] = a;
    buf[1] = b;
    buf[2] = c;
    raw_hid_send(buf, RAW_EPSIZE);
}

static void set_indicators(uint8_t mask) {
    work_louder_micro_led_1_set((mask & 1) ? 64 : 0);
    work_louder_micro_led_2_set((mask & 2) ? 64 : 0);
    work_louder_micro_led_3_set((mask & 4) ? 64 : 0);
}

static void enter_host_mode(void) {
    host_active = true;
    clear_keyboard();
    layer_clear();
    rgb_matrix_enable_noeeprom();
}

static void leave_host_mode(void) {
    host_active  = false;
    flash_phases = 0;
    flash_sticky = false;
    set_indicators(0);
#ifdef RGBLIGHT_ENABLE
    rgblight_reload_from_eeprom();
#endif
}

// ---------------------------------------------------------------------------
// Raw HID from the Mac

void raw_hid_receive(uint8_t *data, uint8_t length) {
    host_last_seen = timer_read32();

    if (data[0] == MP_CMD_RELEASE) {
        if (host_active) leave_host_mode();
        return;
    }
    if (!host_active) enter_host_mode();

    switch (data[0]) {
        case MP_CMD_PING:
            send_packet(MP_EVT_HELLO, MP_PROTOCOL_VERSION, 0);
            break;

        case MP_CMD_KEY_COLORS: {
            uint8_t start = data[1];
            uint8_t count = data[2];
            if (count > 9) count = 9;
            for (uint8_t i = 0; i < count; i++) {
                uint8_t k = start + i;
                if (k >= MATRIX_ROWS * MATRIX_COLS) break;
                key_rgb[k][0] = data[3 + i * 3];
                key_rgb[k][1] = data[4 + i * 3];
                key_rgb[k][2] = data[5 + i * 3];
            }
            break;
        }

        case MP_CMD_FILL:
            for (uint8_t k = 0; k < MATRIX_ROWS * MATRIX_COLS; k++) {
                key_rgb[k][0] = data[1];
                key_rgb[k][1] = data[2];
                key_rgb[k][2] = data[3];
            }
            break;

        case MP_CMD_FLASH:
            flash_rgb[0] = data[1];
            flash_rgb[1] = data[2];
            flash_rgb[2] = data[3];
            flash_sticky = (data[4] == 0);
            flash_phases = flash_sticky ? 254 : (uint8_t)(data[4] > 100 ? 200 : data[4] * 2);
            flash_period = data[5] ? (uint16_t)data[5] * 10 : 250;
            flash_timer  = timer_read32();
            break;

        case MP_CMD_BRIGHTNESS:
            brightness = data[1] > MP_MAX_BRIGHTNESS ? MP_MAX_BRIGHTNESS : data[1];
            break;

        case MP_CMD_INDICATORS:
            set_indicators(data[1]);
            break;

#ifdef RGBLIGHT_ENABLE
        case MP_CMD_UNDERGLOW:
            rgblight_mode_noeeprom(RGBLIGHT_MODE_STATIC_LIGHT);
            rgblight_setrgb(scale(data[1]), scale(data[2]), scale(data[3]));
            break;
#endif
    }
}

void housekeeping_task_user(void) {
    if (host_active && timer_elapsed32(host_last_seen) > MP_HOST_TIMEOUT_MS) {
        leave_host_mode();
    }
}

// ---------------------------------------------------------------------------
// Keys and encoders

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    if (!host_active) return true;

    uint8_t k = record->event.key.row * MATRIX_COLS + record->event.key.col;
    if (k >= MATRIX_ROWS * MATRIX_COLS) return false;

    if (record->event.pressed) {
        pressed_mask |= ((uint16_t)1 << k);
        if (flash_sticky) {
            flash_sticky = false;
            flash_phases = 0;
        }
    } else {
        pressed_mask &= ~((uint16_t)1 << k);
    }
    send_packet(MP_EVT_KEY, k, record->event.pressed ? 1 : 0);
    return false; // in host mode the Mac decides what to do
}

bool encoder_update_user(uint8_t index, bool clockwise) {
    if (host_active) {
        send_packet(MP_EVT_ENCODER, index, clockwise ? 1 : 0);
        return false;
    }
    return true; // standalone mode: volume (left) and scroll (right)
}

// ---------------------------------------------------------------------------
// Lights

bool rgb_matrix_indicators_user(void) {
    if (flash_phases > 0) {
        if (timer_elapsed32(flash_timer) >= flash_period) {
            flash_timer = timer_read32();
            flash_phases--;
            if (flash_phases == 0 && flash_sticky) flash_phases = 254;
        }
        if (flash_phases > 0 && (flash_phases % 2) == 0) {
            rgb_matrix_set_color_all(scale(flash_rgb[0]), scale(flash_rgb[1]), scale(flash_rgb[2]));
            return false;
        }
        if (flash_phases > 0) {
            rgb_matrix_set_color_all(0, 0, 0);
            return false;
        }
    }

    if (!host_active) return true;

    for (uint8_t row = 0; row < MATRIX_ROWS; row++) {
        for (uint8_t col = 0; col < MATRIX_COLS; col++) {
            uint8_t led = g_led_config.matrix_co[row][col];
            if (led == NO_LED) continue;
            uint8_t k = row * MATRIX_COLS + col;
            if (pressed_mask & ((uint16_t)1 << k)) {
                rgb_matrix_set_color(led, brightness, brightness, brightness);
            } else {
                rgb_matrix_set_color(led, scale(key_rgb[k][0]), scale(key_rgb[k][1]), scale(key_rgb[k][2]));
            }
        }
    }
    return false;
}

layer_state_t layer_state_set_user(layer_state_t state) {
    if (!host_active) set_indicators(layer_state_cmp(state, _FN) ? 1 : 0);
    return state;
}
