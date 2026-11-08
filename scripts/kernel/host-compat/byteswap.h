#ifndef _SCRIPTS_INCLUDE_BYTESWAP_H
#define _SCRIPTS_INCLUDE_BYTESWAP_H

#ifdef __APPLE__
#include <libkern/OSByteOrder.h>

#define bswap_16(x) OSSwapInt16(x)
#define bswap_32(x) OSSwapInt32(x)
#define bswap_64(x) OSSwapInt64(x)
#endif

#endif /* _SCRIPTS_INCLUDE_BYTESWAP_H */
