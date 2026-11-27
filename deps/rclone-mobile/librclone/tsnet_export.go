package main

// C entry points for the embedded Tailscale node (deps/rclone-mobile/tsnet).
// Functions returning char* return a malloc'd JSON string the caller frees
// with CodyTsFreeString: {"ok":true[,"result":...]} or {"ok":false,"error":"..."}.

/*
#include <stdlib.h>

typedef void (*cody_ts_log_fn)(const char *line);
static void cody_ts_call_log(cody_ts_log_fn fn, const char *line) { if (fn) fn(line); }
*/
import "C"

import (
	"encoding/json"
	"sync"
	"time"
	"unsafe"

	"github.com/54zhien/cody-rclone/tsnet"
)

var (
	tsLogMu sync.Mutex
	tsLogFn C.cody_ts_log_fn
)

func tsResult(extra string, err error) *C.char {
	if err != nil {
		b, _ := json.Marshal(map[string]any{"ok": false, "error": err.Error()})
		return C.CString(string(b))
	}
	if extra != "" {
		return C.CString(`{"ok":true,"result":` + extra + `}`)
	}
	return C.CString(`{"ok":true}`)
}

// CodyTsSetLogger registers where the node's log lines go (the app forwards
// them to AppLogger). NULL turns logging off.
//
//export CodyTsSetLogger
func CodyTsSetLogger(fn C.cody_ts_log_fn) {
	tsLogMu.Lock()
	tsLogFn = fn
	tsLogMu.Unlock()
	if fn == nil {
		tsnet.SetLogger(nil)
		return
	}
	tsnet.SetLogger(func(line string) {
		tsLogMu.Lock()
		f := tsLogFn
		tsLogMu.Unlock()
		cs := C.CString(line)
		C.cody_ts_call_log(f, cs)
		C.free(unsafe.Pointer(cs))
	})
}

// CodyTsSetDefaultRouteInterface passes the OS default interface name (from
// NWPathMonitor, e.g. "en0" / "pdp_ip0") to the node's network monitor.
//
//export CodyTsSetDefaultRouteInterface
func CodyTsSetDefaultRouteInterface(ifName *C.char) {
	tsnet.SetDefaultRouteInterface(C.GoString(ifName))
}

// CodyTsStart starts the node. authKey may be empty (interactive login; the
// AuthURL then shows up in CodyTsStatus).
//
//export CodyTsStart
func CodyTsStart(authKey, hostname, stateDir *C.char) *C.char {
	return tsResult("", tsnet.Start(C.GoString(authKey), C.GoString(hostname), C.GoString(stateDir)))
}

// CodyTsSetAcceptRoutes accepts (1) or ignores (0) subnet routes that
// peers advertise. Tailscale defaults to accepting; the app sets its own
// setting (default off) after CodyTsStart.
//
//export CodyTsSetAcceptRoutes
func CodyTsSetAcceptRoutes(on C.int) *C.char {
	return tsResult("", tsnet.SetAcceptRoutes(on != 0))
}

// CodyTsStop stops the SOCKS listener and the node (the login is kept).
//
//export CodyTsStop
func CodyTsStop() *C.char {
	return tsResult("", tsnet.Stop())
}

// CodyTsLogout signs the node out and stops it.
//
//export CodyTsLogout
func CodyTsLogout() *C.char {
	return tsResult("", tsnet.Logout())
}

// CodyTsStatus returns the node status as JSON.
//
//export CodyTsStatus
func CodyTsStatus() *C.char {
	return tsResult(tsnet.StatusJSON(), nil)
}

// CodyTsRoutes returns the prefixes currently reachable through the tailnet
// and the MagicDNS suffix.
//
//export CodyTsRoutes
func CodyTsRoutes() *C.char {
	return tsResult(tsnet.RoutesJSON(), nil)
}

// CodyTsDialTest dials addr ("host:port") through the tailnet.
//
//export CodyTsDialTest
func CodyTsDialTest(addr *C.char, timeoutMs C.int) *C.char {
	d, err := tsnet.DialTest(C.GoString(addr), time.Duration(timeoutMs)*time.Millisecond)
	if err != nil {
		return tsResult("", err)
	}
	b, _ := json.Marshal(map[string]any{"ms": d.Milliseconds()})
	return tsResult(string(b), nil)
}

// CodyTsListenSocks starts a local SOCKS5 proxy on addr ("127.0.0.1:0" picks
// a port). The result carries the bound address and generated credentials.
//
//export CodyTsListenSocks
func CodyTsListenSocks(addr *C.char) *C.char {
	return tsResult(tsnet.ListenSocks(C.GoString(addr)))
}

// CodyTsFreeString frees a string returned by the functions above.
//
//export CodyTsFreeString
func CodyTsFreeString(s *C.char) {
	C.free(unsafe.Pointer(s))
}
