/* ANSI-C code produced by gperf version 3.1 */
/* Command-line: gperf --compare-lengths -t --hash-function-name=gperf_hash gperf_words.txt  */
/* Computed positions: -k'1-3' */

#if !((' ' == 32) && ('!' == 33) && ('"' == 34) && ('#' == 35) \
      && ('%' == 37) && ('&' == 38) && ('\'' == 39) && ('(' == 40) \
      && (')' == 41) && ('*' == 42) && ('+' == 43) && (',' == 44) \
      && ('-' == 45) && ('.' == 46) && ('/' == 47) && ('0' == 48) \
      && ('1' == 49) && ('2' == 50) && ('3' == 51) && ('4' == 52) \
      && ('5' == 53) && ('6' == 54) && ('7' == 55) && ('8' == 56) \
      && ('9' == 57) && (':' == 58) && (';' == 59) && ('<' == 60) \
      && ('=' == 61) && ('>' == 62) && ('?' == 63) && ('A' == 65) \
      && ('B' == 66) && ('C' == 67) && ('D' == 68) && ('E' == 69) \
      && ('F' == 70) && ('G' == 71) && ('H' == 72) && ('I' == 73) \
      && ('J' == 74) && ('K' == 75) && ('L' == 76) && ('M' == 77) \
      && ('N' == 78) && ('O' == 79) && ('P' == 80) && ('Q' == 81) \
      && ('R' == 82) && ('S' == 83) && ('T' == 84) && ('U' == 85) \
      && ('V' == 86) && ('W' == 87) && ('X' == 88) && ('Y' == 89) \
      && ('Z' == 90) && ('[' == 91) && ('\\' == 92) && (']' == 93) \
      && ('^' == 94) && ('_' == 95) && ('a' == 97) && ('b' == 98) \
      && ('c' == 99) && ('d' == 100) && ('e' == 101) && ('f' == 102) \
      && ('g' == 103) && ('h' == 104) && ('i' == 105) && ('j' == 106) \
      && ('k' == 107) && ('l' == 108) && ('m' == 109) && ('n' == 110) \
      && ('o' == 111) && ('p' == 112) && ('q' == 113) && ('r' == 114) \
      && ('s' == 115) && ('t' == 116) && ('u' == 117) && ('v' == 118) \
      && ('w' == 119) && ('x' == 120) && ('y' == 121) && ('z' == 122) \
      && ('{' == 123) && ('|' == 124) && ('}' == 125) && ('~' == 126))
/* The character set is not based on ISO-646.  */
#error "gperf generated tables don't work with this execution character set. Please report a bug to <bug-gperf@gnu.org>."
#endif

#line 1 "gperf_words.txt"
struct GPerfResult
  {
  const char* name;
  int code;
  };

#define TOTAL_KEYWORDS 47
#define MIN_WORD_LENGTH 2
#define MAX_WORD_LENGTH 10
#define MIN_HASH_VALUE 7
#define MAX_HASH_VALUE 85
/* maximum key range = 79, duplicates = 0 */

#ifdef __GNUC__
__inline
#else
#ifdef __cplusplus
inline
#endif
#endif
static unsigned int
gperf_hash (register const char *str, register size_t len)
{
  static unsigned char asso_values[] =
    {
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86,  5, 86, 10, 50, 35,
       5, 25, 25, 35, 40,  5, 86, 86,  5, 25,
       0, 15, 10, 86,  5,  5,  0,  0,  5, 86,
      86, 50, 40, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86, 86, 86, 86, 86,
      86, 86, 86, 86, 86, 86
    };
  register unsigned int hval = len;

  switch (hval)
    {
      default:
        hval += asso_values[(unsigned char)str[2]];
      /*FALLTHROUGH*/
      case 2:
        hval += asso_values[(unsigned char)str[1]];
      /*FALLTHROUGH*/
      case 1:
        hval += asso_values[(unsigned char)str[0]];
        break;
    }
  return hval;
}

struct GPerfResult *
in_word_set (register const char *str, register size_t len)
{
  static unsigned char lengthtable[] =
    {
       0,  0,  0,  0,  0,  0,  0,  2,  0,  4,  5,  6,  2,  3,
       9, 10,  6,  2,  0,  4,  0,  6,  2,  8,  9,  0,  6,  2,
       3,  4,  5,  6,  2,  8,  4, 10,  6,  0,  0,  4,  5,  6,
       0,  3,  0,  5,  6,  0,  3,  0,  0,  6,  2,  8,  4,  5,
       6,  0,  8,  4,  5,  6,  0,  3,  4,  0,  6,  0,  0,  0,
       0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
       0,  5
    };
  static struct GPerfResult wordlist[] =
    {
      {""}, {""}, {""}, {""}, {""}, {""}, {""},
#line 25 "gperf_words.txt"
      {"in", 85},
      {""},
#line 44 "gperf_words.txt"
      {"true", 104},
#line 49 "gperf_words.txt"
      {"union", 109},
#line 53 "gperf_words.txt"
      {"unsafe", 113},
#line 27 "gperf_words.txt"
      {"is", 87},
#line 31 "gperf_words.txt"
      {"nil", 91},
#line 26 "gperf_words.txt"
      {"interface", 86},
#line 41 "gperf_words.txt"
      {"_unlikely_", 101},
#line 43 "gperf_words.txt"
      {"struct", 103},
#line 7 "gperf_words.txt"
      {"as", 67},
      {""},
#line 35 "gperf_words.txt"
      {"none", 95},
      {""},
#line 51 "gperf_words.txt"
      {"static", 111},
#line 48 "gperf_words.txt"
      {"or", 108},
#line 40 "gperf_words.txt"
      {"_likely_", 100},
#line 39 "gperf_words.txt"
      {"isreftype", 99},
      {""},
#line 9 "gperf_words.txt"
      {"assert", 69},
#line 19 "gperf_words.txt"
      {"fn", 79},
#line 30 "gperf_words.txt"
      {"mut", 90},
#line 16 "gperf_words.txt"
      {"enum", 76},
#line 34 "gperf_words.txt"
      {"rlock", 94},
#line 10 "gperf_words.txt"
      {"atomic", 70},
#line 23 "gperf_words.txt"
      {"if", 83},
#line 52 "gperf_words.txt"
      {"volatile", 112},
#line 47 "gperf_words.txt"
      {"dump", 107},
#line 42 "gperf_words.txt"
      {"__offsetof", 102},
#line 36 "gperf_words.txt"
      {"return", 96},
      {""}, {""},
#line 15 "gperf_words.txt"
      {"else", 75},
#line 28 "gperf_words.txt"
      {"match", 88},
#line 37 "gperf_words.txt"
      {"select", 97},
      {""},
#line 8 "gperf_words.txt"
      {"asm", 68},
      {""},
#line 17 "gperf_words.txt"
      {"false", 77},
#line 24 "gperf_words.txt"
      {"import", 84},
      {""},
#line 18 "gperf_words.txt"
      {"for", 78},
      {""}, {""},
#line 29 "gperf_words.txt"
      {"module", 89},
#line 21 "gperf_words.txt"
      {"go", 81},
#line 20 "gperf_words.txt"
      {"__global", 80},
#line 22 "gperf_words.txt"
      {"goto", 82},
#line 12 "gperf_words.txt"
      {"const", 72},
#line 38 "gperf_words.txt"
      {"sizeof", 98},
      {""},
#line 13 "gperf_words.txt"
      {"continue", 73},
#line 33 "gperf_words.txt"
      {"lock", 93},
#line 14 "gperf_words.txt"
      {"defer", 74},
#line 32 "gperf_words.txt"
      {"shared", 92},
      {""},
#line 50 "gperf_words.txt"
      {"pub", 110},
#line 45 "gperf_words.txt"
      {"type", 105},
      {""},
#line 46 "gperf_words.txt"
      {"typeof", 106},
      {""}, {""}, {""}, {""}, {""}, {""}, {""}, {""}, {""},
      {""}, {""}, {""}, {""}, {""}, {""}, {""}, {""}, {""},
#line 11 "gperf_words.txt"
      {"break", 71}
    };

  if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)
    {
      register unsigned int key = gperf_hash (str, len);

      if (key <= MAX_HASH_VALUE)
        if (len == lengthtable[key])
          {
            register const char *s = wordlist[key].name;

            if (*str == *s && !memcmp (str + 1, s + 1, len - 1))
              return &wordlist[key];
          }
    }
  return 0;
}
#line 54 "gperf_words.txt"

