#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <hiredis/hiredis.h>
#include <string.h>

int invalidate_loop(void(*f)(char*)) {
  printf("Starting cache invalidation loop. \n");
  int pid = fork();
  if (pid != 0) {
    return pid;
  }
  char* redisHost = getenv("REDIS_HOST");
  int redisPort = atoi(getenv("REDIS_PORT"));
  char* redisPass = getenv("REDIS_PASS");
  redisContext *redis = redisConnect(redisHost, redisPort);
  if (redisPass != NULL) {
    redisCommand(redis, "AUTH %s", redisPass);
  }

  redisCommand(redis, "config set notify-keyspace-events KEA");
  redisCommand(redis, "psubscribe __keyspace@0__:*");
  redisReply *reply;
  while (true) {
    int p = redisGetReply(redis, &reply);
    if (reply != 0) {
      f(reply->element[2]->str);
      freeReplyObject(reply);
    }
  }
}
