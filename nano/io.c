#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <signal.h>

#include <errno.h>
#include <syslog.h>

#include <sys/poll.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>

#include <netinet/ip.h>

#include "io.h"
#include "io_timers.i"
#include "io_streams.i"
#include "io_signals.i"

#include "io_trace.i"

#include "io_ipv4.i"
#include "io_buf.i"
#include "io_redir.i"

#define MAX_ATEXIT_HANDLERS (10)

static void_fn_t *at_exits[MAX_ATEXIT_HANDLERS];
static size_t ae_len;
/* -------------------------------------------------------------------------- */
void io_atexit(void_fn_t *fn)
{
	at_exits[ae_len++] = fn;
}

/* -------------------------------------------------------------------------- */
void io_free()
{
	for (int i = 0; i < ae_len; ++i)
		at_exits[i]();

	io_timers_free();
	io_streams_free();
	closelog();
}

char const *io_prog_name;

/* -------------------------------------------------------------------------- */
int main(int argc, char *argv[])
{
	ae_len = 0;
	signals_init();
	srand((unsigned int)time(NULL));

	io_prog_name = strrchr(argv[0], '/') ?: argv[0];
	if (*io_prog_name == '/')
		++io_prog_name;

	openlog(io_prog_name, LOG_PERROR | LOG_PID, LOG_DAEMON);

	io_timers_init();
	io_streams_init();

	atexit(io_free);

	start(argc, argv);

	openlog(io_prog_name, LOG_PERROR | LOG_PID, LOG_DAEMON);
	do {
		int ret = io_streams_poll(io_get_timeout());
		if (!ret || (ret < 0 && errno != EINTR))
			return ret;
	} while (1);

	return 0;
}

