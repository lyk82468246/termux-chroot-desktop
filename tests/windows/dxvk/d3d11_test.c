// d3d11_test.c —— 最小 D3D11 测试程序（Windows PE，x64/x86 均可编译）
// 阶段日志：WINDOW_CREATED / D3D11_DEVICE_CREATED / SWAPCHAIN_CREATED /
//           FIRST_FRAME_RENDERED / TEST_COMPLETE / D3D11_FAIL
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <initguid.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3dcompiler.h>

static int g_frames = 60;
static int g_fail = 0;
static HWND g_hwnd;

static void fail(const char *stage, HRESULT hr) {
    printf("D3D11_FAIL stage=%s hr=0x%08lx\n", stage, (unsigned long)hr);
    fflush(stdout);
    g_fail = 1;
}

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
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--frames") && i + 1 < argc) g_frames = atoi(argv[++i]);
    }

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = L"D3D11TestClass";
    RegisterClassW(&wc);
    g_hwnd = CreateWindowW(L"D3D11TestClass", L"D3D11 test", WS_OVERLAPPEDWINDOW,
                           100, 100, 640, 480, NULL, NULL, wc.hInstance, NULL);
    if (!g_hwnd) { printf("D3D11_FAIL stage=window\n"); return 2; }
    ShowWindow(g_hwnd, SW_SHOW);
    printf("WINDOW_CREATED\n"); fflush(stdout);

    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 2;
    sd.BufferDesc.Width = 640;
    sd.BufferDesc.Height = 480;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = g_hwnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    D3D_FEATURE_LEVEL fl;
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    IDXGISwapChain *sc = NULL;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
        D3D11_SDK_VERSION, &sd, &sc, &dev, &fl, &ctx);
    if (FAILED(hr)) { fail("d3d11_create", hr); return 3; }
    printf("D3D11_DEVICE_CREATED feature_level=0x%x\n", (unsigned)fl);
    printf("SWAPCHAIN_CREATED\n"); fflush(stdout);

    IDXGIDevice *dxdev = NULL;
    IDXGIAdapter *adapter = NULL;
    if (SUCCEEDED(dev->lpVtbl->QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxdev))) {
        if (SUCCEEDED(dxdev->lpVtbl->GetAdapter(dxdev, &adapter))) {
            DXGI_ADAPTER_DESC ad;
            if (SUCCEEDED(adapter->lpVtbl->GetDesc(adapter, &ad))) {
                char name[256] = {0};
                WideCharToMultiByte(CP_UTF8, 0, ad.Description, -1, name, sizeof(name), NULL, NULL);
                printf("GPU_ADAPTER=%s vendor=0x%x\n", name, ad.VendorId);
                fflush(stdout);
            }
            adapter->lpVtbl->Release(adapter);
        }
        dxdev->lpVtbl->Release(dxdev);
    }

    ID3D11Texture2D *backbuf = NULL;
    ID3D11RenderTargetView *rtv = NULL;
    hr = sc->lpVtbl->GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&backbuf);
    if (FAILED(hr)) { fail("get_buffer", hr); return 4; }
    hr = dev->lpVtbl->CreateRenderTargetView(dev, (ID3D11Resource *)backbuf, NULL, &rtv);
    if (FAILED(hr)) { fail("create_rtv", hr); return 4; }

    ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
    hr = D3DCompile(HLSL, strlen(HLSL), NULL, NULL, NULL, "VSMain", "vs_4_0", 0, 0, &vsb, &err);
    if (FAILED(hr)) { fail("compile_vs", hr); return 5; }
    hr = D3DCompile(HLSL, strlen(HLSL), NULL, NULL, NULL, "PSMain", "ps_4_0", 0, 0, &psb, &err);
    if (FAILED(hr)) { fail("compile_ps", hr); return 5; }

    ID3D11VertexShader *vs = NULL;
    ID3D11PixelShader *ps = NULL;
    dev->lpVtbl->CreateVertexShader(dev, vsb->lpVtbl->GetBufferPointer(vsb), vsb->lpVtbl->GetBufferSize(vsb), NULL, &vs);
    dev->lpVtbl->CreatePixelShader(dev, psb->lpVtbl->GetBufferPointer(psb), psb->lpVtbl->GetBufferSize(psb), NULL, &ps);

    D3D11_INPUT_ELEMENT_DESC ied[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"COLOR",    0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0},
    };
    ID3D11InputLayout *il = NULL;
    dev->lpVtbl->CreateInputLayout(dev, ied, 2, vsb->lpVtbl->GetBufferPointer(vsb), vsb->lpVtbl->GetBufferSize(vsb), &il);

    struct V { float x, y, z; float r, g, b; };
    struct V verts[3] = {
        {0.0f,  0.6f, 0.0f, 1.0f, 0.2f, 0.2f},
        {0.6f, -0.5f, 0.0f, 0.2f, 1.0f, 0.2f},
        {-0.6f,-0.5f, 0.0f, 0.2f, 0.2f, 1.0f},
    };
    D3D11_BUFFER_DESC bd = {0};
    bd.ByteWidth = sizeof(verts);
    bd.Usage = D3D11_USAGE_DEFAULT;
    bd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    D3D11_SUBRESOURCE_DATA srd = {verts, 0, 0};
    ID3D11Buffer *vb = NULL;
    dev->lpVtbl->CreateBuffer(dev, &bd, &srd, &vb);

    ctx->lpVtbl->OMSetRenderTargets(ctx, 1, &rtv, NULL);
    D3D11_VIEWPORT vp = {0, 0, 640, 480, 0, 1};
    ctx->lpVtbl->RSSetViewports(ctx, 1, &vp);

    for (int f = 0; f < g_frames; f++) {
        float clear[4] = {0.1f, 0.2f, 0.3f, 1.0f};
        ctx->lpVtbl->ClearRenderTargetView(ctx, rtv, clear);
        UINT stride = sizeof(struct V), offset = 0;
        ctx->lpVtbl->IASetVertexBuffers(ctx, 0, 1, &vb, &stride, &offset);
        ctx->lpVtbl->IASetInputLayout(ctx, il);
        ctx->lpVtbl->IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        ctx->lpVtbl->VSSetShader(ctx, vs, NULL, 0);
        ctx->lpVtbl->PSSetShader(ctx, ps, NULL, 0);
        ctx->lpVtbl->Draw(ctx, 3, 0);
        sc->lpVtbl->Present(sc, 1, 0);
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        if (f == 0) { printf("FIRST_FRAME_RENDERED\n"); fflush(stdout); }
    }

    printf("TEST_COMPLETE frames=%d\n", g_frames);
    fflush(stdout);
    if (rtv) rtv->lpVtbl->Release(rtv);
    if (backbuf) backbuf->lpVtbl->Release(backbuf);
    if (dev) dev->lpVtbl->Release(dev);
    if (sc) sc->lpVtbl->Release(sc);
    if (ctx) ctx->lpVtbl->Release(ctx);
    DestroyWindow(g_hwnd);
    return g_fail ? 1 : 0;
}
