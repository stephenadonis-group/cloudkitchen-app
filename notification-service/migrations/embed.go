// Package migrations embeds the service's SQL migration files so they ship inside
// the compiled binary. The repository migration runner consumes FS().
package migrations

import (
	"embed"
	"io/fs"
)

//go:embed *.sql
var files embed.FS

// FS returns a read-only filesystem rooted at the migrations directory,
// containing every *.sql file in lexical order.
func FS() fs.FS {
	return files
}
