#include <time.h>
#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>

#include <regex.h>


#ifndef USE_LIBC_REGEX
/* ------------------------------------------------------------------------- */
static int regex_replace(const char *source, const char *regex, const char *replace, char *dest)
{
	regexp *r = regcomp(regex);
	if (regexec(r, source) == 0) {
		free(r);
		strcpy(dest, source);
		return -1;
	}

	regsub(r, replace, dest);
	if (strcmp(dest, source) == 0) {
		// no change
		free(r);
		return 1;
	}

	free(r);
	return 0;
}
#endif

/*
	TODO: regcomp caching system

#ifdef USE_LIBC_REGEX
typedef
	regex_t regex;

typedef
struct _regex_cache {
	unsigned int key;
	char *src;
	regex *r;
	unsigned int time;  // last usage time
	unsigned int usage; // counter
} cregex_t;

cregex_t
regex *re_comp(char const *expr)
{
	regex_t *r = (regex_t *)malloc(sizeof regex_t);
	if (regcomp(r, expr, REG_EXTENDED) != 0) {
		free(r);
		return NULL;
	}
	return (regex *)r;
}

static inline void re_free(regex *r) { free(r); }
static inline void re_reset_cache() {}
#else
static inline regex *re_comp(char const *expr) { return regcomp(expr); }
static inline void re_free(regex *r) { free(r); }
static inline void re_reset_cache() {}
#endif
*/
/* ------------------------------------------------------------------------- */
const char *regex_find_ex(const char *source, const char *regex, ...)
{
	regex_t r;
	if (regcomp(&r, regex, REG_EXTENDED) != 0) {
		logg_debug("regex error: '%s'", regex);
		return NULL;
	}

	va_list ap;
	va_start(ap, regex);

	char const *ret = NULL;
	regmatch_t m[10];
	if (!regexec(&r, source, countof(m), m, 0)) {
		unsigned int i = 1;
		ret = source + m[0].rm_eo;
		for (; i < countof(m); ++i) {
			if (m[i].rm_so < 0)
				break;

			char *dest = va_arg(ap, char*);
			if (!dest)
				break;

			unsigned int size = va_arg(ap, unsigned int);
			size_t len = (size_t) (m[i].rm_eo - m[i].rm_so);
			if (len > size - 1)
				len = size - 1;
			memcpy(dest, source + m[i].rm_so, len);
			dest[len] = 0;
		}
	}

	va_end(ap);
	regfree(&r);
	return ret; /* end of matched expression */
}

/* ------------------------------------------------------------------------- */
const char *regex_find_const_ref(const char *source, const char *regex, ...)
{
	regex_t r;
	if (regcomp(&r, regex, REG_EXTENDED) != 0) {
		logg_debug("regex error: '%s'", regex);
		return NULL;
	}

	va_list ap;
	va_start(ap, regex);

	char const *ret = NULL;
	regmatch_t m[10];
	if (!regexec(&r, source, countof(m), m, 0)) {
		unsigned int i = 1;
		ret = source + m[0].rm_eo;
		for (; i < countof(m); ++i) {
			if (m[i].rm_so < 0)
				break;

			char const **start = va_arg(ap, char const**);
			char const **end = va_arg(ap, char const**);
			if (!start)
				break;

			*start = source + m[i].rm_so;
			if (end)
				*end = source + m[i].rm_eo;
		}
	}

	va_end(ap);
	regfree(&r);
	return ret;
}

/* ------------------------------------------------------------------------- */
char *regex_find_ref(char *source, const char *regex, ...)
{
	regex_t r;
	if (regcomp(&r, regex, REG_EXTENDED) != 0) {
		logg_debug("regex error: '%s'", regex);
		return NULL;
	}

	va_list ap;
	va_start(ap, regex);

	char *ret = NULL;
	regmatch_t m[10];
	if (!regexec(&r, source, countof(m), m, 0)) {
		unsigned int i = 1;
		ret = source + m[0].rm_eo;
		for (; i < countof(m); ++i) {
			if (m[i].rm_so < 0)
				break;

			char **start = va_arg(ap, char **);
			char **end = va_arg(ap, char **);
			if (!start)
				break;

			*start = source + m[i].rm_so;
			if (end)
				*end = source + m[i].rm_eo;
		}
	}

	va_end(ap);
	regfree(&r);
	return ret;
}

/* ------------------------------------------------------------------------- */
int regex_find_all_const_cb(char const *source, const char *regex,
	char const *(*cb)(char const **startp, char const **endp, void *ptr), void *ptr)
{
	regex_t r;
	if (regcomp(&r, regex, REG_EXTENDED) != 0) {
		logg_debug("regex error: '%s'", regex);
		return 0;
	}

	regmatch_t m[10];

	int count = 0;
	for (; !regexec(&r, source, countof(m), m, 0); ++count) {
		const char *startp[countof(m)], *endp[countof(m)];
		int i;
		for (i = 0; i < countof(m); ++i)
			if (m[i].rm_so < 0)
				startp[i] = endp[i] = NULL;
			else {
				startp[i] = source + m[i].rm_so;
				endp[i] = source + m[i].rm_eo;
			}

		if (!(source = cb(startp, endp, ptr)))
			break;
	}

	regfree(&r);
	return count; /* returns number of matches */
}

/* ------------------------------------------------------------------------- */
int regex_find_all_cb(char *source, const char *regex,
	char *(*cb)(char **startp, char **endp, void *ptr), void *ptr)
{
	regex_t r;
	if (regcomp(&r, regex, REG_EXTENDED) != 0) {
		logg_debug("regex error: '%s'", regex);
		return 0;
	}

	regmatch_t m[10];

	int count = 0;
	for (; !regexec(&r, source, countof(m), m, 0); ++count) {
		char *startp[countof(m)], *endp[countof(m)];
		int i;
		for (i = 0; i < countof(m); ++i)
			if (m[i].rm_so < 0)
				startp[i] = endp[i] = NULL;
			else {
				startp[i] = source + m[i].rm_so;
				endp[i] = source + m[i].rm_eo;
			}

		if (!(source = cb(startp, endp, ptr)))
			break;
	}

	regfree(&r);
	return count; /* returns number of matches */
}

