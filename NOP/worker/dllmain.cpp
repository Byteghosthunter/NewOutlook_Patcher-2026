#include <wrl.h>
#include <wil/com.h>
#include <Windows.h>
#include <commctrl.h>
#include <cstdarg>
#include <string>
#include "WebView2.h"
#include "WebView2EnvironmentOptions.h"
#include "MinHook.h"

#pragma comment(lib, "libMinHook.x64.lib")

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

static volatile LONG g_webViewHookState = 0; // 0=not installed, 1=installing, 2=installed

static std::wstring GetLogPath()
{
    wchar_t localAppData[32768] = {};
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, ARRAYSIZE(localAppData));
    if (n == 0 || n >= ARRAYSIZE(localAppData))
        return L"";

    std::wstring dir = std::wstring(localAppData) + L"\\NewOutlookAdBlocker";
    CreateDirectoryW(dir.c_str(), nullptr);
    return dir + L"\\NewOutlookPatcher-NOAB.log";
}

static void LogPrintf(LPCWSTR fmt, ...)
{
    static thread_local bool insideLogger = false;
    if (insideLogger)
        return;

    insideLogger = true;

    wchar_t message[2048] = {};
    va_list args;
    va_start(args, fmt);
    _vsnwprintf_s(message, ARRAYSIZE(message), _TRUNCATE, fmt, args);
    va_end(args);

    OutputDebugStringW(message);
    OutputDebugStringW(L"\r\n");

    std::wstring logPath = GetLogPath();
    if (!logPath.empty())
    {
        HANDLE h = CreateFileW(
            logPath.c_str(),
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr
        );

        if (h != INVALID_HANDLE_VALUE)
        {
            SYSTEMTIME st{};
            GetLocalTime(&st);

            wchar_t line[2300] = {};
            _snwprintf_s(
                line,
                ARRAYSIZE(line),
                _TRUNCATE,
                L"[%04u-%02u-%02u %02u:%02u:%02u.%03u] [PID %lu TID %lu] %s\r\n",
                st.wYear, st.wMonth, st.wDay,
                st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                GetCurrentProcessId(), GetCurrentThreadId(),
                message
            );

            DWORD bytes = 0;
            WriteFile(h, line, static_cast<DWORD>(wcslen(line) * sizeof(wchar_t)), &bytes, nullptr);
            CloseHandle(h);
        }
    }

    insideLogger = false;
}

static const wchar_t* kNoabScript = LR"NOABJS(
(() => {
    const premiumSelector = "[data-message-ad-id^='MessageAdKeyOutlookUpSell']";

    const styleId = "NewOutlookPatcherNOABStyle";
    let styleElement = document.getElementById(styleId);
    if (!styleElement) {
        styleElement = document.createElement("style");
        styleElement.id = styleId;
        (document.head || document.documentElement).appendChild(styleElement);
    }

    styleElement.textContent = `
#OwaContainer,
#OwaContainerSlot1,
.kk1xx._Bfyd.iIsOF.IjQyD,
.kk1xx.lHRXq.IjQyD,
.syTot,
[id='34318026-c018-414b-abb3-3e32dfb9cc4c'],
[id='c5251a9b-a95d-4595-91ee-a39e6eed3db2'],
[id='48cb9ead-1c19-4e1f-8ed9-3d60a7e52b18'],
[id='59391057-d7d7-49fd-a041-d8e4080f05ec'],
[id='39109bd4-9389-4731-b8d6-7cc1a128d0b3'],
.___1fkhojs.f22iagw.f122n59.f1vx9l62.f1c21dwh.fqerorx.f1i5mqs4,
[id='D64D0004-2A11-442B-9586-F49009D4852B'],
[data-message-ad-id^='MessageAdKeyOutlookUpSell'] {
    display: none !important;
}`;

    const hidePremium = () => {
        const nodes = document.querySelectorAll(premiumSelector);
        nodes.forEach((el) => {
            el.style.setProperty("display", "none", "important");
        });
        return nodes.length;
    };

    const initialCount = hidePremium();

    if (!window.__NewOutlookPatcherNOABPremiumObserver) {
        window.__NewOutlookPatcherNOABPremiumObserver = new MutationObserver(() => {
            hidePremium();
        });

        if (document.documentElement) {
            window.__NewOutlookPatcherNOABPremiumObserver.observe(
                document.documentElement,
                { childList: true, subtree: true }
            );
        }
    }

    return initialCount;
})()
)NOABJS";

static void LogWebViewSource(ICoreWebView2* webview, LPCWSTR stage)
{
    if (!webview)
        return;

    LPWSTR source = nullptr;
    HRESULT hr = webview->get_Source(&source);
    if (SUCCEEDED(hr) && source)
    {
        LogPrintf(L"NOAB: %s source=%s", stage, source);
        CoTaskMemFree(source);
    }
    else
    {
        LogPrintf(L"NOAB: %s get_Source failed hr=0x%08X", stage, hr);
    }
}

static void ExecuteNoabScript(ICoreWebView2* webview, LPCWSTR reason)
{
    if (!webview)
        return;

    LogWebViewSource(webview, reason);

    HRESULT hr = webview->ExecuteScript(
        kNoabScript,
        Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
            [reason](HRESULT errorCode, LPCWSTR resultObjectAsJson) -> HRESULT
            {
                LogPrintf(
                    L"NOAB: ExecuteScript(%s) completed hr=0x%08X result=%s",
                    reason,
                    errorCode,
                    resultObjectAsJson ? resultObjectAsJson : L"(null)"
                );
                return S_OK;
            }
        ).Get()
    );

    LogPrintf(L"NOAB: ExecuteScript(%s) submitted hr=0x%08X", reason, hr);
}

static void RegisterNoabScript(ICoreWebView2* webview)
{
    if (!webview)
        return;

    HRESULT hr = webview->AddScriptToExecuteOnDocumentCreated(
        kNoabScript,
        Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
            [](HRESULT errorCode, LPCWSTR id) -> HRESULT
            {
                LogPrintf(
                    L"NOAB: AddScriptToExecuteOnDocumentCreated completed hr=0x%08X id=%s",
                    errorCode,
                    id ? id : L"(null)"
                );
                return S_OK;
            }
        ).Get()
    );

    LogPrintf(L"NOAB: AddScriptToExecuteOnDocumentCreated submitted hr=0x%08X", hr);

    // Also run once immediately for an already-created document.
    ExecuteNoabScript(webview, L"ControllerCompleted/immediate");

    EventRegistrationToken navigationToken{};
    hr = webview->add_NavigationCompleted(
        Callback<ICoreWebView2NavigationCompletedEventHandler>(
            [](ICoreWebView2* sender, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT
            {
                BOOL success = FALSE;
                HRESULT navHr = args ? args->get_IsSuccess(&success) : E_POINTER;
                LogPrintf(
                    L"NOAB: NavigationCompleted event navHr=0x%08X success=%d",
                    navHr,
                    success ? 1 : 0
                );
                ExecuteNoabScript(sender, L"NavigationCompleted");
                return S_OK;
            }
        ).Get(),
        &navigationToken
    );

    LogPrintf(L"NOAB: add_NavigationCompleted hr=0x%08X", hr);
}

template <typename T>
static bool PatchVtableEntry(
    void** vtable,
    size_t index,
    void* detour,
    T* original,
    LPCWSTR name)
{
    if (!vtable || !original)
        return false;

    if (vtable[index] == detour)
    {
        LogPrintf(L"NOAB: %s already patched", name);
        return true;
    }

    DWORD oldProtect = 0;
    if (!VirtualProtect(&vtable[index], sizeof(void*), PAGE_EXECUTE_READWRITE, &oldProtect))
    {
        LogPrintf(L"NOAB: VirtualProtect failed for %s error=%lu", name, GetLastError());
        return false;
    }

    *original = reinterpret_cast<T>(vtable[index]);
    vtable[index] = detour;

    DWORD ignored = 0;
    VirtualProtect(&vtable[index], sizeof(void*), oldProtect, &ignored);
    FlushInstructionCache(GetCurrentProcess(), &vtable[index], sizeof(void*));

    LogPrintf(L"NOAB: patched %s original=%p detour=%p", name, reinterpret_cast<void*>(*original), detour);
    return true;
}

HRESULT(*g_originalControllerCompletedInvoke)(
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler*,
    HRESULT,
    ICoreWebView2Controller*) = nullptr;

HRESULT STDMETHODCALLTYPE HookControllerCompletedInvoke(
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler* self,
    HRESULT errorCode,
    ICoreWebView2Controller* createdController)
{
    LogPrintf(
        L"NOAB: ControllerCompleted intercepted hr=0x%08X controller=%p",
        errorCode,
        createdController
    );

    if (createdController)
    {
        ComPtr<ICoreWebView2> webview;
        HRESULT hr = createdController->get_CoreWebView2(webview.GetAddressOf());
        LogPrintf(L"NOAB: get_CoreWebView2 hr=0x%08X webview=%p", hr, webview.Get());

        if (SUCCEEDED(hr) && webview)
        {
            RegisterNoabScript(webview.Get());

            const wchar_t* isF12Enabled = L"y_1A36CD25-E20F-4D0D-B1E6-3CC4307E1488";
            if (isF12Enabled[0] == L'y')
            {
                EventRegistrationToken keyToken{};
                HRESULT keyHr = createdController->add_AcceleratorKeyPressed(
                    Callback<ICoreWebView2AcceleratorKeyPressedEventHandler>(
                        [](ICoreWebView2Controller* sender, ICoreWebView2AcceleratorKeyPressedEventArgs* args) -> HRESULT
                        {
                            COREWEBVIEW2_KEY_EVENT_KIND kind{};
                            if (FAILED(args->get_KeyEventKind(&kind)))
                                return S_OK;

                            if (kind == COREWEBVIEW2_KEY_EVENT_KIND_KEY_UP)
                            {
                                UINT key = 0;
                                if (SUCCEEDED(args->get_VirtualKey(&key)) && key == VK_F12)
                                {
                                    args->put_Handled(TRUE);
                                    ComPtr<ICoreWebView2> wv;
                                    if (SUCCEEDED(sender->get_CoreWebView2(wv.GetAddressOf())) && wv)
                                        wv->OpenDevToolsWindow();
                                }
                            }
                            return S_OK;
                        }
                    ).Get(),
                    &keyToken
                );
                LogPrintf(L"NOAB: add_AcceleratorKeyPressed hr=0x%08X", keyHr);
            }
        }
    }

    if (g_originalControllerCompletedInvoke)
        return g_originalControllerCompletedInvoke(self, errorCode, createdController);

    LogPrintf(L"NOAB: original ControllerCompleted callback missing");
    return S_OK;
}

HRESULT(*g_originalCreateController)(
    ICoreWebView2Environment*,
    HWND,
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler*) = nullptr;

HRESULT STDMETHODCALLTYPE HookCreateController(
    ICoreWebView2Environment* self,
    HWND parentWindow,
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler* controllerCompletedHandler)
{
    LogPrintf(
        L"NOAB: CreateCoreWebView2Controller intercepted env=%p hwnd=%p callback=%p",
        self,
        parentWindow,
        controllerCompletedHandler
    );

    if (controllerCompletedHandler)
    {
        void** callbackVtable = *reinterpret_cast<void***>(controllerCompletedHandler);
        PatchVtableEntry(
            callbackVtable,
            3,
            reinterpret_cast<void*>(&HookControllerCompletedInvoke),
            &g_originalControllerCompletedInvoke,
            L"ControllerCompleted::Invoke"
        );
    }

    if (g_originalCreateController)
        return g_originalCreateController(self, parentWindow, controllerCompletedHandler);

    LogPrintf(L"NOAB: original CreateCoreWebView2Controller missing");
    return E_FAIL;
}

HRESULT(*g_originalEnvironmentCompletedInvoke)(
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler*,
    HRESULT,
    ICoreWebView2Environment*) = nullptr;

HRESULT STDMETHODCALLTYPE HookEnvironmentCompletedInvoke(
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler* self,
    HRESULT errorCode,
    ICoreWebView2Environment* createdEnvironment)
{
    LogPrintf(
        L"NOAB: EnvironmentCompleted intercepted hr=0x%08X env=%p",
        errorCode,
        createdEnvironment
    );

    if (createdEnvironment)
    {
        void** envVtable = *reinterpret_cast<void***>(createdEnvironment);
        PatchVtableEntry(
            envVtable,
            3,
            reinterpret_cast<void*>(&HookCreateController),
            &g_originalCreateController,
            L"ICoreWebView2Environment::CreateCoreWebView2Controller"
        );

        ComPtr<ICoreWebView2Environment3> env3;
        HRESULT hr3 = createdEnvironment->QueryInterface(IID_PPV_ARGS(env3.GetAddressOf()));
        LogPrintf(L"NOAB: QueryInterface ICoreWebView2Environment3 hr=0x%08X supported=%d", hr3, SUCCEEDED(hr3) && env3 ? 1 : 0);

        ComPtr<ICoreWebView2Environment10> env10;
        HRESULT hr10 = createdEnvironment->QueryInterface(IID_PPV_ARGS(env10.GetAddressOf()));
        LogPrintf(L"NOAB: QueryInterface ICoreWebView2Environment10 hr=0x%08X supported=%d", hr10, SUCCEEDED(hr10) && env10 ? 1 : 0);

        if (SUCCEEDED(hr10) && env10)
        {
            LogPrintf(L"NOAB: Environment10 exists; Outlook may use CreateCoreWebView2ControllerWithOptions. This trace build does not patch that method yet.");
        }
    }

    if (g_originalEnvironmentCompletedInvoke)
        return g_originalEnvironmentCompletedInvoke(self, errorCode, createdEnvironment);

    LogPrintf(L"NOAB: original EnvironmentCompleted callback missing");
    return S_OK;
}

typedef HRESULT(WINAPI* PFN_CreateCoreWebView2EnvironmentWithOptions)(
    PCWSTR,
    PCWSTR,
    ICoreWebView2EnvironmentOptions*,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler*
);

static PFN_CreateCoreWebView2EnvironmentWithOptions g_originalCreateEnvironment = nullptr;

STDAPI HookCreateCoreWebView2EnvironmentWithOptions(
    PCWSTR browserExecutableFolder,
    PCWSTR userDataFolder,
    ICoreWebView2EnvironmentOptions* environmentOptions,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler* environmentCreatedHandler)
{
    LogPrintf(
        L"NOAB: CreateCoreWebView2EnvironmentWithOptions intercepted browser=%s userdata=%s callback=%p",
        browserExecutableFolder ? browserExecutableFolder : L"(default)",
        userDataFolder ? userDataFolder : L"(default)",
        environmentCreatedHandler
    );

    if (environmentCreatedHandler)
    {
        void** callbackVtable = *reinterpret_cast<void***>(environmentCreatedHandler);
        PatchVtableEntry(
            callbackVtable,
            3,
            reinterpret_cast<void*>(&HookEnvironmentCompletedInvoke),
            &g_originalEnvironmentCompletedInvoke,
            L"EnvironmentCompleted::Invoke"
        );
    }

    if (!g_originalCreateEnvironment)
    {
        LogPrintf(L"NOAB: original CreateCoreWebView2EnvironmentWithOptions trampoline missing");
        return E_FAIL;
    }

    return g_originalCreateEnvironment(
        browserExecutableFolder,
        userDataFolder,
        environmentOptions,
        environmentCreatedHandler
    );
}

static void TryInstallWebView2Hook()
{
    if (InterlockedCompareExchange(&g_webViewHookState, 1, 0) != 0)
        return;

    HMODULE loader = GetModuleHandleW(L"WebView2Loader.dll");
    if (!loader)
    {
        InterlockedExchange(&g_webViewHookState, 0);
        return;
    }

    FARPROC target = GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions");
    if (!target)
    {
        LogPrintf(L"NOAB: WebView2Loader.dll present but CreateCoreWebView2EnvironmentWithOptions export not found");
        InterlockedExchange(&g_webViewHookState, 0);
        return;
    }

    LogPrintf(L"NOAB: WebView2Loader detected at %p, target=%p", loader, target);

    MH_STATUS status = MH_Initialize();
    if (status != MH_OK && status != MH_ERROR_ALREADY_INITIALIZED)
    {
        LogPrintf(L"NOAB: MH_Initialize failed status=%d", status);
        InterlockedExchange(&g_webViewHookState, 0);
        return;
    }

    status = MH_CreateHook(
        reinterpret_cast<LPVOID>(target),
        reinterpret_cast<LPVOID>(&HookCreateCoreWebView2EnvironmentWithOptions),
        reinterpret_cast<LPVOID*>(&g_originalCreateEnvironment)
    );

    if (status != MH_OK && status != MH_ERROR_ALREADY_CREATED)
    {
        LogPrintf(L"NOAB: MH_CreateHook failed status=%d", status);
        InterlockedExchange(&g_webViewHookState, 0);
        return;
    }

    status = MH_EnableHook(reinterpret_cast<LPVOID>(target));
    if (status != MH_OK && status != MH_ERROR_ENABLED)
    {
        LogPrintf(L"NOAB: MH_EnableHook failed status=%d", status);
        InterlockedExchange(&g_webViewHookState, 0);
        return;
    }

    InterlockedExchange(&g_webViewHookState, 2);
    LogPrintf(L"NOAB: WebView2 MinHook enabled successfully");
}

// ---- AppVerifier infrastructure ----

#define DLL_PROCESS_VERIFIER 4

typedef struct _RTL_VERIFIER_THUNK_DESCRIPTOR {
    PCHAR ThunkName;
    PVOID ThunkOldAddress;
    PVOID ThunkNewAddress;
} RTL_VERIFIER_THUNK_DESCRIPTOR, *PRTL_VERIFIER_THUNK_DESCRIPTOR;

typedef struct _RTL_VERIFIER_DLL_DESCRIPTOR {
    PWCHAR DllName;
    ULONG DllFlags;
    PVOID DllAddress;
    PRTL_VERIFIER_THUNK_DESCRIPTOR DllThunks;
} RTL_VERIFIER_DLL_DESCRIPTOR, *PRTL_VERIFIER_DLL_DESCRIPTOR;

typedef void (NTAPI* RTL_VERIFIER_DLL_LOAD_CALLBACK)(
    PWSTR DllName,
    PVOID DllBase,
    SIZE_T DllSize,
    PVOID Reserved);

typedef void (NTAPI* RTL_VERIFIER_DLL_UNLOAD_CALLBACK)(
    PWSTR DllName,
    PVOID DllBase,
    SIZE_T DllSize,
    PVOID Reserved);

typedef void (NTAPI* RTL_VERIFIER_NTDLLHEAPFREE_CALLBACK)(
    PVOID AllocationBase,
    SIZE_T AllocationSize);

typedef struct _RTL_VERIFIER_PROVIDER_DESCRIPTOR {
    ULONG Length;
    PRTL_VERIFIER_DLL_DESCRIPTOR ProviderDlls;
    RTL_VERIFIER_DLL_LOAD_CALLBACK ProviderDllLoadCallback;
    RTL_VERIFIER_DLL_UNLOAD_CALLBACK ProviderDllUnloadCallback;
    PWSTR VerifierImage;
    ULONG VerifierFlags;
    ULONG VerifierDebug;
    PVOID RtlpGetStackTraceAddress;
    PVOID RtlpDebugPageHeapCreate;
    PVOID RtlpDebugPageHeapDestroy;
    RTL_VERIFIER_NTDLLHEAPFREE_CALLBACK ProviderNtdllHeapFreeCallback;
} RTL_VERIFIER_PROVIDER_DESCRIPTOR;

HMODULE WINAPI HookLoadLibraryExW(LPCWSTR lpLibFileName, HANDLE hFile, DWORD dwFlags);
HMODULE WINAPI HookLoadLibraryW(LPCWSTR lpLibFileName);

static RTL_VERIFIER_THUNK_DESCRIPTOR kernelbaseHooks[] =
{
    { (PCHAR)"LoadLibraryExW", nullptr, reinterpret_cast<PVOID>(HookLoadLibraryExW) },
    { (PCHAR)"LoadLibraryW",   nullptr, reinterpret_cast<PVOID>(HookLoadLibraryW) },
    { nullptr, nullptr, nullptr },
};

static RTL_VERIFIER_DLL_DESCRIPTOR verifierDlls[] =
{
    { (PWCHAR)L"kernelbase.dll", 0, nullptr, kernelbaseHooks },
    { nullptr, 0, nullptr, nullptr },
};

static RTL_VERIFIER_PROVIDER_DESCRIPTOR verifierDescriptor =
{
    sizeof(verifierDescriptor),
    verifierDlls,
    [](auto, auto, auto, auto) {},
    [](auto, auto, auto, auto) {},
    nullptr, 0, 0,
    nullptr, nullptr, nullptr,
    [](auto, auto) {},
};

typedef HMODULE(WINAPI* PFN_LoadLibraryExW)(LPCWSTR, HANDLE, DWORD);
typedef HMODULE(WINAPI* PFN_LoadLibraryW)(LPCWSTR);

static PFN_LoadLibraryExW GetOriginalLoadLibraryExW()
{
    auto fn = reinterpret_cast<PFN_LoadLibraryExW>(kernelbaseHooks[0].ThunkOldAddress);
    if (!fn)
    {
        HMODULE kb = GetModuleHandleW(L"kernelbase.dll");
        fn = reinterpret_cast<PFN_LoadLibraryExW>(kb ? GetProcAddress(kb, "LoadLibraryExW") : nullptr);
    }
    return fn;
}

static PFN_LoadLibraryW GetOriginalLoadLibraryW()
{
    auto fn = reinterpret_cast<PFN_LoadLibraryW>(kernelbaseHooks[1].ThunkOldAddress);
    if (!fn)
    {
        HMODULE kb = GetModuleHandleW(L"kernelbase.dll");
        fn = reinterpret_cast<PFN_LoadLibraryW>(kb ? GetProcAddress(kb, "LoadLibraryW") : nullptr);
    }
    return fn;
}

HMODULE WINAPI HookLoadLibraryExW(LPCWSTR lpLibFileName, HANDLE hFile, DWORD dwFlags)
{
    PFN_LoadLibraryExW original = GetOriginalLoadLibraryExW();
    if (!original)
        return nullptr;

    HMODULE result = original(lpLibFileName, hFile, dwFlags);

    if (lpLibFileName &&
        (wcsstr(lpLibFileName, L"WebView2") || wcsstr(lpLibFileName, L"uxtheme")))
    {
        LogPrintf(L"NOAB: LoadLibraryExW(%s) -> %p", lpLibFileName, result);
    }

    TryInstallWebView2Hook();
    return result;
}

HMODULE WINAPI HookLoadLibraryW(LPCWSTR lpLibFileName)
{
    PFN_LoadLibraryW original = GetOriginalLoadLibraryW();
    if (!original)
        return nullptr;

    HMODULE result = original(lpLibFileName);

    if (lpLibFileName &&
        (wcsstr(lpLibFileName, L"WebView2") || wcsstr(lpLibFileName, L"uxtheme")))
    {
        LogPrintf(L"NOAB: LoadLibraryW(%s) -> %p", lpLibFileName, result);
    }

    TryInstallWebView2Hook();
    return result;
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)
{
    switch (fdwReason)
    {
    case DLL_PROCESS_VERIFIER:
        *reinterpret_cast<PVOID*>(lpvReserved) = &verifierDescriptor;
        break;

    case DLL_PROCESS_ATTACH:
        DisableThreadLibraryCalls(hinstDLL);
        OutputDebugStringW(L"NOAB: worker DLL attached\r\n");
        break;

    default:
        break;
    }

    return TRUE;
}
