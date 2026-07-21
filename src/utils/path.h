#ifndef NSL_UTILS_PATH_H
#define NSL_UTILS_PATH_H

#include <stdbool.h>

bool path_is_absolute(const char *path);
char *path_to_file_uri(const char *path);
char *file_uri_to_path(const char *uri);

#endif
