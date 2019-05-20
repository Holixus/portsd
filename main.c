#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <unistd.h>
#include <time.h>
#include <getopt.h>

#include <syslog.h>

#include "nano/io.h"


static char *pid_file;
static int verbose_mode;

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
typedef
struct ip_sock_addr {
	uint32_t ip;
	uint32_t port;
} ip_sock_addr_t;

/* -------------------------------------------------------------------------- */
static void parse_addr(char const *arg, ip_sock_addr_t *addr)
{
	char const *srv;
	addr->ip = ipv4_atoi(arg, &srv);
	if (!srv) {
		if (*optarg != ':')
			die("invalid listen IP address");
		else
			srv = arg;
	}

	if (*srv == ':')
		addr->port = (unsigned)atoi(srv + 1);
}

/* -------------------------------------------------------------------------- */
void start(int argc, char *argv[])
{
	static struct option const long_options[] = {
	/*     name, has_arg, *flag, chr */
		{ "server",  1, 0, 's' },
		{ "listen",  1, 0, 'l' },
		{ "deamon",  0, 0, 'd' },
		{ "pid-file",1, 0, 'f' },
		{ "verbose", 0, 0, 'v' },
		{ "help",    0, 0, 'h' },
		{ 0, 0, 0, 0 }
	};

	int daemon_mode = 0;
	ip_sock_addr_t listen_addr = { 0, 80 }, server_addr = { 0, 80 };
	char iface[64] = "";

	for (;;) {
		int option_index;
		switch (getopt_long(argc, argv, "?hl:s:i:dvf:", long_options, &option_index)) {
		case -1:
			goto _end_of_opts;

		case 'l':;
			parse_addr(optarg, &listen_addr);
			break;

		case 's':;
			parse_addr(optarg, &server_addr);
			break;

		case 'i':
			snprintf(iface, sizeof iface, "%s", optarg);
			break;

		case 'v':
			verbose_mode = 1;
			break;

		case 'd':
			daemon_mode = 1;
			break;

		case 'f':
			pid_file = strdup(optarg);
			break;

		case 'h':
		case '?':
			printf(
"Usage: %s <options>\n\n\
options:\n\
  -s, --server=<ip:port>\t: ip/port of peer server;\n\
  -l, --listen=<ip:port>\t: ip/port to listen of connections;\n\
  -i, --iface=<interface>\t: bind listen socket to the network interace;\n\
  -d, --daemon\t\t\t: start as daemon;\n\
  -v, --verbose\t\t\t: set verbose mode;\n\
  -f, --pid-file=<filename>\t: set PID file name;\n\
  -h\t\t\t\t: print this help and exit.\n\n", io_prog_name);
			return;
		}
	}
_end_of_opts:

	if (daemon_mode) {
		if (daemon(0, 0) < 0) {
			syslog(LOG_ERR, "daemonize failed (%m)");
			exit(1);
		}
	}

	create_pid_file();

	io_atexit(free_all);

	tcp_redir_server_create(listen_addr.ip, listen_addr.port, *iface ? iface : NULL, 32, server_addr.ip, server_addr.port);
}
