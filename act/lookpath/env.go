// Copyright 2022 The Git Authors. All rights reserved.
// Copyright 2022 The nektos/act Authors. All rights reserved.
// SPDX-License-Identifier: MIT

package lookpath

type Env interface {
	Getenv(name string) string
}
