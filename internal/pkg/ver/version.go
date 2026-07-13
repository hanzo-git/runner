// Copyright 2023 The Git Authors. All rights reserved.
// SPDX-License-Identifier: MIT

package ver

// go build -ldflags "-X github.com/hanzo-git/runner/internal/pkg/ver.version=1.2.3"
var version = "dev"

func Version() string {
	return version
}
