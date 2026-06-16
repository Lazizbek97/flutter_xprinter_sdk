#include "xprinter_sdk_plugin.h"

// Windows headers must be included before Flutter's Windows headers.
#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <variant>
#include <vector>

namespace flutter_xprinter_sdk {
namespace {

constexpr char kMethodChannel[] = "dev.lazizbekfayziev.flutter_xprinter_sdk";
constexpr char kDiscoveryChannel[] =
    "dev.lazizbekfayziev.flutter_xprinter_sdk/discovery";

constexpr int kSuccess = 0;
constexpr int kDefaultCodePage = 0;

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodResult;

const EncodableMap *
GetArguments(const flutter::MethodCall<EncodableValue> &call) {
  const EncodableValue *arguments = call.arguments();
  if (arguments == nullptr) {
    return nullptr;
  }
  return std::get_if<EncodableMap>(arguments);
}

const EncodableValue *FindValue(const EncodableMap *arguments,
                                const char *key) {
  if (arguments == nullptr) {
    return nullptr;
  }
  const auto iterator = arguments->find(EncodableValue(key));
  return iterator == arguments->end() ? nullptr : &iterator->second;
}

bool ReadString(const EncodableMap *arguments, const char *key,
                std::string *value) {
  const EncodableValue *encoded = FindValue(arguments, key);
  if (encoded == nullptr) {
    return false;
  }
  const auto *string_value = std::get_if<std::string>(encoded);
  if (string_value == nullptr) {
    return false;
  }
  *value = *string_value;
  return true;
}

int ReadInt(const EncodableMap *arguments, const char *key, int fallback) {
  const EncodableValue *encoded = FindValue(arguments, key);
  if (encoded == nullptr) {
    return fallback;
  }
  if (const auto *value = std::get_if<int32_t>(encoded)) {
    return *value;
  }
  if (const auto *value = std::get_if<int64_t>(encoded)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

bool ReadBool(const EncodableMap *arguments, const char *key, bool fallback) {
  const EncodableValue *encoded = FindValue(arguments, key);
  if (encoded == nullptr) {
    return fallback;
  }
  const auto *value = std::get_if<bool>(encoded);
  return value == nullptr ? fallback : *value;
}

const std::vector<uint8_t> *ReadBytes(const EncodableMap *arguments,
                                      const char *key) {
  const EncodableValue *encoded = FindValue(arguments, key);
  return encoded == nullptr ? nullptr
                            : std::get_if<std::vector<uint8_t>>(encoded);
}

std::wstring Utf8ToWide(const std::string &value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring converted(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), converted.data(), size);
  return converted;
}

std::string WideToCodePage(const std::wstring &value, UINT code_page) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(code_page, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string converted(size, '\0');
  WideCharToMultiByte(code_page, 0, value.data(),
                      static_cast<int>(value.size()), converted.data(), size,
                      nullptr, nullptr);
  return converted;
}

UINT WindowsCodePageForPrinterCodePage(int page) {
  switch (page) {
  case 0:
    return 437;
  case 2:
    return 850;
  case 3:
    return 860;
  case 4:
    return 863;
  case 5:
    return 865;
  case 16:
    return 1252;
  case 17:
    return 866;
  case 19:
    return 858;
  default:
    return CP_ACP;
  }
}

std::string EncodePrinterText(const std::string &utf8, int printer_code_page) {
  const std::wstring wide = Utf8ToWide(utf8);
  if (wide.empty() && !utf8.empty()) {
    return utf8;
  }
  const std::string converted = WideToCodePage(
      wide, WindowsCodePageForPrinterCodePage(printer_code_page));
  return converted.empty() && !utf8.empty() ? utf8 : converted;
}

std::wstring ExecutableDirectory() {
  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                    static_cast<DWORD>(buffer.size()));
  while (length == buffer.size()) {
    buffer.resize(buffer.size() * 2);
    length = GetModuleFileNameW(nullptr, buffer.data(),
                                static_cast<DWORD>(buffer.size()));
  }
  if (length == 0) {
    return std::wstring();
  }
  std::wstring path(buffer.data(), length);
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring()
                                         : path.substr(0, separator);
}

std::wstring BuildPortSetting(const std::string &type,
                              const std::string &address) {
  if (type == "usb") {
    return Utf8ToWide(address.empty() ? "USB," : "USB," + address);
  }
  if (type == "tcp") {
    std::string normalized = address;
    const size_t colon = normalized.rfind(':');
    if (colon != std::string::npos && normalized.find(':') == colon) {
      normalized[colon] = ',';
    }
    return Utf8ToWide("NET," + normalized);
  }
  return std::wstring();
}

std::string SdkErrorMessage(int code) {
  switch (code) {
  case -1:
    return "invalid parameter";
  case -2:
    return "invalid handle";
  case -3:
    return "not implemented";
  case -4:
    return "insufficient memory";
  case -5:
    return "image load failed";
  case -6:
    return "invalid image format";
  case -7:
    return "invalid I/O handle";
  case -8:
    return "failed to open port";
  case -9:
    return "failed to write data";
  case -10:
    return "write timed out";
  case -11:
    return "failed to read data";
  case -12:
    return "read timed out";
  case -16:
    return "invalid USB path";
  case -17:
    return "USB device not found";
  default:
    return "SDK error";
  }
}

std::string ErrorWithCode(const std::string &operation, int code) {
  std::ostringstream message;
  message << operation << " failed: " << SdkErrorMessage(code)
          << " (code=" << code << ")";
  return message.str();
}

std::string ImageExtension(const std::vector<uint8_t> &bytes) {
  if (bytes.size() >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 &&
      bytes[2] == 0x4E && bytes[3] == 0x47) {
    return ".png";
  }
  if (bytes.size() >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return ".jpg";
  }
  if (bytes.size() >= 2 && bytes[0] == 'B' && bytes[1] == 'M') {
    return ".bmp";
  }
  if (bytes.size() >= 6 && bytes[0] == 'G' && bytes[1] == 'I' &&
      bytes[2] == 'F') {
    return ".gif";
  }
  return std::string();
}

std::wstring CreateTemporaryImage(const std::vector<uint8_t> &bytes) {
  const std::string extension = ImageExtension(bytes);
  if (extension.empty()) {
    return std::wstring();
  }

  wchar_t temp_directory[MAX_PATH + 1] = {};
  const DWORD length = GetTempPathW(MAX_PATH, temp_directory);
  if (length == 0 || length > MAX_PATH) {
    return std::wstring();
  }

  static std::atomic<unsigned long> sequence{0};
  std::wostringstream name;
  name << temp_directory << L"xprinter_" << GetCurrentProcessId() << L"_"
       << sequence.fetch_add(1) << Utf8ToWide(extension);
  const std::wstring path = name.str();

  std::ofstream output(std::filesystem::path(path),
                       std::ios::binary | std::ios::trunc);
  if (!output) {
    return std::wstring();
  }
  output.write(reinterpret_cast<const char *>(bytes.data()),
               static_cast<std::streamsize>(bytes.size()));
  output.close();
  return output ? path : std::wstring();
}

std::string PathForAnsiSdk(const std::wstring &path) {
  wchar_t short_path[MAX_PATH + 1] = {};
  const DWORD length = GetShortPathNameW(path.c_str(), short_path, MAX_PATH);
  const std::wstring compatible = length > 0 && length <= MAX_PATH
                                      ? std::wstring(short_path, length)
                                      : path;
  return WideToCodePage(compatible, CP_ACP);
}

int NormalizePrinterStatus(unsigned int status) {
  int normalized = 0;
  if ((status & 0x04) != 0) {
    normalized |= 0x10;
  }
  if ((status & 0x08) != 0) {
    normalized |= 0x08;
  }
  if ((status & 0x20) != 0) {
    normalized |= 0x20;
  }
  if ((status & 0x40) != 0) {
    normalized |= 0x40;
  }
  return normalized;
}

class SdkApi {
public:
  using InitPrinterFn = void *(*)(const wchar_t *);
  using ReleasePrinterFn = int (*)(void *);
  using OpenPortFn = int (*)(void *, const wchar_t *);
  using ClosePortFn = int (*)(void *);
  using WriteDataFn = int (*)(void *, unsigned char *, int);
  using PrinterInitializeFn = int (*)(void *);
  using FeedLineFn = int (*)(void *, int);
  using CutPaperFn = int (*)(void *, int);
  using SetAlignFn = int (*)(void *, int);
  using PrintBarCodeFn = int (*)(void *, int, const char *, int, int, int, int);
  using PrintSymbolFn = int (*)(void *, int, const char *, int, int, int, int);
  using PrintImageFn = int (*)(void *, const char *, int);
  using GetPrinterStateFn = int (*)(void *, unsigned int *);
  using SetCodePageFn = int (*)(void *, int);

  ~SdkApi() {
    if (module_ != nullptr) {
      FreeLibrary(module_);
    }
  }

  bool Load() {
    if (module_ != nullptr) {
      return true;
    }

    const std::wstring directory = ExecutableDirectory();
    const std::wstring dll_path = directory.empty()
                                      ? L"printer.sdk.dll"
                                      : directory + L"\\printer.sdk.dll";
    module_ = LoadLibraryExW(dll_path.c_str(), nullptr,
                             LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                                 LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (module_ == nullptr) {
      std::ostringstream message;
      message << "Could not load printer.sdk.dll (Windows error "
              << GetLastError() << ")";
      error_ = message.str();
      return false;
    }

    return Resolve("InitPrinter", &init_printer) &&
           Resolve("ReleasePrinter", &release_printer) &&
           Resolve("OpenPort", &open_port) &&
           Resolve("ClosePort", &close_port) &&
           Resolve("WriteData", &write_data) &&
           Resolve("PrinterInitialize", &printer_initialize) &&
           Resolve("FeedLine", &feed_line) && Resolve("CutPaper", &cut_paper) &&
           Resolve("SetAlign", &set_align) &&
           Resolve("PrintBarCode", &print_bar_code) &&
           Resolve("PrintSymbol", &print_symbol) &&
           Resolve("PrintImage", &print_image) &&
           Resolve("GetPrinterState", &get_printer_state) &&
           Resolve("SetCodePage", &set_code_page);
  }

  const std::string &error() const { return error_; }

  InitPrinterFn init_printer = nullptr;
  ReleasePrinterFn release_printer = nullptr;
  OpenPortFn open_port = nullptr;
  ClosePortFn close_port = nullptr;
  WriteDataFn write_data = nullptr;
  PrinterInitializeFn printer_initialize = nullptr;
  FeedLineFn feed_line = nullptr;
  CutPaperFn cut_paper = nullptr;
  SetAlignFn set_align = nullptr;
  PrintBarCodeFn print_bar_code = nullptr;
  PrintSymbolFn print_symbol = nullptr;
  PrintImageFn print_image = nullptr;
  GetPrinterStateFn get_printer_state = nullptr;
  SetCodePageFn set_code_page = nullptr;

private:
  template <typename T> bool Resolve(const char *name, T *target) {
    *target = reinterpret_cast<T>(GetProcAddress(module_, name));
    if (*target != nullptr) {
      return true;
    }
    error_ = std::string("printer.sdk.dll is missing export ") + name;
    FreeLibrary(module_);
    module_ = nullptr;
    return false;
  }

  HMODULE module_ = nullptr;
  std::string error_;
};

} // namespace

class XprinterSdkPlugin::Impl {
public:
  ~Impl() { Disconnect(); }

  void HandleMethodCall(const flutter::MethodCall<EncodableValue> &method_call,
                        std::unique_ptr<MethodResult<EncodableValue>> result) {
    const std::string &method = method_call.method_name();
    const EncodableMap *arguments = GetArguments(method_call);

    if (method == "connect") {
      Connect(arguments, std::move(result));
    } else if (method == "disconnect") {
      Disconnect();
      result->Success();
    } else if (method == "isConnected") {
      result->Success(EncodableValue(connected_));
    } else if (method == "getBondedDevices") {
      result->Success(EncodableValue(flutter::EncodableList()));
    } else if (method == "initialize") {
      Initialize(std::move(result));
    } else if (method == "printText") {
      PrintText(arguments, std::move(result));
    } else if (method == "printBitmap") {
      PrintBitmap(arguments, std::move(result));
    } else if (method == "printHorizontalLine") {
      PrintHorizontalLine(arguments, std::move(result));
    } else if (method == "printQRCode") {
      PrintQrCode(arguments, std::move(result));
    } else if (method == "printBarCode") {
      PrintBarcode(arguments, std::move(result));
    } else if (method == "feedLine") {
      FeedLineCall(arguments, std::move(result));
    } else if (method == "cutPaper") {
      CutPaperCall(arguments, std::move(result));
    } else if (method == "selectCodePage") {
      SelectCodePage(arguments, std::move(result));
    } else if (method == "setAlignment") {
      SetAlignment(arguments, std::move(result));
    } else if (method == "getStatus") {
      GetStatus(std::move(result));
    } else if (method == "sendRawCommand") {
      SendRawCommand(arguments, std::move(result));
    } else {
      result->NotImplemented();
    }
  }

private:
  bool EnsureConnected(MethodResult<EncodableValue> *result) {
    if (!connected_ || printer_ == nullptr) {
      result->Error("not_connected", "no active printer connection");
      return false;
    }
    return true;
  }

  void Connect(const EncodableMap *arguments,
               std::unique_ptr<MethodResult<EncodableValue>> result) {
    std::string type;
    std::string address;
    if (!ReadString(arguments, "type", &type) ||
        !ReadString(arguments, "address", &address)) {
      result->Error("invalid_args",
                    "connect requires 'type' and 'address' string arguments");
      return;
    }
    Disconnect();
    if (type == "bluetooth") {
      result->Error(
          "unsupported_transport",
          "The XPrinter Windows SDK does not support direct Bluetooth "
          "connections. Use USB or TCP.");
      return;
    }
    if (type != "usb" && type != "tcp") {
      result->Error("invalid_args", "unknown connection type: " + type);
      return;
    }
    if (type == "tcp" && address.empty()) {
      result->Error("invalid_args", "TCP address must not be empty");
      return;
    }

    if (!api_.Load()) {
      result->Error("sdk_unavailable", api_.error());
      return;
    }

    printer_ = api_.init_printer(L"");
    if (printer_ == nullptr) {
      result->Error("connect_fail", "InitPrinter returned null");
      return;
    }

    const std::wstring setting = BuildPortSetting(type, address);
    const int code = api_.open_port(printer_, setting.c_str());
    if (code != kSuccess) {
      api_.release_printer(printer_);
      printer_ = nullptr;
      result->Error("connect_fail", ErrorWithCode("OpenPort", code));
      return;
    }

    connected_ = true;
    current_code_page_ = kDefaultCodePage;
    result->Success(EncodableValue(true));
  }

  void Disconnect() {
    if (printer_ != nullptr && api_.close_port != nullptr) {
      api_.close_port(printer_);
    }
    if (printer_ != nullptr && api_.release_printer != nullptr) {
      api_.release_printer(printer_);
    }
    printer_ = nullptr;
    connected_ = false;
    current_code_page_ = kDefaultCodePage;
  }

  template <typename Function, typename... Arguments>
  void RunSdkCall(const std::string &operation, Function function,
                  std::unique_ptr<MethodResult<EncodableValue>> result,
                  Arguments... arguments) {
    if (!EnsureConnected(result.get())) {
      return;
    }
    const int code = function(printer_, arguments...);
    if (code != kSuccess) {
      result->Error("print_fail", ErrorWithCode(operation, code));
      return;
    }
    result->Success();
  }

  void Initialize(std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (!EnsureConnected(result.get())) {
      return;
    }
    const int code = api_.printer_initialize(printer_);
    if (code != kSuccess) {
      result->Error("print_fail", ErrorWithCode("PrinterInitialize", code));
      return;
    }
    current_code_page_ = kDefaultCodePage;
    result->Success();
  }

  void PrintText(const EncodableMap *arguments,
                 std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (!EnsureConnected(result.get())) {
      return;
    }
    std::string text;
    if (!ReadString(arguments, "text", &text)) {
      result->Error("invalid_args", "printText requires 'text'");
      return;
    }

    const int alignment = ReadInt(arguments, "alignment", 0);
    const int attribute = ReadInt(arguments, "attribute", 0);
    const int text_size = ReadInt(arguments, "textSize", 0);
    const bool font_b = (attribute & 0x01) != 0;
    const bool bold = (attribute & 0x08) != 0;
    const bool reverse = (attribute & 0x10) != 0;
    const int underline =
        (attribute & 0x100) != 0 ? 2 : ((attribute & 0x80) != 0 ? 1 : 0);

    std::vector<uint8_t> data = {
        0x1B, 0x61, static_cast<uint8_t>(std::clamp(alignment, 0, 2)),
        0x1B, 0x4D, static_cast<uint8_t>(font_b ? 1 : 0),
        0x1B, 0x45, static_cast<uint8_t>(bold ? 1 : 0),
        0x1D, 0x42, static_cast<uint8_t>(reverse ? 1 : 0),
        0x1B, 0x2D, static_cast<uint8_t>(underline),
        0x1D, 0x21, static_cast<uint8_t>(text_size & 0x77),
    };
    const std::string encoded = EncodePrinterText(text, current_code_page_);
    data.insert(data.end(), encoded.begin(), encoded.end());
    if (data.empty() || data.back() != '\n') {
      data.push_back('\n');
    }

    WriteBytes("printText", data, std::move(result));
  }

  void PrintBitmap(const EncodableMap *arguments,
                   std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (!EnsureConnected(result.get())) {
      return;
    }
    const std::vector<uint8_t> *bytes = ReadBytes(arguments, "bytes");
    if (bytes == nullptr || bytes->empty()) {
      result->Error("invalid_args", "printBitmap requires non-empty 'bytes'");
      return;
    }

    const std::wstring path = CreateTemporaryImage(*bytes);
    if (path.empty()) {
      result->Error("invalid_args",
                    "printBitmap supports PNG, JPEG, BMP, or GIF image bytes");
      return;
    }

    const int alignment = ReadInt(arguments, "alignment", 1);
    int code = api_.set_align(printer_, std::clamp(alignment, 0, 2));
    if (code == kSuccess) {
      const std::string sdk_path = PathForAnsiSdk(path);
      code = sdk_path.empty() ? -5
                              : api_.print_image(printer_, sdk_path.c_str(), 0);
    }
    DeleteFileW(path.c_str());

    if (code != kSuccess) {
      result->Error("print_fail", ErrorWithCode("PrintImage", code));
      return;
    }
    result->Success();
  }

  void
  PrintHorizontalLine(const EncodableMap *arguments,
                      std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (!EnsureConnected(result.get())) {
      return;
    }
    const int width_dots = ReadInt(arguments, "widthDots", 384);
    const int height_rows = ReadInt(arguments, "heightRows", 4);
    const int alignment = ReadInt(arguments, "alignment", 1);
    if (width_dots <= 0 || height_rows <= 0 || width_dots > 65535 ||
        height_rows > 65535) {
      result->Error("invalid_args",
                    "widthDots and heightRows must be between 1 and 65535");
      return;
    }

    const int align_code =
        api_.set_align(printer_, std::clamp(alignment, 0, 2));
    if (align_code != kSuccess) {
      result->Error("print_fail", ErrorWithCode("SetAlign", align_code));
      return;
    }

    const int width_bytes = (width_dots + 7) / 8;
    std::vector<uint8_t> data = {
        0x1D,
        0x76,
        0x30,
        0x00,
        static_cast<uint8_t>(width_bytes & 0xFF),
        static_cast<uint8_t>((width_bytes >> 8) & 0xFF),
        static_cast<uint8_t>(height_rows & 0xFF),
        static_cast<uint8_t>((height_rows >> 8) & 0xFF),
    };
    data.resize(data.size() + width_bytes * height_rows, 0xFF);
    WriteBytes("printHorizontalLine", data, std::move(result));
  }

  void PrintQrCode(const EncodableMap *arguments,
                   std::unique_ptr<MethodResult<EncodableValue>> result) {
    std::string content;
    if (!ReadString(arguments, "content", &content)) {
      result->Error("invalid_args", "printQRCode requires 'content'");
      return;
    }
    const int module_size = ReadInt(arguments, "moduleSize", 4);
    const int correction = ReadInt(arguments, "errorCorrection", 49);
    const int alignment = ReadInt(arguments, "alignment", 1);
    // Both vendor sample applications use 49 for QR model 1, despite the
    // manual's conflicting barcode-type table.
    RunSdkCall("PrintSymbol", api_.print_symbol, std::move(result), 49,
               content.c_str(), correction, module_size, module_size,
               alignment);
  }

  void PrintBarcode(const EncodableMap *arguments,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
    std::string content;
    if (!ReadString(arguments, "content", &content)) {
      result->Error("invalid_args", "printBarCode requires 'content'");
      return;
    }
    RunSdkCall("PrintBarCode", api_.print_bar_code, std::move(result),
               ReadInt(arguments, "type", 73), content.c_str(),
               ReadInt(arguments, "width", 2), ReadInt(arguments, "height", 80),
               ReadInt(arguments, "alignment", 1),
               ReadInt(arguments, "hri", 0));
  }

  void FeedLineCall(const EncodableMap *arguments,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
    const int lines = ReadInt(arguments, "lines", 1);
    if (lines < 0 || lines > 255) {
      result->Error("invalid_args", "lines must be between 0 and 255");
      return;
    }
    RunSdkCall("FeedLine", api_.feed_line, std::move(result), lines);
  }

  void CutPaperCall(const EncodableMap *arguments,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
    const bool half = ReadBool(arguments, "half", true);
    RunSdkCall("CutPaper", api_.cut_paper, std::move(result), half ? 1 : 0);
  }

  void SelectCodePage(const EncodableMap *arguments,
                      std::unique_ptr<MethodResult<EncodableValue>> result) {
    const int page = ReadInt(arguments, "page", 17);
    if (!EnsureConnected(result.get())) {
      return;
    }
    const int code = api_.set_code_page(printer_, page);
    if (code != kSuccess) {
      result->Error("print_fail", ErrorWithCode("SetCodePage", code));
      return;
    }
    current_code_page_ = page;
    result->Success();
  }

  void SetAlignment(const EncodableMap *arguments,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
    RunSdkCall("SetAlign", api_.set_align, std::move(result),
               std::clamp(ReadInt(arguments, "alignment", 0), 0, 2));
  }

  void GetStatus(std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (!EnsureConnected(result.get())) {
      return;
    }
    unsigned int status = 0;
    const int code = api_.get_printer_state(printer_, &status);
    if (code != kSuccess) {
      result->Success(EncodableValue(-1));
      return;
    }
    result->Success(EncodableValue(NormalizePrinterStatus(status)));
  }

  void SendRawCommand(const EncodableMap *arguments,
                      std::unique_ptr<MethodResult<EncodableValue>> result) {
    const std::vector<uint8_t> *bytes = ReadBytes(arguments, "bytes");
    if (bytes == nullptr) {
      result->Error("invalid_args", "sendRawCommand requires 'bytes'");
      return;
    }
    WriteBytes("sendRawCommand", *bytes, std::move(result));
  }

  void WriteBytes(const std::string &operation,
                  const std::vector<uint8_t> &bytes,
                  std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (!EnsureConnected(result.get())) {
      return;
    }
    if (bytes.empty()) {
      result->Success();
      return;
    }
    std::vector<uint8_t> mutable_bytes(bytes);
    const int code = api_.write_data(printer_, mutable_bytes.data(),
                                     static_cast<int>(mutable_bytes.size()));
    if (code != kSuccess) {
      result->Error("print_fail", ErrorWithCode(operation, code));
      return;
    }
    result->Success();
  }

  SdkApi api_;
  void *printer_ = nullptr;
  bool connected_ = false;
  int current_code_page_ = kDefaultCodePage;
};

void XprinterSdkPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), kMethodChannel,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<XprinterSdkPlugin>();
  method_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  auto discovery_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), kDiscoveryChannel,
          &flutter::StandardMethodCodec::GetInstance());
  discovery_channel->SetStreamHandler(std::make_unique<
                                      flutter::StreamHandlerFunctions<>>(
      [](const EncodableValue *,
         std::unique_ptr<flutter::EventSink<EncodableValue>> &&)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        return std::make_unique<flutter::StreamHandlerError<EncodableValue>>(
            "unsupported_transport",
            "Bluetooth discovery is not supported by the XPrinter "
            "Windows SDK",
            nullptr);
      },
      [](const EncodableValue *)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        return nullptr;
      }));

  registrar->AddPlugin(std::move(plugin));
}

XprinterSdkPlugin::XprinterSdkPlugin() : impl_(std::make_unique<Impl>()) {}

XprinterSdkPlugin::~XprinterSdkPlugin() = default;

void XprinterSdkPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &method_call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  impl_->HandleMethodCall(method_call, std::move(result));
}

} // namespace flutter_xprinter_sdk
