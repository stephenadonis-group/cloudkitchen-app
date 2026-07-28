// Package migrations embeds the SQL migration files so they ship inside the
// binary and run at startup via the repository migration runner.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
