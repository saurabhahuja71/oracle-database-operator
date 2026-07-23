package commons

import (
	"fmt"
	"strings"
	"testing"
)

func TestDisableFSFOCMDTerminatesStopObserverCommand(t *testing.T) {
	script := fmt.Sprintf(DisableFSFOCMD, "sidb-standby-dg")

	if !strings.Contains(script, "STOP OBSERVER sidb-standby-dg;\nDISABLE FAST_START FAILOVER;") {
		t.Fatalf("expected STOP OBSERVER and DISABLE FAST_START FAILOVER to be separate DGMGRL commands, got %q", script)
	}
	if strings.Contains(script, "sidb-standby-dg DISABLE") {
		t.Fatalf("STOP OBSERVER command is missing a terminator before DISABLE FAST_START FAILOVER: %q", script)
	}
}
