#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
int main(int argc, char **argv) {
    int code = (argc > 1) ? atoi(argv[1]) : 0;
    printf("IA32_HELLO argc=%d code=%d\n", argc, code);
    fflush(stdout);
    return code;
}
