CC = gcc
CFLAGS = -fPIC -Walle -fpermissive

INC = -I. -I/usr/include
LIBS_INCDIR = -L../../lib
LIBS = -lOB -lstdc++

SRC_CPP_FILE = ${@F:.o=.cpp}

.cpp.o:
	@echo ---------------------------------------------------------------
	@echo OBJECT $(@F)
	$(CC) -c $(CFLAGS) $(INC) $(SRC_CPP_FILE) -D_DEBUG
	@echo ---------------------------------------------------------------

SERVER_OBJS = server.o apptest.o apptest_skel.o apptest_impl.o

CLIENT_OBJS = client.o apptest.o

all: server client

server: ${SERVER_OBJS}
	${CC} -o server ${CFLAGS} ${SERVER_OBJS} ${LIBS_INCDIR} ${LIBS}

client: ${CLIENT_OBJS}
	${CC} -o client ${CFLAGS} ${CLIENT_OBJS} ${LIBS_INCDIR} ${LIBS}

clean:
	@rm -f server client ${SERVER_OBJS} ${CLIENT_OBJS}
	@echo "all cleaned up!"