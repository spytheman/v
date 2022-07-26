#ifndef TRIE_HASH_vfast_perfect_hash
#define TRIE_HASH_vfast_perfect_hash
#include <stddef.h>
#include <stdint.h>
enum PerfectKey {
    vfast______global = 80,
    vfast______offsetof = 102,
    vfast____likely__ = 100,
    vfast____unlikely__ = 101,
    vfast__as = 67,
    vfast__asm = 68,
    vfast__assert = 69,
    vfast__atomic = 70,
    vfast__break = 71,
    vfast__const = 72,
    vfast__continue = 73,
    vfast__defer = 74,
    vfast__dump = 107,
    vfast__else = 75,
    vfast__enum = 76,
    vfast__fn = 79,
    vfast__for = 78,
    vfast__false = 77,
    vfast__go = 81,
    vfast__goto = 82,
    vfast__if = 83,
    vfast__in = 85,
    vfast__is = 87,
    vfast__import = 84,
    vfast__interface = 86,
    vfast__isreftype = 99,
    vfast__lock = 93,
    vfast__mut = 90,
    vfast__match = 88,
    vfast__module = 89,
    vfast__nil = 91,
    vfast__none = 95,
    vfast__or = 108,
    vfast__pub = 110,
    vfast__return = 96,
    vfast__rlock = 94,
    vfast__select = 97,
    vfast__shared = 92,
    vfast__sizeof = 98,
    vfast__static = 111,
    vfast__struct = 103,
    vfast__true = 104,
    vfast__type = 105,
    vfast__typeof = 106,
    vfast__union = 109,
    vfast__unsafe = 113,
    vfast__volatile = 112,
    vfast__Unknown = -1,
};
static enum PerfectKey vfast_perfect_hash(const char *string, size_t length);
#ifdef __GNUC__
typedef uint16_t __attribute__((aligned (1))) triehash_uu16;
typedef char static_assert16[__alignof__(triehash_uu16) == 1 ? 1 : -1];
typedef uint32_t __attribute__((aligned (1))) triehash_uu32;
typedef char static_assert32[__alignof__(triehash_uu32) == 1 ? 1 : -1];
typedef uint64_t __attribute__((aligned (1))) triehash_uu64;
typedef char static_assert64[__alignof__(triehash_uu64) == 1 ? 1 : -1];
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define onechar(c, s, l) (((uint64_t)(c)) << (s))
#else
#define onechar(c, s, l) (((uint64_t)(c)) << (l-8-s))
#endif
#if (!defined(__ARM_ARCH) || defined(__ARM_FEATURE_UNALIGNED)) && !defined(TRIE_HASH_NO_MULTI_BYTE)
#define TRIE_HASH_MULTI_BYTE
#endif
#endif /*GNUC */
#ifdef TRIE_HASH_MULTI_BYTE
static enum PerfectKey vfast_perfect_hash2(const char *string)
{
    switch(string[0]) {
    case 0| onechar('a', 0, 8):
        switch(string[1]) {
        case 0| onechar('s', 0, 8):
            return vfast__as;
        }
        break;
    case 0| onechar('f', 0, 8):
        switch(string[1]) {
        case 0| onechar('n', 0, 8):
            return vfast__fn;
        }
        break;
    case 0| onechar('g', 0, 8):
        switch(string[1]) {
        case 0| onechar('o', 0, 8):
            return vfast__go;
        }
        break;
    case 0| onechar('i', 0, 8):
        switch(string[1]) {
        case 0| onechar('f', 0, 8):
            return vfast__if;
            break;
        case 0| onechar('n', 0, 8):
            return vfast__in;
            break;
        case 0| onechar('s', 0, 8):
            return vfast__is;
        }
        break;
    case 0| onechar('o', 0, 8):
        switch(string[1]) {
        case 0| onechar('r', 0, 8):
            return vfast__or;
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash3(const char *string)
{
    switch(string[0]) {
    case 0| onechar('a', 0, 8):
        switch(string[1]) {
        case 0| onechar('s', 0, 8):
            switch(string[2]) {
            case 0| onechar('m', 0, 8):
                return vfast__asm;
            }
        }
        break;
    case 0| onechar('f', 0, 8):
        switch(string[1]) {
        case 0| onechar('o', 0, 8):
            switch(string[2]) {
            case 0| onechar('r', 0, 8):
                return vfast__for;
            }
        }
        break;
    case 0| onechar('m', 0, 8):
        switch(string[1]) {
        case 0| onechar('u', 0, 8):
            switch(string[2]) {
            case 0| onechar('t', 0, 8):
                return vfast__mut;
            }
        }
        break;
    case 0| onechar('n', 0, 8):
        switch(string[1]) {
        case 0| onechar('i', 0, 8):
            switch(string[2]) {
            case 0| onechar('l', 0, 8):
                return vfast__nil;
            }
        }
        break;
    case 0| onechar('p', 0, 8):
        switch(string[1]) {
        case 0| onechar('u', 0, 8):
            switch(string[2]) {
            case 0| onechar('b', 0, 8):
                return vfast__pub;
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash4(const char *string)
{
    switch(*((triehash_uu32*) &string[0])) {
    case 0| onechar('d', 0, 32)| onechar('u', 8, 32)| onechar('m', 16, 32)| onechar('p', 24, 32):
        return vfast__dump;
        break;
    case 0| onechar('e', 0, 32)| onechar('l', 8, 32)| onechar('s', 16, 32)| onechar('e', 24, 32):
        return vfast__else;
        break;
    case 0| onechar('e', 0, 32)| onechar('n', 8, 32)| onechar('u', 16, 32)| onechar('m', 24, 32):
        return vfast__enum;
        break;
    case 0| onechar('g', 0, 32)| onechar('o', 8, 32)| onechar('t', 16, 32)| onechar('o', 24, 32):
        return vfast__goto;
        break;
    case 0| onechar('l', 0, 32)| onechar('o', 8, 32)| onechar('c', 16, 32)| onechar('k', 24, 32):
        return vfast__lock;
        break;
    case 0| onechar('n', 0, 32)| onechar('o', 8, 32)| onechar('n', 16, 32)| onechar('e', 24, 32):
        return vfast__none;
        break;
    case 0| onechar('t', 0, 32)| onechar('r', 8, 32)| onechar('u', 16, 32)| onechar('e', 24, 32):
        return vfast__true;
        break;
    case 0| onechar('t', 0, 32)| onechar('y', 8, 32)| onechar('p', 16, 32)| onechar('e', 24, 32):
        return vfast__type;
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash5(const char *string)
{
    switch(*((triehash_uu32*) &string[0])) {
    case 0| onechar('b', 0, 32)| onechar('r', 8, 32)| onechar('e', 16, 32)| onechar('a', 24, 32):
        switch(string[4]) {
        case 0| onechar('k', 0, 8):
            return vfast__break;
        }
        break;
    case 0| onechar('c', 0, 32)| onechar('o', 8, 32)| onechar('n', 16, 32)| onechar('s', 24, 32):
        switch(string[4]) {
        case 0| onechar('t', 0, 8):
            return vfast__const;
        }
        break;
    case 0| onechar('d', 0, 32)| onechar('e', 8, 32)| onechar('f', 16, 32)| onechar('e', 24, 32):
        switch(string[4]) {
        case 0| onechar('r', 0, 8):
            return vfast__defer;
        }
        break;
    case 0| onechar('f', 0, 32)| onechar('a', 8, 32)| onechar('l', 16, 32)| onechar('s', 24, 32):
        switch(string[4]) {
        case 0| onechar('e', 0, 8):
            return vfast__false;
        }
        break;
    case 0| onechar('m', 0, 32)| onechar('a', 8, 32)| onechar('t', 16, 32)| onechar('c', 24, 32):
        switch(string[4]) {
        case 0| onechar('h', 0, 8):
            return vfast__match;
        }
        break;
    case 0| onechar('r', 0, 32)| onechar('l', 8, 32)| onechar('o', 16, 32)| onechar('c', 24, 32):
        switch(string[4]) {
        case 0| onechar('k', 0, 8):
            return vfast__rlock;
        }
        break;
    case 0| onechar('u', 0, 32)| onechar('n', 8, 32)| onechar('i', 16, 32)| onechar('o', 24, 32):
        switch(string[4]) {
        case 0| onechar('n', 0, 8):
            return vfast__union;
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash6(const char *string)
{
    switch(*((triehash_uu32*) &string[0])) {
    case 0| onechar('a', 0, 32)| onechar('s', 8, 32)| onechar('s', 16, 32)| onechar('e', 24, 32):
        switch(string[4]) {
        case 0| onechar('r', 0, 8):
            switch(string[5]) {
            case 0| onechar('t', 0, 8):
                return vfast__assert;
            }
        }
        break;
    case 0| onechar('a', 0, 32)| onechar('t', 8, 32)| onechar('o', 16, 32)| onechar('m', 24, 32):
        switch(string[4]) {
        case 0| onechar('i', 0, 8):
            switch(string[5]) {
            case 0| onechar('c', 0, 8):
                return vfast__atomic;
            }
        }
        break;
    case 0| onechar('i', 0, 32)| onechar('m', 8, 32)| onechar('p', 16, 32)| onechar('o', 24, 32):
        switch(string[4]) {
        case 0| onechar('r', 0, 8):
            switch(string[5]) {
            case 0| onechar('t', 0, 8):
                return vfast__import;
            }
        }
        break;
    case 0| onechar('m', 0, 32)| onechar('o', 8, 32)| onechar('d', 16, 32)| onechar('u', 24, 32):
        switch(string[4]) {
        case 0| onechar('l', 0, 8):
            switch(string[5]) {
            case 0| onechar('e', 0, 8):
                return vfast__module;
            }
        }
        break;
    case 0| onechar('r', 0, 32)| onechar('e', 8, 32)| onechar('t', 16, 32)| onechar('u', 24, 32):
        switch(string[4]) {
        case 0| onechar('r', 0, 8):
            switch(string[5]) {
            case 0| onechar('n', 0, 8):
                return vfast__return;
            }
        }
        break;
    case 0| onechar('s', 0, 32)| onechar('e', 8, 32)| onechar('l', 16, 32)| onechar('e', 24, 32):
        switch(string[4]) {
        case 0| onechar('c', 0, 8):
            switch(string[5]) {
            case 0| onechar('t', 0, 8):
                return vfast__select;
            }
        }
        break;
    case 0| onechar('s', 0, 32)| onechar('h', 8, 32)| onechar('a', 16, 32)| onechar('r', 24, 32):
        switch(string[4]) {
        case 0| onechar('e', 0, 8):
            switch(string[5]) {
            case 0| onechar('d', 0, 8):
                return vfast__shared;
            }
        }
        break;
    case 0| onechar('s', 0, 32)| onechar('i', 8, 32)| onechar('z', 16, 32)| onechar('e', 24, 32):
        switch(string[4]) {
        case 0| onechar('o', 0, 8):
            switch(string[5]) {
            case 0| onechar('f', 0, 8):
                return vfast__sizeof;
            }
        }
        break;
    case 0| onechar('s', 0, 32)| onechar('t', 8, 32)| onechar('a', 16, 32)| onechar('t', 24, 32):
        switch(string[4]) {
        case 0| onechar('i', 0, 8):
            switch(string[5]) {
            case 0| onechar('c', 0, 8):
                return vfast__static;
            }
        }
        break;
    case 0| onechar('s', 0, 32)| onechar('t', 8, 32)| onechar('r', 16, 32)| onechar('u', 24, 32):
        switch(string[4]) {
        case 0| onechar('c', 0, 8):
            switch(string[5]) {
            case 0| onechar('t', 0, 8):
                return vfast__struct;
            }
        }
        break;
    case 0| onechar('t', 0, 32)| onechar('y', 8, 32)| onechar('p', 16, 32)| onechar('e', 24, 32):
        switch(string[4]) {
        case 0| onechar('o', 0, 8):
            switch(string[5]) {
            case 0| onechar('f', 0, 8):
                return vfast__typeof;
            }
        }
        break;
    case 0| onechar('u', 0, 32)| onechar('n', 8, 32)| onechar('s', 16, 32)| onechar('a', 24, 32):
        switch(string[4]) {
        case 0| onechar('f', 0, 8):
            switch(string[5]) {
            case 0| onechar('e', 0, 8):
                return vfast__unsafe;
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash8(const char *string)
{
    switch(*((triehash_uu64*) &string[0])) {
    case 0| onechar('_', 0, 64)| onechar('_', 8, 64)| onechar('g', 16, 64)| onechar('l', 24, 64)| onechar('o', 32, 64)| onechar('b', 40, 64)| onechar('a', 48, 64)| onechar('l', 56, 64):
        return vfast______global;
        break;
    case 0| onechar('_', 0, 64)| onechar('l', 8, 64)| onechar('i', 16, 64)| onechar('k', 24, 64)| onechar('e', 32, 64)| onechar('l', 40, 64)| onechar('y', 48, 64)| onechar('_', 56, 64):
        return vfast____likely__;
        break;
    case 0| onechar('c', 0, 64)| onechar('o', 8, 64)| onechar('n', 16, 64)| onechar('t', 24, 64)| onechar('i', 32, 64)| onechar('n', 40, 64)| onechar('u', 48, 64)| onechar('e', 56, 64):
        return vfast__continue;
        break;
    case 0| onechar('v', 0, 64)| onechar('o', 8, 64)| onechar('l', 16, 64)| onechar('a', 24, 64)| onechar('t', 32, 64)| onechar('i', 40, 64)| onechar('l', 48, 64)| onechar('e', 56, 64):
        return vfast__volatile;
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash9(const char *string)
{
    switch(*((triehash_uu64*) &string[0])) {
    case 0| onechar('i', 0, 64)| onechar('n', 8, 64)| onechar('t', 16, 64)| onechar('e', 24, 64)| onechar('r', 32, 64)| onechar('f', 40, 64)| onechar('a', 48, 64)| onechar('c', 56, 64):
        switch(string[8]) {
        case 0| onechar('e', 0, 8):
            return vfast__interface;
        }
        break;
    case 0| onechar('i', 0, 64)| onechar('s', 8, 64)| onechar('r', 16, 64)| onechar('e', 24, 64)| onechar('f', 32, 64)| onechar('t', 40, 64)| onechar('y', 48, 64)| onechar('p', 56, 64):
        switch(string[8]) {
        case 0| onechar('e', 0, 8):
            return vfast__isreftype;
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash10(const char *string)
{
    switch(*((triehash_uu64*) &string[0])) {
    case 0| onechar('_', 0, 64)| onechar('_', 8, 64)| onechar('o', 16, 64)| onechar('f', 24, 64)| onechar('f', 32, 64)| onechar('s', 40, 64)| onechar('e', 48, 64)| onechar('t', 56, 64):
        switch(string[8]) {
        case 0| onechar('o', 0, 8):
            switch(string[9]) {
            case 0| onechar('f', 0, 8):
                return vfast______offsetof;
            }
        }
        break;
    case 0| onechar('_', 0, 64)| onechar('u', 8, 64)| onechar('n', 16, 64)| onechar('l', 24, 64)| onechar('i', 32, 64)| onechar('k', 40, 64)| onechar('e', 48, 64)| onechar('l', 56, 64):
        switch(string[8]) {
        case 0| onechar('y', 0, 8):
            switch(string[9]) {
            case 0| onechar('_', 0, 8):
                return vfast____unlikely__;
            }
        }
    }
    return vfast__Unknown;
}
#else
static enum PerfectKey vfast_perfect_hash2(const char *string)
{
    switch(string[0]) {
    case 'a':
        switch(string[1]) {
        case 's':
            return vfast__as;
        }
        break;
    case 'f':
        switch(string[1]) {
        case 'n':
            return vfast__fn;
        }
        break;
    case 'g':
        switch(string[1]) {
        case 'o':
            return vfast__go;
        }
        break;
    case 'i':
        switch(string[1]) {
        case 'f':
            return vfast__if;
            break;
        case 'n':
            return vfast__in;
            break;
        case 's':
            return vfast__is;
        }
        break;
    case 'o':
        switch(string[1]) {
        case 'r':
            return vfast__or;
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash3(const char *string)
{
    switch(string[0]) {
    case 'a':
        switch(string[1]) {
        case 's':
            switch(string[2]) {
            case 'm':
                return vfast__asm;
            }
        }
        break;
    case 'f':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 'r':
                return vfast__for;
            }
        }
        break;
    case 'm':
        switch(string[1]) {
        case 'u':
            switch(string[2]) {
            case 't':
                return vfast__mut;
            }
        }
        break;
    case 'n':
        switch(string[1]) {
        case 'i':
            switch(string[2]) {
            case 'l':
                return vfast__nil;
            }
        }
        break;
    case 'p':
        switch(string[1]) {
        case 'u':
            switch(string[2]) {
            case 'b':
                return vfast__pub;
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash4(const char *string)
{
    switch(string[0]) {
    case 'd':
        switch(string[1]) {
        case 'u':
            switch(string[2]) {
            case 'm':
                switch(string[3]) {
                case 'p':
                    return vfast__dump;
                }
            }
        }
        break;
    case 'e':
        switch(string[1]) {
        case 'l':
            switch(string[2]) {
            case 's':
                switch(string[3]) {
                case 'e':
                    return vfast__else;
                }
            }
            break;
        case 'n':
            switch(string[2]) {
            case 'u':
                switch(string[3]) {
                case 'm':
                    return vfast__enum;
                }
            }
        }
        break;
    case 'g':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 't':
                switch(string[3]) {
                case 'o':
                    return vfast__goto;
                }
            }
        }
        break;
    case 'l':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 'c':
                switch(string[3]) {
                case 'k':
                    return vfast__lock;
                }
            }
        }
        break;
    case 'n':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 'n':
                switch(string[3]) {
                case 'e':
                    return vfast__none;
                }
            }
        }
        break;
    case 't':
        switch(string[1]) {
        case 'r':
            switch(string[2]) {
            case 'u':
                switch(string[3]) {
                case 'e':
                    return vfast__true;
                }
            }
            break;
        case 'y':
            switch(string[2]) {
            case 'p':
                switch(string[3]) {
                case 'e':
                    return vfast__type;
                }
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash5(const char *string)
{
    switch(string[0]) {
    case 'b':
        switch(string[1]) {
        case 'r':
            switch(string[2]) {
            case 'e':
                switch(string[3]) {
                case 'a':
                    switch(string[4]) {
                    case 'k':
                        return vfast__break;
                    }
                }
            }
        }
        break;
    case 'c':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 'n':
                switch(string[3]) {
                case 's':
                    switch(string[4]) {
                    case 't':
                        return vfast__const;
                    }
                }
            }
        }
        break;
    case 'd':
        switch(string[1]) {
        case 'e':
            switch(string[2]) {
            case 'f':
                switch(string[3]) {
                case 'e':
                    switch(string[4]) {
                    case 'r':
                        return vfast__defer;
                    }
                }
            }
        }
        break;
    case 'f':
        switch(string[1]) {
        case 'a':
            switch(string[2]) {
            case 'l':
                switch(string[3]) {
                case 's':
                    switch(string[4]) {
                    case 'e':
                        return vfast__false;
                    }
                }
            }
        }
        break;
    case 'm':
        switch(string[1]) {
        case 'a':
            switch(string[2]) {
            case 't':
                switch(string[3]) {
                case 'c':
                    switch(string[4]) {
                    case 'h':
                        return vfast__match;
                    }
                }
            }
        }
        break;
    case 'r':
        switch(string[1]) {
        case 'l':
            switch(string[2]) {
            case 'o':
                switch(string[3]) {
                case 'c':
                    switch(string[4]) {
                    case 'k':
                        return vfast__rlock;
                    }
                }
            }
        }
        break;
    case 'u':
        switch(string[1]) {
        case 'n':
            switch(string[2]) {
            case 'i':
                switch(string[3]) {
                case 'o':
                    switch(string[4]) {
                    case 'n':
                        return vfast__union;
                    }
                }
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash6(const char *string)
{
    switch(string[0]) {
    case 'a':
        switch(string[1]) {
        case 's':
            switch(string[2]) {
            case 's':
                switch(string[3]) {
                case 'e':
                    switch(string[4]) {
                    case 'r':
                        switch(string[5]) {
                        case 't':
                            return vfast__assert;
                        }
                    }
                }
            }
            break;
        case 't':
            switch(string[2]) {
            case 'o':
                switch(string[3]) {
                case 'm':
                    switch(string[4]) {
                    case 'i':
                        switch(string[5]) {
                        case 'c':
                            return vfast__atomic;
                        }
                    }
                }
            }
        }
        break;
    case 'i':
        switch(string[1]) {
        case 'm':
            switch(string[2]) {
            case 'p':
                switch(string[3]) {
                case 'o':
                    switch(string[4]) {
                    case 'r':
                        switch(string[5]) {
                        case 't':
                            return vfast__import;
                        }
                    }
                }
            }
        }
        break;
    case 'm':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 'd':
                switch(string[3]) {
                case 'u':
                    switch(string[4]) {
                    case 'l':
                        switch(string[5]) {
                        case 'e':
                            return vfast__module;
                        }
                    }
                }
            }
        }
        break;
    case 'r':
        switch(string[1]) {
        case 'e':
            switch(string[2]) {
            case 't':
                switch(string[3]) {
                case 'u':
                    switch(string[4]) {
                    case 'r':
                        switch(string[5]) {
                        case 'n':
                            return vfast__return;
                        }
                    }
                }
            }
        }
        break;
    case 's':
        switch(string[1]) {
        case 'e':
            switch(string[2]) {
            case 'l':
                switch(string[3]) {
                case 'e':
                    switch(string[4]) {
                    case 'c':
                        switch(string[5]) {
                        case 't':
                            return vfast__select;
                        }
                    }
                }
            }
            break;
        case 'h':
            switch(string[2]) {
            case 'a':
                switch(string[3]) {
                case 'r':
                    switch(string[4]) {
                    case 'e':
                        switch(string[5]) {
                        case 'd':
                            return vfast__shared;
                        }
                    }
                }
            }
            break;
        case 'i':
            switch(string[2]) {
            case 'z':
                switch(string[3]) {
                case 'e':
                    switch(string[4]) {
                    case 'o':
                        switch(string[5]) {
                        case 'f':
                            return vfast__sizeof;
                        }
                    }
                }
            }
            break;
        case 't':
            switch(string[2]) {
            case 'a':
                switch(string[3]) {
                case 't':
                    switch(string[4]) {
                    case 'i':
                        switch(string[5]) {
                        case 'c':
                            return vfast__static;
                        }
                    }
                }
                break;
            case 'r':
                switch(string[3]) {
                case 'u':
                    switch(string[4]) {
                    case 'c':
                        switch(string[5]) {
                        case 't':
                            return vfast__struct;
                        }
                    }
                }
            }
        }
        break;
    case 't':
        switch(string[1]) {
        case 'y':
            switch(string[2]) {
            case 'p':
                switch(string[3]) {
                case 'e':
                    switch(string[4]) {
                    case 'o':
                        switch(string[5]) {
                        case 'f':
                            return vfast__typeof;
                        }
                    }
                }
            }
        }
        break;
    case 'u':
        switch(string[1]) {
        case 'n':
            switch(string[2]) {
            case 's':
                switch(string[3]) {
                case 'a':
                    switch(string[4]) {
                    case 'f':
                        switch(string[5]) {
                        case 'e':
                            return vfast__unsafe;
                        }
                    }
                }
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash8(const char *string)
{
    switch(string[0]) {
    case '_':
        switch(string[1]) {
        case '_':
            switch(string[2]) {
            case 'g':
                switch(string[3]) {
                case 'l':
                    switch(string[4]) {
                    case 'o':
                        switch(string[5]) {
                        case 'b':
                            switch(string[6]) {
                            case 'a':
                                switch(string[7]) {
                                case 'l':
                                    return vfast______global;
                                }
                            }
                        }
                    }
                }
            }
            break;
        case 'l':
            switch(string[2]) {
            case 'i':
                switch(string[3]) {
                case 'k':
                    switch(string[4]) {
                    case 'e':
                        switch(string[5]) {
                        case 'l':
                            switch(string[6]) {
                            case 'y':
                                switch(string[7]) {
                                case '_':
                                    return vfast____likely__;
                                }
                            }
                        }
                    }
                }
            }
        }
        break;
    case 'c':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 'n':
                switch(string[3]) {
                case 't':
                    switch(string[4]) {
                    case 'i':
                        switch(string[5]) {
                        case 'n':
                            switch(string[6]) {
                            case 'u':
                                switch(string[7]) {
                                case 'e':
                                    return vfast__continue;
                                }
                            }
                        }
                    }
                }
            }
        }
        break;
    case 'v':
        switch(string[1]) {
        case 'o':
            switch(string[2]) {
            case 'l':
                switch(string[3]) {
                case 'a':
                    switch(string[4]) {
                    case 't':
                        switch(string[5]) {
                        case 'i':
                            switch(string[6]) {
                            case 'l':
                                switch(string[7]) {
                                case 'e':
                                    return vfast__volatile;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash9(const char *string)
{
    switch(string[0]) {
    case 'i':
        switch(string[1]) {
        case 'n':
            switch(string[2]) {
            case 't':
                switch(string[3]) {
                case 'e':
                    switch(string[4]) {
                    case 'r':
                        switch(string[5]) {
                        case 'f':
                            switch(string[6]) {
                            case 'a':
                                switch(string[7]) {
                                case 'c':
                                    switch(string[8]) {
                                    case 'e':
                                        return vfast__interface;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            break;
        case 's':
            switch(string[2]) {
            case 'r':
                switch(string[3]) {
                case 'e':
                    switch(string[4]) {
                    case 'f':
                        switch(string[5]) {
                        case 't':
                            switch(string[6]) {
                            case 'y':
                                switch(string[7]) {
                                case 'p':
                                    switch(string[8]) {
                                    case 'e':
                                        return vfast__isreftype;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return vfast__Unknown;
}
static enum PerfectKey vfast_perfect_hash10(const char *string)
{
    switch(string[0]) {
    case '_':
        switch(string[1]) {
        case '_':
            switch(string[2]) {
            case 'o':
                switch(string[3]) {
                case 'f':
                    switch(string[4]) {
                    case 'f':
                        switch(string[5]) {
                        case 's':
                            switch(string[6]) {
                            case 'e':
                                switch(string[7]) {
                                case 't':
                                    switch(string[8]) {
                                    case 'o':
                                        switch(string[9]) {
                                        case 'f':
                                            return vfast______offsetof;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            break;
        case 'u':
            switch(string[2]) {
            case 'n':
                switch(string[3]) {
                case 'l':
                    switch(string[4]) {
                    case 'i':
                        switch(string[5]) {
                        case 'k':
                            switch(string[6]) {
                            case 'e':
                                switch(string[7]) {
                                case 'l':
                                    switch(string[8]) {
                                    case 'y':
                                        switch(string[9]) {
                                        case '_':
                                            return vfast____unlikely__;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return vfast__Unknown;
}
#endif /* TRIE_HASH_MULTI_BYTE */
static enum PerfectKey vfast_perfect_hash(const char *string, size_t length)
{
    switch (length) {
    case 2:
        return vfast_perfect_hash2(string);
    case 3:
        return vfast_perfect_hash3(string);
    case 4:
        return vfast_perfect_hash4(string);
    case 5:
        return vfast_perfect_hash5(string);
    case 6:
        return vfast_perfect_hash6(string);
    case 8:
        return vfast_perfect_hash8(string);
    case 9:
        return vfast_perfect_hash9(string);
    case 10:
        return vfast_perfect_hash10(string);
    default:
        return vfast__Unknown;
    }
}
#endif                       /* TRIE_HASH_vfast_perfect_hash */
