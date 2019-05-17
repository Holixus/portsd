#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

static void trace(char const *fmt, ...) __attribute__ ((format (printf, 1, 2)));


static char const io_trace_file[] = "/tmp/io.log";

static void trace_clean()
{
	close(open(io_trace_file, O_CREAT|O_TRUNC|O_WRONLY, 0666));
}

static void trace(char const *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	int fd = open(io_trace_file, O_APPEND|O_CREAT|O_WRONLY, 0666);
	char msg[256];
	if (write(fd, msg, (size_t)vsnprintf(msg, sizeof msg, fmt, ap)) < 0)
		perror("io_trace: %m");
	close(fd);
	va_end(ap);
}

/* -------------------------------------------------------------------------- */
void die(char const *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	exit(1);
}

