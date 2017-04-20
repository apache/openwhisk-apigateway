CC?=gcc 

CFLAGS=-g -fpic
LDFLAGS=-g -shared
LDLIBS=-lhiredis

libcache_invalidator.so: cache_invalidator.o
	$(CC) $(LDFLAGS) $< $(LOADLIBES) $(LDLIBS) -o $@

install: libcache_invalidator.so
	cp $< /usr/local/lib

