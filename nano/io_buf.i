
#define IO_BUFFER_SEGMENT_SIZE (2048)

typedef struct io_seg io_seg_t;

/* ------------------------------------------------------------------------ */
struct io_seg {
	io_seg_t *next;
	char *begin, *end;
	char data[IO_BUFFER_SEGMENT_SIZE - 3 * sizeof (void*)];
};

typedef
struct io_buf {
	io_seg_t *first, *last;
} io_buf_t;


/* ------------------------------------------------------------------------ */
static io_seg_t *io_seg_new()
{
	io_seg_t *s = (io_seg_t *)malloc(sizeof (io_seg_t));
	s->begin = s->end = s->data;
	s->next = 0;
	return s;
}

/* ------------------------------------------------------------------------ */
static void io_buf_init(io_buf_t *b)
{
	b->first = b->last = NULL;
}

/* ------------------------------------------------------------------------ */
static void io_buf_add(io_buf_t *b, io_seg_t *s)
{
	if (!b->last) {
		b->first = b->last = s;
	} else {
		b->last->next = s;
		b->last = s;
	}
}

/* ------------------------------------------------------------------------ */
static void io_buf_free(io_buf_t *b)
{
	if (!b->first)
		return ;

	io_seg_t *s = b->first, *n;
	do {
		n = s->next;
		free(s);
	} while ((s = n));
	b->first = b->last = NULL;
}

/* ------------------------------------------------------------------------ */
static int io_buf_send(io_buf_t *b, int sock)
{
	ssize_t total = 0;

	io_seg_t *s;
	while ((s = b->first)) {
		ssize_t to_send = (int)(s->end - s->begin);
		if (to_send) {
			ssize_t sent = send(sock, s->begin, (size_t)to_send, 0);
			if (sent < 0)
				return -1;
			s->begin += sent;
			if (sent < to_send) {
				return (int)(total + sent);
			}
			total += sent;
		}
		if (!(b->first = s->next))
			b->last = NULL;
		free(s);
	}

	return (int)total;
}

/* ------------------------------------------------------------------------ */
static int io_buf_recv(io_buf_t *b, int sock)
{
	ssize_t total = 0;

	io_seg_t *s = b->last;
	if (!s)
		b->first = b->last = s = io_seg_new();

_recv_more:;
	ssize_t to_recv = (signed)sizeof s->data - (s->end - s->begin);
	if (!to_recv) {
		s = io_seg_new();
		b->last->next = s;
		b->last = s;
		to_recv = (signed)sizeof s->data - (s->end - s->begin);
	}

	ssize_t len = recv(sock, s->end, (size_t)to_recv, 0);
	if (len < 0)
		return -1;

	s->end += len;
	total += len;
	if ((size_t)len == to_recv)
		goto _recv_more;

	return (int)total;
}

