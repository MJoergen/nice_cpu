/***************************************************************
 * mchess
 *
 * This is a simple (minimalistic) chess engine, but functional
 * never the less. It is meant as a starting point for writing
 * your own chess engine. Use it for inspiration :-)
 *
 * This is a single-file C version of the original C++ sources
 * (CSquare, CMove, CMoveList, CBoard, ai and main).
 *
 * Build with e.g.:   gcc -W -Wall -O3 -o mchess mchess.c
 *
 * Features:
 * - A simple alpha-beta search strategy.
 * - Detects check-mate and stale-mate.
 * - A "perft N" command for testing the move generator.
 * - Searches a fixed depth of five ply (the root move plus four),
 *   followed by a capture-only quiescence search.
 * - A simple console (ASCII) user interface.
 *
 * Not implemented: castling, en passant, UCI, time control,
 * opening book.
 ***************************************************************/

#include <assert.h>
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/***************************************************************
 * Squares
 *
 * The board is represented as an array of 120 elements,
 * arranged in 12 rows and 10 columns.
 * The following diagram shows the numbering of the elements.
 * Note: The square A1 is element number 21
 *
 * 110 111 112 113 114 115 116 117 118 119
 * 100 101 102 103 104 105 106 107 108 109
 *  90  A8  92  93  94  95  96  97  H8  99
 *  80  81  82  83  84  85  86  87  88  89
 *  70  71  72  73  74  75  76  77  78  79
 *  60  61  62  63  64  65  66  67  68  69
 *  50  51  52  53  54  55  56  57  58  59
 *  40  41  42  43  44  45  46  47  48  49
 *  30  31  32  33  34  35  36  37  H2  39
 *  20  A1  22  23  24  25  26  27  H1  29
 *  10  11  12  13  14  15  16  17  18  19
 *   0   1   2   3   4   5   6   7   8   9
 ***************************************************************/

enum // Squares
{
    A1 = 21, H8 = 98
};

enum // Directions
{
    N = 10, S = -10, E = -1, W = 1,
    NW = 11, SW = -9, NE = 9, SE = -11,
    NNW = 21, NNE = 19, NWW = 12, NEE = 8,
    SSW = -19, SSE = -21, SWW = -8, SEE = -12
};

// Each element of the board contains one of the following values:
enum // Pieces
{
    EM = 0,   // Empty
    WP = 1,   // White Pawn
    WN = 2,   // White Knight
    WB = 3,   // White Bishop
    WR = 4,   // White Rook
    WQ = 5,   // White Queen
    WK = 6,   // White King
    BP = -1,  // Black Pawn
    BN = -2,  // Black Knight
    BB = -3,  // Black Bishop
    BR = -4,  // Black Rook
    BQ = -5,  // Black Queen
    BK = -6,  // Black King
    IV = 99   // INVALID
};

static const char pieces[] = "kqrbnp.PNBRQK";

// Scores are in centipawns. A mate must be worth far more than any
// possible material advantage.
#define MATE 30000
#define INF  32000

// Number of ply searched below the root move.
#define SEARCH_DEPTH 4

// Create nice colours in the console output
#define TTY_YELLOW "\033[33m"
#define TTY_BLUE   "\033[34m"
#define TTY_NORM   "\033[0m"

static int row_of(int sq) { return (sq/10) - 1; } // returns 1 - 8
static int col_of(int sq) { return (sq%10);     } // returns 1 - 8

/***************************************************************
 * Move
 ***************************************************************/

typedef struct
{
    uint8_t from;
    uint8_t to;
    int8_t  piece;
    int8_t  captured;   // IV means the move is not valid
    int8_t  promoted;
} Move;

static Move move_make(int piece, int from, int to, int captured, int promoted)
{
    Move m;
    m.from     = from;
    m.to       = to;
    m.piece    = piece;
    m.captured = captured;
    m.promoted = promoted;
    return m;
}

static int is_capture(const Move *m) { return m->captured != EM; }

// Parses a square, e.g. "e2". Returns true if error
static int square_from_string(const char *s, uint8_t *sq)
{
    uint32_t col = s[0] - 'a';
    uint32_t row = s[1] - '1';
    *sq = row*10 + col + 21;
    return (col >= 8 || row >= 8);
}

// Writes e.g. "e2e4" or "e7e8q" to buf (at least 6 bytes)
static void move_to_string(const Move *m, char *buf)
{
    assert (m->captured != IV);

    buf[0] = col_of(m->from) + 'a' - 1;
    buf[1] = row_of(m->from) + '0';
    buf[2] = col_of(m->to) + 'a' - 1;
    buf[3] = row_of(m->to) + '0';
    buf[4] = '\0';

    if (m->promoted != EM)
    {
        buf[4] = (char) tolower(pieces[m->promoted+6]);
        buf[5] = '\0';
    }
}

// Returns NULL if error
// The optional promotion suffix (q, r, b or n) is stored as a white piece
// type here. board_is_move_valid replaces the whole move with the matching
// generated move, which has the correct colour.
static const char * move_from_string(Move *m, const char *s)
{
    // Make sure we never read beyond the terminating zero
    for (int i=0; i<4; ++i)
        if (s[i] == '\0')
            return NULL;

    if (square_from_string(s, &m->from) || square_from_string(s+2, &m->to))
        return NULL;

    s += 4;

    m->piece = EM;
    m->captured = EM;
    m->promoted = EM;

    switch (tolower(s[0]))
    {
        case 'q' : m->promoted = WQ; s++; break;
        case 'r' : m->promoted = WR; s++; break;
        case 'b' : m->promoted = WB; s++; break;
        case 'n' : m->promoted = WN; s++; break;
        case ' ' : break;
        case '\0': break;
        default  : return NULL;
    }

    while (s[0] == ' ')
        s++;

    return s;
} /* end of move_from_string */

/***************************************************************
 * MoveList
 *
 * A fixed size array of moves. The maximum number of legal moves
 * in any chess position is 218, so this is plenty.
 ***************************************************************/

#define MAX_MOVES 512

typedef struct
{
    Move         moves[MAX_MOVES];
    unsigned int size;
} MoveList;

static void list_push_back(MoveList *list, Move move)
{
    assert (list->size < MAX_MOVES);
    list->moves[list->size++] = move;
}

static void list_clear(MoveList *list)
{
    list->size = 0;
}

static void list_print(const MoveList *list)
{
    for (unsigned int i=0; i<list->size; ++i)
    {
        char buf[8];
        move_to_string(&list->moves[i], buf);
        printf("%s ", buf);
    }
}

/***************************************************************
 * Board
 ***************************************************************/

typedef struct
{
    int8_t board[120];
    int    side_to_move; // 1 for white, -1 for black
    int    material;     // From the point of view of the side to move
} Board;

/***************************************************************
 * board_new_game
 * This resets the board configuration to the initial game setup
 ***************************************************************/
static void board_new_game(Board *b)
{
    static const int8_t initial[120] = {
        IV, IV, IV, IV, IV, IV, IV, IV, IV, IV,
        IV, IV, IV, IV, IV, IV, IV, IV, IV, IV,
        IV, WR, WN, WB, WQ, WK, WB, WN, WR, IV,
        IV, WP, WP, WP, WP, WP, WP, WP, WP, IV,
        IV, EM, EM, EM, EM, EM, EM, EM, EM, IV,
        IV, EM, EM, EM, EM, EM, EM, EM, EM, IV,
        IV, EM, EM, EM, EM, EM, EM, EM, EM, IV,
        IV, EM, EM, EM, EM, EM, EM, EM, EM, IV,
        IV, BP, BP, BP, BP, BP, BP, BP, BP, IV,
        IV, BR, BN, BB, BQ, BK, BB, BN, BR, IV,
        IV, IV, IV, IV, IV, IV, IV, IV, IV, IV,
        IV, IV, IV, IV, IV, IV, IV, IV, IV, IV};

    memcpy(b->board, initial, sizeof(initial));

    b->side_to_move = 1;
    b->material = 0;
} // end of board_new_game

/***************************************************************
 * board_print
 * This displays the current board configuration.
 ***************************************************************/
static int board_is_king_in_check(const Board *b);

static void board_print(const Board *b)
{
    for (int row=8; row>=1; --row)
    {
        printf(TTY_NORM "%d ", row);
        for (int col=1; col<=8; ++col)
        {
            int number = (row+1)*10+col;
            int piece = b->board[number];
            if (piece != IV)
            {
                if (piece < 0)
                    printf(TTY_BLUE);
                else if (piece > 0)
                    printf(TTY_YELLOW);
                else
                    printf(TTY_NORM);
                printf("%c ", pieces[piece+6]);
            }
        }
        printf("\n");
    }
    printf(TTY_NORM);
    printf("  a b c d e f g h\n");
    switch (b->side_to_move)
    {
        case  1 : printf("White to move\n"); break;
        case -1 : printf("Black to move\n"); break;
    }

    printf("\n");
    printf("Material : %d\n", b->material);
    if (board_is_king_in_check(b))
    {
        printf("You are in check!\n");
    }
} // end of board_print

/***************************************************************
 * board_is_square_threatened
 * Returns true if the side opposite to "side" threatens this square
 ***************************************************************/
static int board_is_square_threatened(const Board *b, int sq, int side)
{
    const int8_t *bd = b->board;
    const int e = -side; // Sign of the attacking pieces

    // Check for pawns
    if (bd[sq + 10*side + 1] == e*WP || bd[sq + 10*side - 1] == e*WP)
        return 1;

    // Check for knights
    {
        static const int dirs[8] = {NNW, NNE, NWW, NEE, SSW, SSE, SWW, SEE};

        for (int k=0; k<8; ++k)
            if (bd[sq + dirs[k]] == e*WN)
                return 1;
    }

    // Check for diagonal (bishop and queen)
    {
        static const int dirs[4] = {NW, NE, SW, SE};

        for (int k=0; k<4; ++k)
        {
            int sq2 = sq;
            while (1)
            {
                sq2 += dirs[k];
                if (bd[sq2] == e*WB || bd[sq2] == e*WQ)
                    return 1;
                if (bd[sq2] != EM)
                    break;
            }
        }
    }

    // Check for horizontal/vertical (rook and queen)
    {
        static const int dirs[4] = {N, S, W, E};

        for (int k=0; k<4; ++k)
        {
            int sq2 = sq;
            while (1)
            {
                sq2 += dirs[k];
                if (bd[sq2] == e*WR || bd[sq2] == e*WQ)
                    return 1;
                if (bd[sq2] != EM)
                    break;
            }
        }
    }

    // Check for king
    {
        static const int dirs[8] = {NW, NE, SW, SE, N, S, W, E};

        for (int k=0; k<8; ++k)
            if (bd[sq + dirs[k]] == e*WK)
                return 1;
    }

    return 0;
} // end of board_is_square_threatened

/***************************************************************
 * add_pawn_move
 * Adds a pawn move, expanding it to four moves if it promotes.
 ***************************************************************/
static void add_pawn_move(MoveList *moves, int s, int piece, int from, int to, int captured, int promotes)
{
    if (promotes)
    {
        list_push_back(moves, move_make(piece, from, to, captured, s*WQ));
        list_push_back(moves, move_make(piece, from, to, captured, s*WR));
        list_push_back(moves, move_make(piece, from, to, captured, s*WB));
        list_push_back(moves, move_make(piece, from, to, captured, s*WN));
    }
    else
        list_push_back(moves, move_make(piece, from, to, captured, EM));
}

/***************************************************************
 * board_find_pseudo_legal_moves
 * This generates a complete list of all pseudo-legal moves.
 * A pseudo-legal move does not consider, whether the king will
 * be in check. See board_find_legal_moves for that.
 ***************************************************************/
static void board_find_pseudo_legal_moves(const Board *b, MoveList *moves)
{
    static const int dirs_knight[8] = {NNW, NNE, NWW, NEE, SSW, SSE, SWW, SEE};
    static const int dirs_bishop[4] = {NE, NW, SE, SW};
    static const int dirs_rook[4]   = {N, E, S, W};
    static const int dirs_queen[8]  = {NE, NW, SE, SW, N, E, S, W};

    const int8_t *bd = b->board;
    const int s = b->side_to_move; // 1 for white, -1 for black

    list_clear(moves);

    for (int i=A1; i<=H8; ++i)
    {
        int8_t piece = bd[i];
        int j;
        const int *dirs = NULL;
        int ndirs = 0;
        int slide = 0;

        if (piece * s <= 0 || piece == IV) // Invalid, wrong color, or empty
            continue;

        switch (piece * s)
        {
            case WP : // Pawn
            {
                // Promotion happens from the seventh rank (from the mover's point of view)
                int promotes = (s > 0) ? (i > 80) : (i < 40);
                // Double step only from the second rank
                int on_start = (s > 0) ? (i < 40) : (i > 80);

                j = i + 10*s; // One square forward
                if (bd[j] == EM)
                {
                    add_pawn_move(moves, s, piece, i, j, EM, promotes);

                    j = i + 20*s; // Two squares forward
                    if (bd[j] == EM && on_start)
                        add_pawn_move(moves, s, piece, i, j, EM, 0);
                }

                j = i + 9*s; // Diagonal capture
                if (bd[j] != IV && bd[j]*s < 0)
                    add_pawn_move(moves, s, piece, i, j, bd[j], promotes);

                j = i + 11*s; // Diagonal capture
                if (bd[j] != IV && bd[j]*s < 0)
                    add_pawn_move(moves, s, piece, i, j, bd[j], promotes);

                continue;
            }

            case WN : dirs = dirs_knight; ndirs = 8; slide = 0; break; // Knight
            case WB : dirs = dirs_bishop; ndirs = 4; slide = 1; break; // Bishop
            case WR : dirs = dirs_rook;   ndirs = 4; slide = 1; break; // Rook
            case WQ : dirs = dirs_queen;  ndirs = 8; slide = 1; break; // Queen
            case WK : dirs = dirs_queen;  ndirs = 8; slide = 0; break; // King
            default : continue;
        }

        for (int k=0; k<ndirs; ++k)
        {
            j = i;
            while (1)
            {
                j += dirs[k];
                if (bd[j] == IV) break;
                if (bd[j]*s > 0) break; // Own piece
                list_push_back(moves, move_make(piece, i, j, bd[j], EM));
                if (bd[j] != EM) break; // Capture ends the ray
                if (!slide) break;
            }
        }
    }
} // end of board_find_pseudo_legal_moves

/***************************************************************
 * board_make_move
 * This updates the board according to the move
 ***************************************************************/
static void board_make_move(Board *b, const Move *move)
{
    switch (move->captured)
    {
        case WP : case BP : b->material += 1; break;
        case WN : case BN : b->material += 3; break;
        case WB : case BB : b->material += 3; break;
        case WR : case BR : b->material += 5; break;
        case WQ : case BQ : b->material += 9; break;
        default : break;
    }

    switch (move->promoted)
    {
        case WN : case BN : b->material += 3-1; break;
        case WB : case BB : b->material += 3-1; break;
        case WR : case BR : b->material += 5-1; break;
        case WQ : case BQ : b->material += 9-1; break;
        default : break;
    }

    b->board[move->to] = b->board[move->from];
    if (move->promoted != EM)
        b->board[move->to] = move->promoted;
    b->board[move->from] = EM;
    b->side_to_move = -b->side_to_move;
    b->material = -b->material;
} // end of board_make_move

/***************************************************************
 * board_undo_move
 * This reverses the effect of board_make_move
 ***************************************************************/
static void board_undo_move(Board *b, const Move *move)
{
    b->material = -b->material;
    switch (move->captured)
    {
        case WP : case BP : b->material -= 1; break;
        case WN : case BN : b->material -= 3; break;
        case WB : case BB : b->material -= 3; break;
        case WR : case BR : b->material -= 5; break;
        case WQ : case BQ : b->material -= 9; break;
        default : break;
    }

    switch (move->promoted)
    {
        case WN : case BN : b->material -= 3-1; break;
        case WB : case BB : b->material -= 3-1; break;
        case WR : case BR : b->material -= 5-1; break;
        case WQ : case BQ : b->material -= 9-1; break;
        default : break;
    }

    b->board[move->from] = move->piece;
    b->board[move->to] = move->captured;
    b->side_to_move = -b->side_to_move;
} // end of board_undo_move

/***************************************************************
 * Returns true if the king of the given side is in check.
 ***************************************************************/
static int board_is_king_in_check_for(const Board *b, int side)
{
    int king = (side == 1) ? WK : BK;
    int king_square = 0;

    // Look for the king
    for (int i=A1; i<=H8; ++i)
    {
        if (b->board[i] == king)
        {
            king_square = i;
            break;
        }
    }

    assert (king_square != 0); // The king MUST be somewhere

    return board_is_square_threatened(b, king_square, side);
} // end of board_is_king_in_check_for

/***************************************************************
 * Returns true if player to move is in check.
 ***************************************************************/
static int board_is_king_in_check(const Board *b)
{
    return board_is_king_in_check_for(b, b->side_to_move);
} // end of board_is_king_in_check

/***************************************************************
 * Returns true if player NOT to move is in check.
 ***************************************************************/
static int board_is_other_king_in_check(const Board *b)
{
    return board_is_king_in_check_for(b, -b->side_to_move);
} // end of board_is_other_king_in_check

/***************************************************************
 * board_find_legal_moves
 * This generates the list of all legal moves, i.e. the
 * pseudo-legal moves that do not leave our own king in check.
 ***************************************************************/
static void board_find_legal_moves(Board *b, MoveList *moves)
{
    MoveList pseudo;
    board_find_pseudo_legal_moves(b, &pseudo);

    list_clear(moves);
    for (unsigned int i=0; i<pseudo.size; ++i)
    {
        board_make_move(b, &pseudo.moves[i]);
        int illegal = board_is_other_king_in_check(b);
        board_undo_move(b, &pseudo.moves[i]);
        if (!illegal)
            list_push_back(moves, pseudo.moves[i]);
    }
} // end of board_find_legal_moves

/***************************************************************
 * board_is_move_valid
 * This returns true, if the move is legal. In that case the move
 * is replaced by the corresponding generated move, so it is fully
 * filled in (piece, captured piece, promotion).
 * If no promotion piece is given, a queen is assumed.
 ***************************************************************/
static int board_is_move_valid(Board *b, Move *move)
{
    MoveList moves;
    board_find_legal_moves(b, &moves);
    for (unsigned int i=0; i<moves.size; ++i)
    {
        const Move *m = &moves.moves[i];
        if (m->from != move->from || m->to != move->to)
            continue;

        int wanted = move->promoted;
        if (wanted == EM && m->promoted != EM)
            wanted = WQ;

        if (abs(m->promoted) == wanted)
        {
            *move = *m;
            return 1;
        }
    }
    return 0;
} // end of board_is_move_valid

/***************************************************************
 * board_get_value
 *
 * It returns an integer value showing how good the position
 * is for the side to move.
 *
 * This is a very simple evaluation function. Only two factors are
 * considered:
 * 1. The material balance:
 *      * Pawn   100
 *      * Knight 300
 *      * Bishop 300
 *      * Rook   500
 *      * Queen  900
 * 2. The difference in number of legal moves of both players.
 *
 * The latter tends to favor positions, where the computer
 * has many legal moves. This implies centralization and development.
 ***************************************************************/
static int board_get_value(Board *b)
{
    MoveList moves;
    board_find_pseudo_legal_moves(b, &moves);
    int my_moves = moves.size;

    b->side_to_move = -b->side_to_move;
    board_find_pseudo_legal_moves(b, &moves);
    int his_moves = moves.size;
    b->side_to_move = -b->side_to_move;

    return (my_moves-his_moves) + 100*b->material;
} // end of board_get_value

/***************************************************************
 * AI: quiescence
 *
 * Search only captures, until the position is quiet. This avoids
 * evaluating positions in the middle of a capture sequence
 * (the "horizon effect").
 * The side to move may always decline to capture ("stand pat").
 ***************************************************************/
static int ai_quiescence(Board *board, int alpha, int beta)
{
    int stand_pat = board_get_value(board);
    if (stand_pat >= beta)
        return stand_pat;
    if (stand_pat > alpha)
        alpha = stand_pat;

    MoveList moves;
    board_find_pseudo_legal_moves(board, &moves);

    int best_val = stand_pat;

    for (unsigned int i=0; i<moves.size; ++i)
    {
        const Move *move = &moves.moves[i];
        if (!is_capture(move))
            continue;

        board_make_move(board, move);
        if (board_is_other_king_in_check(board))
        {
            // Illegal move
            board_undo_move(board, move);
            continue;
        }
        int num = -ai_quiescence(board, -beta, -alpha);
        board_undo_move(board, move);

        if (num > best_val)
            best_val = num;
        if (best_val > alpha)
            alpha = best_val;
        if (alpha >= beta)
            break;
    }

    return best_val;
} // end of ai_quiescence

/***************************************************************
 * AI: search
 *
 * This is a very basic (Fail-Soft Negamax) alpha-beta search.
 * For details, see e.g.
 * http://chessprogramming.wikispaces.com/Alpha-Beta
 * and
 * http://en.wikipedia.org/wiki/Alpha-beta_pruning
 *
 * Parameter values are:
 * * alpha, beta. The search window
 * * level. The number of ply (half-moves) to search.
 *
 * The value returned by this function is
 * * positive, if the side to move has an advantage (is winning).
 * * negative, if the side to move is losing.
 * * zero, if the position is equal.
 * * -(MATE+level), if the side to move is check-mated. A mate that
 *   is found sooner has a larger absolute value.
 * * zero, if the side to move is stale-mated.
 ***************************************************************/
static int ai_search(Board *board, int alpha, int beta, int level)
{
    if (level == 0)
        return ai_quiescence(board, alpha, beta); // We are at leaf, resolve captures and evaluate.

    MoveList moves;
    board_find_pseudo_legal_moves(board, &moves);

    int best_val = -INF; // Assume the worst
    int any_legal = 0;

    // Search through all pseudo-legal moves
    for (unsigned int i=0; i<moves.size; ++i)
    {
        const Move *move = &moves.moves[i];

        board_make_move(board, move);
        if (board_is_other_king_in_check(board))
        {
            // The move left our own king in check, so it is illegal.
            board_undo_move(board, move);
            continue;
        }
        any_legal = 1;

        // Do a recursive search
        int num = -ai_search(board, -beta, -alpha, level-1);
        board_undo_move(board, move);

        if (num > best_val)
        {
            // Store the best value so far.
            best_val = num;
        }
        if (best_val > alpha)
        {
            // Tighten the search window.
            alpha = best_val;
        }
        if (alpha >= beta)
        {
            // This is the alpha-beta pruning.
            // Stop searching, if we already have found a "killer" move.
            break;
        }
    }

    if (!any_legal)
    {
        if (board_is_king_in_check(board))
            return -(MATE + level); // Check-mate
        return 0;                   // Stale-mate
    }

    return best_val;
} // end of ai_search

/***************************************************************
 * ai_find_best_move
 *
 * This is the main AI.
 * It returns what it considers to be the best legal move in the
 * current position.
 ***************************************************************/
static Move ai_find_best_move(Board *board)
{
    // Make a list of all legal moves
    MoveList moves;
    board_find_legal_moves(board, &moves);

    if (moves.size == 0)
    {
        printf("BUG: No legal moves!\n");
        exit(1);
    }

    printf("info string %u legal moves.\n", moves.size);

    MoveList best_moves; // Array of the (one or more) best moves so far
    list_clear(&best_moves);
    int best_val = -INF;

    // Search through all legal moves
    for (unsigned int i=0; i<moves.size; ++i)
    {
        Move move = moves.moves[i];

        // Get value of current move
        board_make_move(board, &move);
        int val = -ai_search(board, -INF, INF, SEARCH_DEPTH);
        board_undo_move(board, &move);

        char buf[8];
        move_to_string(&move, buf);
        printf("info string %d : %s\n", val, buf);

        if (val > best_val)
        {
            best_val = val;
            list_clear(&best_moves);
            list_push_back(&best_moves, move);
        }
        else if (val == best_val)
        {
            list_push_back(&best_moves, move);
        }
    }

    return best_moves.moves[rand() % best_moves.size];
} // end of ai_find_best_move

/***************************************************************
 * perft
 *
 * Counts the leaf nodes of the legal move tree to the given depth.
 * Useful for testing the move generator. Known values from the
 * start position: 20, 400, 8902, 197281.
 * (Castling and en passant are not implemented, so the numbers
 * diverge from the official ones from depth 5.)
 ***************************************************************/
static unsigned long perft(Board *board, int depth)
{
    if (depth == 0)
        return 1;

    MoveList moves;
    board_find_legal_moves(board, &moves);

    unsigned long count = 0;
    for (unsigned int i=0; i<moves.size; ++i)
    {
        board_make_move(board, &moves.moves[i]);
        count += perft(board, depth-1);
        board_undo_move(board, &moves.moves[i]);
    }
    return count;
} // end of perft

/***************************************************************
 * main
 *
 * This is where it all starts!
 ***************************************************************/
int main(void)
{
    srand(time(0)); // Seed the random number generator.

    Board board;
    board_new_game(&board);

    while (1) // Repeat forever
    {
        // Display board
        board_print(&board);

        // Check for end of game
        {
            MoveList legal;
            board_find_legal_moves(&board, &legal);
            if (legal.size == 0)
            {
                if (board_is_king_in_check(&board))
                    printf("Check-mate!\n");
                else
                    printf("Stale-mate!\n");
                return 0;
            }
        }
        printf("Input command : ");
        fflush(stdout);

        // Read input from player
        char str[256];
        if (fgets(str, sizeof(str), stdin) == NULL)
            exit(0); // End of file
        str[strcspn(str, "\r\n")] = '\0';
        printf("\n");

        // Parse input from player
        if (strcmp(str, "quit") == 0)
        {
            exit(0);
        }

        if (strncmp(str, "move ", 5) == 0)
        {
            Move move;

            if (move_from_string(&move, str+5) == NULL)
            {
                // Could not parse move.
                printf("Try again. Use long notation, e.g. e2e4\n");
                continue; // Go back to beginning
            }

            char buf[8];
            if (board_is_move_valid(&board, &move))
            {
                move_to_string(&move, buf);
                printf("You move : %s\n", buf);
                board_make_move(&board, &move);
            }
            else
            {
                // The move is not filled in, so print it manually
                move.captured = EM;
                move_to_string(&move, buf);
                printf("Move %s is not legal.\n", buf);
                continue;
            }
        } // end of "move "

        else if (strcmp(str, "go") == 0)
        {
            Move best_move = ai_find_best_move(&board);

            char buf[8];
            move_to_string(&best_move, buf);
            printf("bestmove %s\n", buf);

            board_make_move(&board, &best_move);
        } // end of "go"

        else if (strncmp(str, "perft ", 6) == 0)
        {
            int depth = atoi(str+6);
            printf("perft(%d) = %lu\n", depth, perft(&board, depth));
        }

        else if (strcmp(str, "show") == 0)
        {
            MoveList moves;
            board_find_legal_moves(&board, &moves);

            list_print(&moves);
            printf("\n");
        }

        else
        {
            printf("Unknown command\n");
            printf("Valid commands are: quit, move, go, show, perft\n");
        }
    } // end of while (1)

    return 0;
} // end of int main()
