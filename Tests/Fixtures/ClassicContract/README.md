# Classic data contract fixtures

These fixtures were copied from `mylxsw/typeflux` commit
`fcf8b7bf723644f9d51159aadf6ef62d2c900674` (PR #767),
`Tests/Fixtures/ClassicContract/`. The data files are unchanged.

The four current plists represent independent defaults domains with the same
model registry and different rewrite model references. They cover OpenAI,
Typeflux Cloud, Ollama, and a custom endpoint. The JSON files contain a
persona, activation hotkey, and vocabulary entries. The SQLite file contains
one dictation record and must be opened from a temporary copy because the
history store can write WAL sidecars. The v0.4.0 plist is the frozen legacy
defaults snapshot.

Run `make test SUITE=ClassicCompatibilityContractTests` on macOS.
