#include <stdio.h>
#include <windows.h>
int main(void) {
    const char *p = "Z:\\tmp\\win-tests\\ia32-file.txt";
    FILE *f = fopen(p, "w");
    if (!f) { printf("FILE_WRITE_FAIL\n"); return 4; }
    fprintf(f, "ia32 file test\n");
    fclose(f);
    f = fopen(p, "r");
    if (!f) { printf("FILE_READ_FAIL\n"); return 5; }
    char b[64] = {0};
    fgets(b, sizeof(b), f);
    fclose(f);
    printf("IA32_FILE_OK <%s>\n", b);
    return 0;
}
