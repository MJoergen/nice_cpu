// Access to NICE memory and I/O devices from wasm code (ISA.md §9.4).
#ifndef _NICE_H
#define _NICE_H

// The console (ISA.md §8.3). Each write prints bits 7..0 of the word. A
// read returns the next input byte with NICE_CONSOLE_BYTE set, 0 if no
// byte is there yet, or NICE_CONSOLE_END once the emulator's input ended.
#define NICE_CONSOLE 0xFFFFFF00u
#define NICE_CONSOLE_BYTE 0x100u
#define NICE_CONSOLE_END 0x200u

// Reads the NICE word at a word address.
__attribute__((import_module("nice"), import_name("peek")))
unsigned nice_peek(unsigned addr);

// Writes val to the NICE word at a word address.
__attribute__((import_module("nice"), import_name("poke")))
void nice_poke(unsigned addr, unsigned val);

#endif
