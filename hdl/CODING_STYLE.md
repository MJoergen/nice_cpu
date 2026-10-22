# VHDL coding style

The VHDL in `hdl/` follows the style of
[qnice_cpu](https://github.com/MJoergen/qnice_cpu/blob/main/CODING_STYLE.md),
in short form. `make lint` checks what it can with
[vsg](https://vhdl-style-guide.readthedocs.io/) and [vsg.yml](vsg.yml).

All code is VHDL-2008, analyzed with plain `ghdl --std=08` (no `-frelaxed`).

## Files

- One design unit per file, named after it.
- The file starts with a header comment, then `library ieee;`. The `use`
  clauses are indented 3 spaces, with a blank line between libraries.
- A longer header uses these headings, in this order: a summary, `THEORY OF
  OPERATION`, `INTERFACE CONTRACTS -- these are requirements on the
  environment:` with items `a)`, `b)`, and `c)`, and `RESET`.
- The architecture is `synthesis`, or `simulation` for a unit that only
  simulates (`sim/`, `test/`).
- Closing keywords are written in full: `end entity perf;`,
  `end architecture synthesis;`, and `end process p_bus;`.

## Names

| Kind | Convention | Example |
|---|---|---|
| Entity, signal, variable | `lower_snake_case` | `wb_mem`, `take_nmi` |
| Port | ends in `_i` or `_o` | `wb_stall_o` |
| Generic | `G_UPPER_SNAKE` | `G_STALL` |
| Constant | `C_UPPER_SNAKE` | `C_REGS_RESET` |
| Enumeration literal | `UPPER_SNAKE` | `HALT_NONE` |
| State of a state machine | `UPPER_SNAKE` + `_ST` | `FETCH_ST` |
| Type | `t_` prefix | `t_retire` |
| Process, instance, generate | `p_`, `i_`, `gen_` prefix | `p_fsm`, `i_mpu` |

- `clk_i` and `rst_i` come first in a port list.
- Optional suffixes: `_r` for a register and `_v` for a variable.
- An instance of one entity is labeled `i_<entity>`.

## Layout

- Indent 3 spaces. No tabs and no trailing spaces.
- Keep lines under 100 columns where it reads well. vsg only warns.
- Within a group of declarations, separated by blank lines or comments,
  align the colons. Port clauses and port maps align as a whole. Write the
  modes `in ` and `out`.
- Align trailing comments on a run of lines into one column.
- Put spaces around operators: `C_LEN * 4 - 1`, `addr + 1`.
- Write bit-string literals in upper case: `X"1FFF"`.
- In an architecture body, two blank lines separate each process and
  instance from its neighbors, but one follows `begin`. Elsewhere, one
  blank line separates ideas, where the author sees fit.
- A case alternative with one short statement may sit on the line of its
  `when`, so that the case reads as a table. Align the `=>` of such a table.
- An instance ends with its label: `); -- i_mpu`.

## Idioms

- Instantiate entities directly: `i_mpu : entity work.mpu`. No components.
- Write `process (clk_i)` without `is`, and `if x = '1' then` without
  parentheses. Compare `std_logic` explicitly; do not write `if x then`.
- Reset is synchronous and active high. It is the last `if` inside
  `if rising_edge(clk_i) then`, so it overrides the rest.
- Use `numeric_std_unsigned` for arithmetic on `std_logic_vector`. Import
  `numeric_std` only where `signed` or `unsigned` is needed.
- Subprogram headers are compact: `function f(a : t;` with the other
  parameters aligned under `a`.
- `report` and `severity` go on lines of their own, indented under the
  `assert` or `report`. A message starts with the unit's name, as in
  `"tb_mpu: ..."`.
- No shared variables.

## Comments

- Full sentences. Comment why, not what.
- Use ` -- ` as a dash in prose.
- Open items go in [TODO.md](../TODO.md), not in comments.

## Exceptions

A construct that breaks a vsg rule on purpose, such as a table, is wrapped
in markers at column 0, after a comment that says why:

```vhdl
            -- A table of the writable words, one line each.
-- vsg_off sequential_007
            ...
-- vsg_on sequential_007
```

Change [vsg.yml](vsg.yml) only for a rule that holds for the whole
repository, and state that rule here first.
