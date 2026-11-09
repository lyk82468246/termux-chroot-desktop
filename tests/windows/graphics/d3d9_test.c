// d3d9_test.c —— 最小 D3D9 测试（窗口 + 清屏 + 三角形 + Present）
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include <d3d9.h>

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

struct V { float x, y, z; DWORD c; };

int main(int argc, char **argv) {
    int frames = 10;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"D3D9TestClass";
    RegisterClassW(&wc);
    HWND hwnd = CreateWindowW(L"D3D9TestClass", L"D3D9 test", WS_OVERLAPPEDWINDOW,
                              100, 100, 640, 480, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("D3D9_FAIL stage=window\n"); return 2; }
    ShowWindow(hwnd, SW_SHOW);
    printf("WINDOW_CREATED\n"); fflush(stdout);

    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    if (!d3d) { printf("D3D9_FAIL stage=create9\n"); return 3; }

    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_UNKNOWN;
    pp.BackBufferWidth = 640;
    pp.BackBufferHeight = 480;
    pp.hDeviceWindow = hwnd;

    IDirect3DDevice9 *dev = NULL;
    HRESULT hr = d3d->lpVtbl->CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd,
                                           D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev);
    if (FAILED(hr)) { printf("D3D9_FAIL stage=createdevice hr=0x%08lx\n", (unsigned long)hr); return 4; }
    printf("D3D9_DEVICE_CREATED\n"); fflush(stdout);
    dev->lpVtbl->SetRenderState(dev, D3DRS_LIGHTING, FALSE);
    dev->lpVtbl->SetRenderState(dev, D3DRS_CULLMODE, D3DCULL_NONE);

    D3DADAPTER_IDENTIFIER9 id;
    if (SUCCEEDED(d3d->lpVtbl->GetAdapterIdentifier(d3d, D3DADAPTER_DEFAULT, 0, &id)))
        printf("D3D9_ADAPTER=%s\n", id.Description);
    fflush(stdout);

    struct V verts[3] = {
        {0.0f, 0.6f, 0.0f, 0xffff0000},
        {0.6f, -0.5f, 0.0f, 0xff00ff00},
        {-0.6f, -0.5f, 0.0f, 0xff0000ff},
    };
    for (int f = 0; f < frames; f++) {
        dev->lpVtbl->Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(25, 50, 75), 1.0f, 0);
        dev->lpVtbl->BeginScene(dev);
        dev->lpVtbl->SetFVF(dev, D3DFVF_XYZ | D3DFVF_DIFFUSE);
        dev->lpVtbl->DrawPrimitiveUP(dev, D3DPT_TRIANGLELIST, 1, verts, sizeof(struct V));
        dev->lpVtbl->EndScene(dev);
        dev->lpVtbl->Present(dev, NULL, NULL, NULL, NULL);
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        if (f == 0) { printf("FIRST_FRAME_RENDERED\n"); fflush(stdout); }
    }
    printf("TEST_COMPLETE frames=%d\n", frames); fflush(stdout);
    dev->lpVtbl->Release(dev);
    d3d->lpVtbl->Release(d3d);
    DestroyWindow(hwnd);
    return 0;
}
