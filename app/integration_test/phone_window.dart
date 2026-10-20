// Resizes the Windows test app's window to a phone shape (Win32 via FFI), so
// the map scroll benchmark lays the map out like on a phone: 412 dp wide
// at a device pixel ratio of [kPhoneWindowDpr].
import 'dart:ffi';

import 'package:flutter/foundation.dart';

const double kPhoneWindowDpr = 1.3;

typedef _EnumProc = Int32 Function(IntPtr hwnd, IntPtr lParam);

int _found = 0;
int _pid = 0;
late final int Function(int hwnd, Pointer<Uint32> pid) _threadProcessId;
late final int Function(int hwnd) _isVisible;
late final int Function(int hwnd, Pointer<Int32> rect) _clientRect;
late final int Function(int hwnd, Pointer<Uint16> name, int max) _className;

int _onWindow(int hwnd, int lParam) {
  final out = Pointer<Uint32>.fromAddress(lParam);
  _threadProcessId(hwnd, out);
  if (out.value != _pid) return 1;
  final name = Pointer<Uint16>.fromAddress(lParam + 8);
  final n = _className(hwnd, name, 100);
  final cls = String.fromCharCodes([for (var i = 0; i < n; i++) name[i]]);
  if (cls == 'FLUTTER_RUNNER_WIN32_WINDOW' || (_found == 0 && _isVisible(hwnd) != 0)) _found = hwnd;
  return cls == 'FLUTTER_RUNNER_WIN32_WINDOW' ? 0 : 1;
}

bool _resized = false;

Future<void> resizePhoneWindow() async {
  if (_resized) return;
  _resized = true;
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final heap = kernel32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap')();
  final alloc = kernel32.lookupFunction<Pointer<Int32> Function(IntPtr, Uint32, IntPtr), Pointer<Int32> Function(int, int, int)>(
    'HeapAlloc',
  );
  _pid = kernel32.lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId')();
  _threadProcessId = user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>(
    'GetWindowThreadProcessId',
  );
  _isVisible = user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
  _clientRect = user32.lookupFunction<Int32 Function(IntPtr, Pointer<Int32>), int Function(int, Pointer<Int32>)>('GetClientRect');
  _className = user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Int32), int Function(int, Pointer<Uint16>, int)>(
    'GetClassNameW',
  );
  final enumWindows = user32
      .lookupFunction<Int32 Function(Pointer<NativeFunction<_EnumProc>>, IntPtr), int Function(Pointer<NativeFunction<_EnumProc>>, int)>(
        'EnumWindows',
      );
  final setPos = user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)
  >('SetWindowPos');

  final mem = alloc(heap, 8, 256);
  enumWindows(Pointer.fromFunction<_EnumProc>(_onWindow, 0), mem.address);
  if (_found == 0) {
    debugPrint('[perf] no window found to resize');
    return;
  }
  // Client width 412 dp; as tall as the screen allows.
  const wantW = 412 * kPhoneWindowDpr;
  for (var pass = 0; pass < 2; pass++) {
    _clientRect(_found, mem);
    final cw = mem[2] - mem[0];
    final ch = mem[3] - mem[1];
    // Window size = client + borders; measure the borders from the current size.
    final rect = alloc(heap, 8, 16);
    user32.lookupFunction<Int32 Function(IntPtr, Pointer<Int32>), int Function(int, Pointer<Int32>)>('GetWindowRect')(
      _found,
      rect,
    );
    final ww = rect[2] - rect[0], wh = rect[3] - rect[1];
    final bw = ww - cw, bh = wh - ch;
    // SWP_NOZORDER | SWP_NOACTIVATE
    setPos(_found, 0, 0, 0, wantW.round() + bw, 1060, 0x0004 | 0x0010);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    debugPrint('[perf] window client was ${cw}x$ch, borders ${bw}x$bh');
  }
}
