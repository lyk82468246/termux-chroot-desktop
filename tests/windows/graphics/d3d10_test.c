// d3d10_test.c —— 最小 D3D10 测试（窗口 + 设备/交换链 + 三角形 + Present）
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include <initguid.h>
#include <d3d10.h>
#include <dxgi.h>
#include <d3dcompiler.h>

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

static const char *HLSL =
    "struct VSIn { float3 pos : POSITION; float3 col : COLOR; };\n"
    "struct VSOut { float4 pos : SV_POSITION; float3 col : COLOR; };\n"
    "VSOut VSMain(VSIn i) { VSOut o; o.pos = float4(i.pos, 1.0); o.col = i.col; return o; }\n"
    "float4 PSMain(VSOut i) : SV_TARGET { return float4(i.col, 1.0); }\n";

int main(int argc, char **argv) {
    int frames = 10;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"D3D10TestClass";
    RegisterClassW(&wc);
    HWND hwnd = CreateWindowW(L"D3D10TestClass", L"D3D10 test", WS_OVERLAPPEDWINDOW,
                              100, 100, 640, 480, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("D3D10_FAIL stage=window\n"); return 2; }
    ShowWindow(hwnd, SW_SHOW);
    printf("WINDOW_CREATED\n"); fflush(stdout);

    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 1;
    sd.BufferDesc.Width = 640;
    sd.BufferDesc.Height = 480;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    IDXGISwapChain *swap = NULL;
    ID3D10Device *dev = NULL;
    HRESULT hr = D3D10CreateDeviceAndSwapChain(NULL, D3D10_DRIVER_TYPE_HARDWARE, NULL, 0,
                                               D3D10_SDK_VERSION, &sd, &swap, &dev);
    if (FAILED(hr)) { printf("D3D10_FAIL stage=create hr=0x%08lx\n", (unsigned long)hr); return 3; }
    printf("D3D10_DEVICE_CREATED\n"); fflush(stdout);

    ID3D10Texture2D *back = NULL;
    swap->lpVtbl->GetBuffer(swap, 0, &IID_ID3D10Texture2D, (void **)&back);
    ID3D10RenderTargetView *rtv = NULL;
    dev->lpVtbl->CreateRenderTargetView(dev, (ID3D10Resource *)back, NULL, &rtv);
    printf("SWAPCHAIN_CREATED\n"); fflush(stdout);

    ID3D10Blob *vsb = NULL, *psb = NULL, *err = NULL;
    hr = D3DCompile(HLSL, strlen(HLSL), NULL, NULL, NULL, "VSMain", "vs_4_0", 0, 0, &vsb, &err);
    if (FAILED(hr)) { printf("D3D10_FAIL stage=compile_vs\n"); return 4; }
    hr = D3DCompile(HLSL, strlen(HLSL), NULL, NULL, NULL, "PSMain", "ps_4_0", 0, 0, &psb, &err);
    if (FAILED(hr)) { printf("D3D10_FAIL stage=compile_ps\n"); return 4; }
    ID3D10VertexShader *vs = NULL;
    ID3D10PixelShader *ps = NULL;
    dev->lpVtbl->CreateVertexShader(dev, vsb->lpVtbl->GetBufferPointer(vsb), vsb->lpVtbl->GetBufferSize(vsb), &vs);
    dev->lpVtbl->CreatePixelShader(dev, psb->lpVtbl->GetBufferPointer(psb), psb->lpVtbl->GetBufferSize(psb), &ps);

    D3D10_INPUT_ELEMENT_DESC ied[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0},
        {"COLOR",    0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D10_INPUT_PER_VERTEX_DATA, 0},
    };
    ID3D10InputLayout *il = NULL;
    dev->lpVtbl->CreateInputLayout(dev, ied, 2, vsb->lpVtbl->GetBufferPointer(vsb),
                                   vsb->lpVtbl->GetBufferSize(vsb), &il);

    struct V { float x, y, z; float r, g, b; };
    struct V verts[3] = {
        {0.0f, 0.6f, 0.0f, 1.0f, 0.2f, 0.2f},
        {0.6f, -0.5f, 0.0f, 0.2f, 1.0f, 0.2f},
        {-0.6f, -0.5f, 0.0f, 0.2f, 0.2f, 1.0f},
    };
    D3D10_BUFFER_DESC bd = {0};
    bd.ByteWidth = sizeof(verts);
    bd.Usage = D3D10_USAGE_DEFAULT;
    bd.BindFlags = D3D10_BIND_VERTEX_BUFFER;
    D3D10_SUBRESOURCE_DATA srd = {verts, 0, 0};
    ID3D10Buffer *vb = NULL;
    dev->lpVtbl->CreateBuffer(dev, &bd, &srd, &vb);

    for (int f = 0; f < frames; f++) {
        float clear[4] = {0.1f, 0.2f, 0.3f, 1.0f};
        dev->lpVtbl->ClearRenderTargetView(dev, rtv, clear);
        dev->lpVtbl->OMSetRenderTargets(dev, 1, &rtv, NULL);
        D3D10_VIEWPORT vp = {0, 0, 640, 480, 0.0f, 1.0f};
        dev->lpVtbl->RSSetViewports(dev, 1, &vp);
        UINT stride = sizeof(struct V), offset = 0;
        dev->lpVtbl->IASetVertexBuffers(dev, 0, 1, &vb, &stride, &offset);
        dev->lpVtbl->IASetInputLayout(dev, il);
        dev->lpVtbl->IASetPrimitiveTopology(dev, D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        dev->lpVtbl->VSSetShader(dev, vs);
        dev->lpVtbl->PSSetShader(dev, ps);
        dev->lpVtbl->Draw(dev, 3, 0);
        swap->lpVtbl->Present(swap, 1, 0);
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        if (f == 0) { printf("FIRST_FRAME_RENDERED\n"); fflush(stdout); }
    }
    printf("TEST_COMPLETE frames=%d\n", frames); fflush(stdout);
    dev->lpVtbl->Release(dev);
    swap->lpVtbl->Release(swap);
    DestroyWindow(hwnd);
    return 0;
}
