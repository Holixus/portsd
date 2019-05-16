#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <getopt.h>

#include <syslog.h>

#include "nano/io.h"


static char *pid_file;

/* -------------------------------------------------------------------------- */
static void create_pid_file()
{
	if (!pid_file)
		return ;
	FILE *f = fopen(pid_file, "w");
	if (!f) {
		syslog(LOG_ERR, "failed to create pid-file '%s' (%m)", pid_file);
		return ;
	}

	fprintf(f, "%d\n", getpid());

	fclose(f);
}

/* -------------------------------------------------------------------------- */
static void free_all()
{
	if (pid_file)
		unlink(pid_file);
}


/* -------------------------------------------------------------------------- */
void start(int argc, char *argv[])
{
	static struct option const long_options[] = {
	/*     name, has_arg, *flag, chr */
		{ "server",  1, 0, 'S' },
		{ "port",    1, 0, 'P' },
		{ "deamon",  0, 0, 'D' },
		{ "pid-file",1, 0, 'F' },
		{ "help",    0, 0, 'h' },
		{ 0, 0, 0, 0 }
	};

	int make_daemon = 0;
	uint32_t local_ip = 0x7F000001, local_port = 8088, server_ip = 0, server_port = 0;
	char iface[64] = "";

	for (;;) {
		int option_index;
		switch (getopt_long(argc, argv, "?hP:S:I:DF:", long_options, &option_index)) {
		case -1:
			goto _end_of_opts;

		case 'P':
			local_port = (unsigned)atoi(optarg);
			break;

		case 'S':;
			char const *srv;
			server_ip = ipv4_atoi(optarg, &srv);
			if (*srv == ':')
				server_port = (unsigned)atoi(srv + 1);
			break;

		case 'I':
			snprintf(iface, sizeof iface, "%s", optarg);
			break;

		case 'D':
			make_daemon = 1;
			break;

		case 'F':
			pid_file = strdup(optarg);
			break;

		case 'h':
		case '?':
			printf(
"Usage: %s <options>\n\n\
options:\n\
  -S, --server=<ip:port>\t: defines CRS address;\n\
  -P, --port=<port>\t\t: port to listen of connections;\n\
  -I, --iface=<interface>\t: to bind netword interace;\n\
  -D, --daemon\t\t\t: start as daemon;\n\
  -F, --pid-file=<filename>\t: set PID file name;\n\
  -h\t\t\t\t: print this help and exit.\n\n", io_prog_name);
			return;
		}
	}
_end_of_opts:

	if (make_daemon) {
		if (daemon(0, 0) < 0) {
			syslog(LOG_ERR, "daemonize failed (%m)");
			exit(1);
		}
	}

	create_pid_file();

	io_atexit(free_all);

	tcp_pipe_server_create(local_ip, local_port, *iface ? iface : NULL, 32, server_ip, server_port);
}
