/* Host-only compatibility for Linux modpost built on macOS. */
#define uuid_t darwin_host_uuid_t
#include <sys/types.h>
#include <unistd.h>
#undef uuid_t
