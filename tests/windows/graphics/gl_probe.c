// gl_probe.c ?? ?? Wine ? OpenGL ??? renderer?Windows PE?
#include <stdio.h>
#include <windows.h>
#include <GL/gl.h>

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

int main(void) {
    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"GlProbeClass";
    RegisterClassW(&wc);
    HWND h = CreateWindowW(L"GlProbeClass", L"gl probe", WS_OVERLAPPEDWINDOW,
                           0, 0, 64, 64, NULL, NULL, wc.hInstance, NULL);
    if (!h) { printf("GL_FAIL window\n"); return 2; }
    HDC dc = GetDC(h);
    PIXELFORMATDESCRIPTOR pfd = {0};
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    int pf = ChoosePixelFormat(dc, &pfd);
    if (!pf || !SetPixelFormat(dc, pf, &pfd)) { printf("GL_FAIL pixelformat\n"); return 3; }
    HGLRC rc = wglCreateContext(dc);
    if (!rc || !wglMakeCurrent(dc, rc)) { printf("GL_FAIL context\n"); return 4; }
    const char *vendor = (const char *)glGetString(GL_VENDOR);
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *version = (const char *)glGetString(GL_VERSION);
    printf("GL_VENDOR=%s\n", vendor ? vendor : "?");
    printf("GL_RENDERER=%s\n", renderer ? renderer : "?");
    printf("GL_VERSION=%s\n", version ? version : "?");
    fflush(stdout);
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(rc);
    return 0;
}
