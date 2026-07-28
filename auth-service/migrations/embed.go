// Package migrations embeds the SQL migration files so they ship inside the
// binary and can be executed at startup by the repository migration runner.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
