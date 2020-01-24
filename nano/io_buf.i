
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
static int io_buf_is_empty(io_buf_t *b)
{
	return !b->first;
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
static io_seg_t *io_buf_get_last_seg(io_buf_t *b)
{
	io_seg_t *s = b->last;
	if (!s)
		b->first = b->last = s = io_seg_new();
	return s;
}

/* ------------------------------------------------------------------------ */
static size_t io_buf_get_seg_to_write(io_buf_t *b, io_seg_t **ps)
{
	io_seg_t *s = *ps;
	size_t to_recv = sizeof s->data - (unsigned)(s->end - s->begin);
	if (!to_recv) {
		s = io_seg_new();
		b->last->next = s;
		b->last = s;
		to_recv = (signed)sizeof s->data - (s->end - s->begin);
	}
	*ps = s;
	return to_recv;
}

/* ------------------------------------------------------------------------ */
static int io_buf_send(io_buf_t *b, int sock)
{
	ssize_t total = 0;

	io_seg_t *s;
	while ((s = b->first)) {
		ssize_t to_send = (int)(s->end - s->begin);
		if (to_send) {
			ssize_t sent;
			do {
				sent = send(sock, s->begin, (size_t)to_send, 0);
			} while (sent < 0 && errno == EINTR);
			if (sent < 0)
				return -1;
			s->begin += sent;
			total += sent;
			if (sent < to_send)
				return (int)total;
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

	io_seg_t *s = io_buf_get_last_seg(b);

_recv_more:;
	size_t to_recv = io_buf_get_seg_to_write(b, &s);
	ssize_t len;
	do {
		len = recv(sock, s->end, to_recv, 0);
	} while (len < 0 && errno == EINTR);
	if (len < 0)
		return -1;

	s->end += len;
	total += len;
	if ((size_t)len == to_recv)
		goto _recv_more;

	return (int)total;
}

/* ------------------------------------------------------------------------ */
static ssize_t io_buf_write(io_buf_t *b, char *data, size_t size)
{
	if (!size)
		return 0;

	size_t tail = size;
	ssize_t total = 0;

	io_seg_t *s = io_buf_get_last_seg(b);

	do {
		size_t to_recv = io_buf_get_seg_to_write(b, &s);

		size_t len = to_recv > tail  ? tail : to_recv;
		memcpy(s->end, data, len);
		tail -= len;

		s->end += len;
		total += len;
	} while (tail);

	return total;
}

/* ------------------------------------------------------------------------ */
static ssize_t io_buf_read(io_buf_t *b, char *data, size_t size)
{
	size_t tail = size;
	ssize_t total = 0;

	io_seg_t *s;
	while (tail && (s = b->first)) {
		ssize_t to_send = (int)(s->end - s->begin);
		if (to_send) {
			size_t sent = to_send > tail ? tail : to_send;
			memcpy(data, s->begin, sent);
			data += sent;
			tail -= sent;

			s->begin += sent;
			total += sent;

			if (sent < to_send)
				return total;
		}
		if (!(b->first = s->next))
			b->last = NULL;
		free(s);
	}

	return total;
}

