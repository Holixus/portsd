#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <unistd.h>
#include <time.h>
#include <getopt.h>

#include <syslog.h>
#include <regex.h>


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
	uint32_t ports_num;
} ip_sock_addr_t;


/* -------------------------------------------------------------------------- */
void start(int argc, char *argv[])
{
	static struct option const long_options[] = {
	/*     name, has_arg, *flag, chr */
		{ "daemon",  0, 0, 'd' },
		{ "pid-file",1, 0, 'f' },
		{ "verbose", 0, 0, 'v' },
		{ "help",    0, 0, 'h' },
		{ 0, 0, 0, 0 }
	};

	int daemon_mode = 0;

	for (;;) {
		int option_index;
		switch (getopt_long(argc, argv, "?hdvf:", long_options, &option_index)) {
		case -1:
			goto _end_of_opts;

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
"Usage: %s <options> [ip:port[-port]]+ \n\n\
options:\n\
  -d, --daemon\t\t\t: start as daemon;\n\
  -v, --verbose\t\t\t: set verbose mode;\n\
  -f, --pid-file=<filename>\t: set PID file name;\n\
  -h\t\t\t\t: print this help and exit.\n\n", io_prog_name);
			return;
		}
	}
_end_of_opts:;

	ip_sock_addr_t servs[30];
	int servs_num = 0;

	if (optind < argc) {
		regex_t r;
		if (regcomp(&r, "^([0-9.]{7,15})?:([0-9]{1,5})(-[0-9]{1,5})?$", REG_EXTENDED) != 0) {
			syslog(LOG_CRIT, "A");
			exit(1);
		}
		for (; optind < argc; ++optind) {
			regmatch_t m[10];
			char *arg = argv[optind];
			if (!regexec(&r, arg, 10, m, 0)) {
				ip_sock_addr_t *s = servs + servs_num++;
				s->ip = m[1].rm_so >= 0 ? ipv4_atoi(arg + m[1].rm_so, NULL) : 0;
				s->port = atoi(arg + m[2].rm_so);
				s->ports_num = (m[3].rm_so > 0) ? atoi(arg + m[3].rm_so + 1) - s->port + 1 : 1;
				if (s->ports_num < 1) {
					syslog(LOG_ERR, "invalid argument: '%s'", arg);
					--servs_num;
				} else
					syslog(LOG_NOTICE, "listen server: %s:%d-%d", ipv4_itoa(s->ip), s->port, s->port + s->ports_num - 1);
			} else {
				syslog(LOG_ERR, "invalid argument: '%s'", arg);
			}
		}
		regfree(&r);
	}

	if (daemon_mode) {
		if (daemon(0, 0) < 0) {
			syslog(LOG_ERR, "daemonize failed (%m)");
			exit(1);
		}
	}

	create_pid_file();

	io_atexit(free_all);

	for (int i = 0; i < servs_num; ++i) {
		ip_sock_addr_t *s = servs + i;
		for (int n = 0; n < s->ports_num; ++n)
			tcp_reply_server_create(s->ip, s->port + n, NULL, 32);
	}
}
