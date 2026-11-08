#include <stdio.h>
#include <windows.h>

static void emit(const char *tag, int idx, const wchar_t *w) {
    char utf8[1024] = {0};
    WideCharToMultiByte(CP_UTF8, 0, w, -1, utf8, sizeof(utf8), NULL, NULL);
    printf("%s[%d]=<%s>\n", tag, idx, utf8);
    FILE *f = fopen(getenv("WIN_ARGS_RESULT") ? getenv("WIN_ARGS_RESULT") : "C:\\args-result.txt", "a");
    if (f) { fprintf(f, "%s[%d]=<%s>\n", tag, idx, utf8); fclose(f); }
}

int wmain(int argc, wchar_t **argv) {
    printf("ARGC=%d\n", argc);
    for (int i = 1; i < argc; i++) emit("ARGV", i, argv[i]);
    printf("EXE=<%ls>\n", argv[0]);
    fflush(stdout);
    return 7;
}
