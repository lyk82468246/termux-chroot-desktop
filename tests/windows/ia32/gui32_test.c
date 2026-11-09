#include <stdio.h>
#include <string.h>
#include <windows.h>

static HWND hEdit, hButton;
static char g_result[MAX_PATH];

static void write_result(const char *text) {
    FILE *f = fopen(g_result, "w");
    if (f) { fprintf(f, "%s\n", text); fclose(f); }
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_NCCREATE:
        return TRUE;
    case WM_CREATE:
        return 0;
    case WM_COMMAND:
        if (LOWORD(wp) == 1002) {
            wchar_t buf[256] = {0};
            GetWindowTextW(hEdit, buf, 255);
            char utf8[512] = {0};
            WideCharToMultiByte(CP_UTF8, 0, buf, -1, utf8, sizeof(utf8), NULL, NULL);
            printf("GUI_BUTTON text=%s\n", utf8); fflush(stdout);
            write_result(utf8);
            PostQuitMessage(0);
        }
        return 0;
    case WM_TIMER:
        KillTimer(hwnd, 1);
        printf("GUI_AUTO_CLICK\n"); fflush(stdout);
        SendMessageW(hButton, BM_CLICK, 0, 0);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR cmd, int show) {
    const char *res = getenv("WIN_GUI_RESULT");
    snprintf(g_result, sizeof(g_result), "%s", res ? res : "C:\\gui-result.txt");

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = L"Gui32TestClass";
    if (!RegisterClassW(&wc)) { printf("GUI_FAIL register\n"); return 9; }

    HWND hwnd = CreateWindowW(L"Gui32TestClass", L"ia32 GUI test", WS_OVERLAPPEDWINDOW,
                              100, 100, 480, 220, NULL, NULL, hInst, NULL);
    if (!hwnd) { printf("GUI_FAIL create err=%lu\n", GetLastError()); return 9; }

    hEdit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"hello ia32 gui",
                            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                            20, 20, 420, 28, hwnd, (HMENU)1001, hInst, NULL);
    hButton = CreateWindowW(L"BUTTON", L"OK", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                            20, 60, 100, 32, hwnd, (HMENU)1002, hInst, NULL);
    CreateWindowW(L"STATIC", L"type something and press OK", WS_CHILD | WS_VISIBLE,
                  20, 110, 420, 24, hwnd, NULL, hInst, NULL);

    const wchar_t *cl = GetCommandLineW();
    if (!wcsstr(cl, L"--stay")) {
        UINT ms = 4000;
        const wchar_t *a = wcsstr(cl, L"--exit-after");
        if (a) { ms = (UINT)wcstoul(a + 12, NULL, 10); if (!ms) ms = 4000; }
        SetTimer(hwnd, 1, ms, NULL);
    }

    ShowWindow(hwnd, show);
    UpdateWindow(hwnd);
    printf("GUI_READY\n"); fflush(stdout);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    printf("GUI_EXIT %d\n", (int)msg.wParam); fflush(stdout);
    return (int)msg.wParam;
}
