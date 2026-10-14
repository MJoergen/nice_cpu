# References

These are the documents considered while defining the NICE ISA in [ISA.md](ISA.md).

## NICE: primary sources (B. Ulmann)

| Year | Document | Links | Notes |
|---|---|---|---|
| 1997 | B. Ulmann, *NICE – an elegant and powerful 32-bit architecture*, ACM SIGARCH Computer Architecture News 25(4), pp. 30–35, September 1997. | [Author's copy (PDF)](http://www.vaxman.de/publications/nice_can.pdf) · [ResearchGate](https://www.researchgate.net/publication/234813020_NICE_an_elegant_and_powerful_32-bit_architecture) · [Bibliography entry](https://ftp.math.utah.edu/pub/tex/bib/idx/sigarch/25/4/30_35.html) | The original description. The author's PDF has the same text as the journal scan. |
| 1999 | B. Ulmann, *Designing a NICE processor*, Microprocessors and Microsystems 23, pp. 257–264, 1999. | [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0141933199000216) · [DOI](https://doi.org/10.1016/S0141-9331(99)00021-6) | A tutorial and restatement. It fixes `iand`, says R15 reads as the next instruction, and adds a 74181 background for the ALU. |
| 2004 | *The NICE Processor Pages* (web page, dated 13-OCT-2004). | [vaxman.de](http://www.vaxman.de/projects/nice/nice.html) · [Wayback Machine](https://web.archive.org/web/2023/http://www.vaxman.de/projects/nice/nice.html) | Uses a different condition-field and status-register layout from the articles. That layout is the one adopted. |
| 2004 | B. Ulmann and T. Kratz, `NICE.pm` v0.4 and `nice_ide.pl`: Perl emulator, assembler, and IDE. | [nice_source.zip](http://www.vaxman.de/projects/nice/nice_source.zip) · [NICE.pm documentation](http://www.vaxman.de/projects/nice/nice_pm.html) · [Windows build](http://www.vaxman.de/projects/nice/nice_ide.exe) · [Linux build](http://www.vaxman.de/projects/nice/nice_ide) | The emulator's intended behaviour is the main reference for the ISA. Its bugs are not; see [review/emulator-and-webpage-review.md](review/emulator-and-webpage-review.md) §4. |
| 2004 | Example programs `count`, `replicate`, and `print` (`.asm` and `.bin`). | [examples.zip](http://www.vaxman.de/projects/nice/examples.zip) | Real assembler output. These are the first test vectors. |

Author indexes: [Ulmann's publication list](http://www.vaxman.de/publications/publications.html) · [dblp](https://dblp.org/pid/21/6402.html).

No independent NICE implementations were found.

## QNICE: the reference for gaps the NICE sources leave open

| Document | Links | Notes |
|---|---|---|
| QNICE ("Quite NICE"), the 16-bit descendant of NICE. | [vaxman.de](http://www.vaxman.de/projects/qnice/qnice.html) · [qnice.sourceforge.net](https://qnice.sourceforge.net/) | |
| QNICE-FPGA, at the commit pinned by qnice_cpu. | [sy2002/QNICE-FPGA @ b1fb36c](https://github.com/sy2002/QNICE-FPGA/tree/b1fb36c) | Files used: [`doc/intro/qnice_intro.tex`](https://github.com/sy2002/QNICE-FPGA/blob/b1fb36c/doc/intro/qnice_intro.tex) (ISA slides), [`emulator/qnice.c`](https://github.com/sy2002/QNICE-FPGA/blob/b1fb36c/emulator/qnice.c) (reference emulator), [`vhdl/alu.vhd`](https://github.com/sy2002/QNICE-FPGA/blob/b1fb36c/vhdl/alu.vhd). |
| qnice_cpu, Michael Jørgensen's QNICE implementation. | [MJoergen/qnice_cpu](https://github.com/MJoergen/qnice_cpu) | Files used: `src/cpu_main/sub/alu_data.vhd`, `alu_flags.vhd`, `write.vhd`, `doc/README.md`, `doc/interrupts.md`, and `test/prog_r15.asm`. |

## Background

- [The 6502 overflow flag explained](http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html) (Ken Shirriff). Used for the textbook definition of the V flag.

## Review notes in this repository

These record how each ISA decision was reached. [ISA.md](ISA.md) supersedes them where they differ.

- [review/nice-article-review.md](review/nice-article-review.md): the 60 contradictions, example bugs, and gaps found in the 1997 article.
- [review/gap-resolution.md](review/gap-resolution.md): each of the 60 items, checked against QNICE and the later sources.
- [review/second-article-review.md](review/second-article-review.md): what the 1999 article resolves and contradicts.
- [review/emulator-and-webpage-review.md](review/emulator-and-webpage-review.md): what the 2004 web page and emulator resolve and contradict, and the emulator's bugs.
