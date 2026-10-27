" Vim syntax file
" Language:    NICE assembly (.nasm), see doc/ISA.md section 10
" Install:     copy to ~/.vim/syntax/nice.vim, and add to ~/.vimrc:
"                autocmd BufRead,BufNewFile *.nasm set filetype=nice
"              (Vim's own filetype detection takes *.nasm for Netwide Assembler.)

if exists("b:current_syntax")
  finish
endif

" Mnemonics, registers, conditions, modifiers, and directives ignore case.
syn case ignore

" Labels and .EQU names: the first word in column 0.
syn match niceLabel     "^[A-Za-z_][A-Za-z0-9_.]*:\="

" Instructions
syn keyword niceAlu     MOVE SUB MDBL ADD DBL DEC NOT NOR IAND NAND XOR IOR XNOR AND ONE OR
syn keyword niceShift   SHL SHR ROL ROR BPL BPR
syn keyword niceControl HALT RTI INT

" Modifiers: [M], [C], [CM], [MC]
syn match niceModifier  "\[[CM]\+\]"

" Conditions: ?Z, ?!C, ?1, and so on
syn match niceCond      "?!\=[1XCZNVEIM]\>"

" Directives
syn match niceDirective "\.\(EQU\|ORG\|DAT\|BLK\|RES\|ASCII_L\|ASCII_B\)\>"

" Operands
syn match niceRegister  "\<R[0-9]\+\>"
syn match niceNumber    "\<\(0x\x\+\|0b[01]\+\|[0-9]\+\)\>"
" Symbolic shifts come after the numbers, so 0>C is not a number.
syn match   niceShift   "\(\s\)\@<=\(0<[01C]\|C<[01C0]\|<<<\|C<<\|[01C]>[0C]\|0>C\|>>>\|>>C\)\(\s\|$\)\@="
" An indirect operand as a whole: @R3, @--R3, @R3++, @0x12, @c[R1].
syn match niceIndirect  "@\(--\)\=[A-Za-z0-9_.+-]*\(\[[^]]*\]\)\=\(++\|--\)\="
syn region niceString   start=+'+ end=+'+ oneline
syn region niceString   start=+"+ end=+"+ oneline

" Comments: ; anywhere, or * at the start of a word. Last, so they win.
syn match niceComment   ";.*$"
syn match niceComment   "\(^\|\s\)\@<=\*.*$"

hi def link niceLabel     Label
hi def link niceAlu       Statement
hi def link niceShift     Statement
hi def link niceControl   Statement
hi def link niceModifier  Special
hi def link niceCond      PreProc
hi def link niceDirective Macro
hi def link niceRegister  Identifier
hi def link niceNumber    Number
hi def link niceIndirect  Type
hi def link niceString    String
hi def link niceComment   Comment

let b:current_syntax = "nice"
