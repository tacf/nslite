#include <stdlib.h>
#include <string.h>
#include <git2.h>
#include "api.h"

#define API_TYPE_GIT_REPO "GitRepo"

#define OID_BUFSZ (GIT_OID_MAX_HEXSIZE + 1)
#define OID_SHORT_LEN 12


typedef struct {
  git_repository *repo;
} GitRepo;


typedef struct {
  git_oid oid;
  char *name;
} GitRefEntry;


typedef struct {
  GitRefEntry *entries;
  size_t count;
  size_t capacity;
} GitRefList;


static char *dup_str(const char *s) {
  size_t len = strlen(s);
  char *out = malloc(len + 1);
  if (out) { memcpy(out, s, len + 1); }
  return out;
}


static int push_error(lua_State *L, const char *what) {
  const git_error *err = git_error_last();
  lua_pushnil(L);
  if (err && err->message) {
    lua_pushfstring(L, "%s: %s", what, err->message);
  } else {
    lua_pushstring(L, what);
  }
  return 2;
}


static void refs_list_free(GitRefList *list) {
  for (size_t i = 0; i < list->count; i++) { free(list->entries[i].name); }
  free(list->entries);
  list->entries = NULL;
  list->count = 0;
  list->capacity = 0;
}


static int add_ref(GitRefList *list, const git_oid *oid, const char *name) {
  if (list->count == list->capacity) {
    size_t cap = list->capacity ? list->capacity * 2 : 8;
    GitRefEntry *entries = realloc(list->entries, cap * sizeof(*entries));
    if (!entries) { return -1; }
    list->entries = entries;
    list->capacity = cap;
  }
  char *copy = dup_str(name);
  if (!copy) { return -1; }
  list->entries[list->count].oid = *oid;
  list->entries[list->count].name = copy;
  list->count++;
  return 0;
}


static int ref_cb(git_reference *ref, void *payload) {
  GitRefList *list = payload;
  git_object *obj = NULL;
  if (git_reference_peel(&obj, ref, GIT_OBJECT_COMMIT) < 0) { return 0; }
  int ok = add_ref(list, git_object_id(obj), git_reference_name(ref));
  git_object_free(obj);
  return ok < 0 ? -1 : 0;
}


static int f_open(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  git_repository *repo = NULL;
  int err = git_repository_open_ext(&repo, path, 0, NULL);
  if (err < 0) { return push_error(L, "could not open repository"); }
  /* set repo before the metatable so __gc never sees a stale pointer */
  GitRepo *self = lua_newuserdatauv(L, sizeof(*self), 0);
  self->repo = repo;
  luaL_setmetatable(L, API_TYPE_GIT_REPO);
  return 1;
}


static GitRepo *check_repo(lua_State *L) {
  GitRepo *self = luaL_checkudata(L, 1, API_TYPE_GIT_REPO);
  if (!self->repo) { luaL_error(L, "repository is closed"); }
  return self;
}


static int f_path(lua_State *L) {
  GitRepo *self = check_repo(L);
  const char *workdir = git_repository_workdir(self->repo);
  lua_pushstring(L, workdir ? workdir : git_repository_path(self->repo));
  return 1;
}


static int f_head(lua_State *L) {
  GitRepo *self = check_repo(L);
  git_reference *head = NULL;
  if (git_repository_head(&head, self->repo) < 0) {
    return push_error(L, "could not resolve HEAD");
  }
  const git_oid *oid = git_reference_target(head);
  if (!oid) {
    git_reference_free(head);
    lua_pushnil(L);
    lua_pushliteral(L, "HEAD is symbolic");
    return 2;
  }
  char buf[OID_BUFSZ];
  git_oid_tostr(buf, sizeof(buf), oid);
  git_reference_free(head);
  lua_pushstring(L, buf);
  return 1;
}


static int f_log(lua_State *L) {
  GitRepo *self = check_repo(L);
  int max_count = 0;
  if (!lua_isnoneornil(L, 2)) { max_count = (int) luaL_checkinteger(L, 2); }

  GitRefList refs = { 0 };
  if (git_reference_foreach(self->repo, ref_cb, &refs) < 0) {
    refs_list_free(&refs);
    return push_error(L, "could not read references");
  }

  git_reference *head = NULL;
  if (git_repository_head(&head, self->repo) == 0) {
    git_object *obj = NULL;
    if (git_reference_peel(&obj, head, GIT_OBJECT_COMMIT) == 0) {
      if (add_ref(&refs, git_object_id(obj), "HEAD") < 0) {
        git_object_free(obj);
        git_reference_free(head);
        refs_list_free(&refs);
        lua_pushnil(L);
        lua_pushliteral(L, "out of memory");
        return 2;
      }
      git_object_free(obj);
    }
    git_reference_free(head);
  }

  git_revwalk *walk = NULL;
  int err = git_revwalk_new(&walk, self->repo);
  if (err < 0) {
    refs_list_free(&refs);
    return push_error(L, "could not create revision walker");
  }
  git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL | GIT_SORT_TIME);

  err = git_revwalk_push_head(walk);
  if (err < 0) {
    git_revwalk_free(walk);
    refs_list_free(&refs);
    if (err == GIT_ENOTFOUND) {
      lua_newtable(L);
      return 1;
    }
    return push_error(L, "could not walk HEAD");
  }

  lua_newtable(L);
  git_oid oid;
  int index = 0;
  char oid_buf[OID_BUFSZ];
  while ((max_count <= 0 || index < max_count)
    && git_revwalk_next(&oid, walk) == 0) {

    git_commit *commit = NULL;
    if (git_commit_lookup(&commit, self->repo, &oid) < 0) { continue; }

    lua_newtable(L);

    git_oid_tostr(oid_buf, sizeof(oid_buf), &oid);
    lua_pushstring(L, oid_buf);
    lua_setfield(L, -2, "oid");
    lua_pushlstring(L, oid_buf, OID_SHORT_LEN);
    lua_setfield(L, -2, "short");

    const char *summary = git_commit_summary(commit);
    lua_pushstring(L, summary ? summary : "");
    lua_setfield(L, -2, "summary");

    const git_signature *author = git_commit_author(commit);
    lua_pushstring(L, author && author->name ? author->name : "");
    lua_setfield(L, -2, "author");
    lua_pushstring(L, author && author->email ? author->email : "");
    lua_setfield(L, -2, "author_email");
    lua_pushinteger(L, (lua_Integer) git_commit_time(commit));
    lua_setfield(L, -2, "author_time");

    unsigned int parent_count = git_commit_parentcount(commit);
    lua_newtable(L);
    for (unsigned int i = 0; i < parent_count; i++) {
      char pbuf[OID_BUFSZ];
      git_oid_tostr(pbuf, sizeof(pbuf), git_commit_parent_id(commit, i));
      lua_pushstring(L, pbuf);
      lua_rawseti(L, -2, (int) i + 1);
    }
    lua_setfield(L, -2, "parents");

    /* build the refs table lazily; most commits have none */
    int ri = 0;
    for (size_t i = 0; i < refs.count; i++) {
      if (!git_oid_equal(&refs.entries[i].oid, &oid)) { continue; }
      if (ri == 0) { lua_newtable(L); }
      lua_pushstring(L, refs.entries[i].name);
      lua_rawseti(L, -2, ++ri);
    }
    if (ri > 0) { lua_setfield(L, -2, "refs"); }

    lua_rawseti(L, -2, ++index);
    git_commit_free(commit);
  }

  git_revwalk_free(walk);
  refs_list_free(&refs);
  return 1;
}


static int f_close(lua_State *L) {
  GitRepo *self = luaL_checkudata(L, 1, API_TYPE_GIT_REPO);
  if (self->repo) {
    git_repository_free(self->repo);
    self->repo = NULL;
  }
  return 0;
}


static void shutdown_libgit2(void) { git_libgit2_shutdown(); }


static const luaL_Reg lib[] = { { "open", f_open }, { NULL, NULL } };


static const luaL_Reg repo_lib[] = { { "__gc", f_close }, { "path", f_path },
  { "head", f_head }, { "log", f_log }, { "close", f_close }, { NULL, NULL } };


int luaopen_git(lua_State *L) {
  if (git_libgit2_init() < 0) {
    return luaL_error(L, "could not initialize libgit2");
  }
  atexit(shutdown_libgit2);
  luaL_newmetatable(L, API_TYPE_GIT_REPO);
  luaL_setfuncs(L, repo_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  luaL_newlib(L, lib);
  return 1;
}
