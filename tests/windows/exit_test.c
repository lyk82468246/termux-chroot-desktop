#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    int code = (argc > 1) ? atoi(argv[1]) : 0;
    printf("EXIT_TEST code=%d\n", code);
    fflush(stdout);
    return code;
}
