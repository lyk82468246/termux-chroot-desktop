#include <stdio.h>
#include <windows.h>

static LRESULT CALLBACK MyProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_NCCREATE) return TRUE;
    if (m == WM_CREATE) return 0;
    return DefWindowProcW(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE hi, HINSTANCE hp, LPSTR cmd, int show) {
    HWND h1 = CreateWindowExW(0, L"STATIC", L"probe", WS_OVERLAPPEDWINDOW,
                              0, 0, 200, 100, NULL, NULL, hi, NULL);
    printf("STATIC=%p err=%lu\n", (void*)h1, GetLastError()); fflush(stdout);

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = hi;
    wc.lpszClassName = L"ProbeDefClass";
    printf("REG_DEF=%d\n", RegisterClassW(&wc)); fflush(stdout);
    HWND h2 = CreateWindowW(L"ProbeDefClass", L"probe2", WS_OVERLAPPEDWINDOW,
                            0, 0, 200, 100, NULL, NULL, hi, NULL);
    printf("CUSTOM_DEFPROC=%p err=%lu\n", (void*)h2, GetLastError()); fflush(stdout);

    WNDCLASSW wc2 = {0};
    wc2.lpfnWndProc = MyProc;
    wc2.hInstance = hi;
    wc2.lpszClassName = L"ProbeMyClass";
    printf("REG_MY=%d\n", RegisterClassW(&wc2)); fflush(stdout);
    HWND h3 = CreateWindowW(L"ProbeMyClass", L"probe3", WS_OVERLAPPEDWINDOW,
                            0, 0, 200, 100, NULL, NULL, hi, NULL);
    printf("CUSTOM_MYPROC=%p err=%lu\n", (void*)h3, GetLastError()); fflush(stdout);

    printf("MSGBOX=%d\n", MessageBoxA(NULL, "hello", "probe", MB_OK)); fflush(stdout);
    return 0;
}
