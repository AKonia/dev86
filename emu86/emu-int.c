
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>

#include "emu-proc.h"
#include "emu-serial.h"
#include "emu-int.h"


// BIOS video services
// WARNING: specific to ADVTECH SBC - not standard IBM BIOS

static byte_t num_hex (byte_t n)
	{
	byte_t h = n + '0';
	if (h > '9') h += 'A' - '9';
	return h;
	}

void int_10h ()
	{
	byte_t ah = reg8_get (REG_AH);

	byte_t al;

	word_t es;
	word_t bp;
	word_t cx;

	addr_t a;
	byte_t c;

	switch (ah)
		{
		// Write character at current cursor position

		case 0x0A:
			serial_send (reg8_get (REG_AL));
			break;

		// Write string

		case 0x13:
			es = seg_get (SEG_ES);
			bp = reg16_get (REG_BP);
			cx = reg16_get (REG_CX);
			a = addr_seg_off (es, bp);

			while (cx--)
				{
				serial_send (mem_read_byte (a++));
				}

			break;

		// Write byte as hexadecimal

		case 0x1D:
			al = reg8_get (REG_AL);
			c = num_hex (al >> 4);
			serial_send (c);
			c = num_hex (al & 0x0F);
			serial_send (c);
			break;

		default:
			assert (0);
		}
	}


// BIOS keyboard services
// WARNING: specific to ADVTECH SBC - not standard IBM BIOS

void int_16h ()
	{
	byte_t c = 0;

	byte_t ah = reg8_get (REG_AH);
	switch (ah)
		{
		// Normal keyboard read
		// ADVTECH: keyboard init

		case 0x00:
			break;

		// Extended keyboard read
		// ADVTECH: read next char (blocking)

		case 0x10:
			c = serial_recv ();
			reg8_set (REG_AL, (byte_t) c);  // ASCII code
			reg8_set (REG_AH, 0);           // No scan code
			break;

		default:
			assert (0);
		}
	}


// BIOS printer services
// WARNING: specific to ADVTECH SBC - not standard IBM BIOS

void int_17h ()
	{
	byte_t ah = reg8_get (REG_AH);
	switch (ah)
		{
		// ADVTECH: serial reset

		case 0x06:
			break;

		default:
			assert (0);
		}
	}


// BIOS time services
// WARNING: specific to ADVTECH SBC - not standard IBM BIOS

void int_1Ah ()
	{
	byte_t ah = reg8_get (REG_AH);
	switch (ah)
		{
		// Get system time

		case 0x00:
			reg16_set (REG_CX, 0);  // stay on 0
			reg16_set (REG_DX, 0);
			reg8_set (REG_AL, 0);   // no day wrap
			break;

		default:
			assert (0);
		}
	}


// BIOS ethernet services
// WARNING: specific to ADVTECH SBC - not standard IBM BIOS

void int_60h ()
	{
	byte_t ah = reg8_get (REG_AH);
	switch (ah)
		{
		// ADVTECH: ethernet reset

		case 0x00:
			break;

		default:
			assert (0);
		}
	}


// BIOS configuration services
// WARNING: specific to ADVTECH SBC - not standard IBM BIOS

void int_D0h ()
	{
	byte_t ah = reg8_get (REG_AH);
	switch (ah)
		{
		// ADVTECH: NIC IO base

		case 0x00:
			reg16_set (REG_AX, 0x300);
			break;

		// ADVTECH: program select (DIP SW) ?

		case 0x01:
			reg16_set (REG_AX, 3);  // program 01 -> MON86  11 -> TEST
			break;

		// ADVTECH: RTC present ?

		case 0x02:
			reg16_set (REG_AX, 0);  // no RTC for EMU86
			break;

		// ADVTECH: CPU frequency

		case 0x03:
			reg16_set (REG_AX, 16960);  // 1 MHz :-)
			reg16_set (REG_DX, 15);
			break;

		case 0x06:
			reg16_set (REG_AX, 1);  // password reset jumper ON
			break;

		default:
			assert (0);
		}
	}


// BIOS misc services
// WARNING: specific to ADVTECH SBC - not standard IBM BIOS

void int_D2h ()
	{
	byte_t ah = reg8_get (REG_AH);
	switch (ah)
		{
		case 0x00:  // LED
			break;

		case 0x02:  // set D2h_flag
			break;

		default:
			assert (0);

		}
	}


// Interrupt handle table

typedef void (* int_hand_t) ();

struct int_num_hand_s
	{
	byte_t num;
	int_hand_t hand;
	};

typedef struct int_num_hand_s int_num_hand_t;

int_num_hand_t _int_tab [] = {
		{ 0x10, int_10h },
		{ 0x16, int_16h },
		{ 0x17, int_17h },
		{ 0x1A, int_1Ah },
		{ 0x60, int_60h },
		{ 0xD0, int_D0h },
		{ 0xD2, int_D2h },
		{ 0,    NULL    }
	};


int int_hand (byte_t i)
	{
	int err = -1;

	int_num_hand_t * desc = _int_tab;

	while (1)
		{
		byte_t num = desc->num;
		int_hand_t hand = desc->hand;

		if (!num && !hand) break;

		if (num == i)
			{
			(*hand) ();
			err = 0;
			break;
			}

		desc++;
		}

	return err;
	}
